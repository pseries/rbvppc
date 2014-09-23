require_relative 'lpar'
require_relative 'lun'

class Vio < Lpar
	
	attr_reader  :available_disks, :used_disks
	
    def initialize(hmc,frame,name)
    
        raise StandardError.new("A VIO cannot be defined without a managing HMC") if hmc.nil?
        raise StandardError.new("A VIO cannot be defined without a name") if name.nil?
        raise StandardError.new("A VIO cannot be difined without specifying the frame that it resides on") if frame.nil?
                
        hmc.connect
        options_hash = hmc.get_lpar_info(frame,name)        
        
        #Set to 'default' values to leverage parent class' constructor
        #options_hash[:des_proc]   = "1.0"
        #options_hash[:des_vcpu]       = "1"
        #options_hash[:des_mem]       = "4096"
        #options_hash[:current_profile]      = current_profile
        #options_hash[:hostname]             = @name
                
        super(options_hash)
        
        list_available_disks
    end

    #Get VIOS version
    def get_vio_version
        command = "ioslevel"
        execute_vios_cmd(command)
    end 

    #Reboot VIOS
    def reboot
        command ="shutdown -restart"
        execute_vios_cmd(command)
    end

    ###################################
    # Execute VIOS commands
    ###################################
        
    #Execute VIOS commands via HMC
    def execute_vios_cmd(command)
        hmc.execute_cmd "viosvrcmd -m #{frame} -p #{name} -c \" #{command} \""
    end
    
    #Execute VIOS commands via HMC grepping for a specific item.
    def  execute_vios_cmd_grep(command, grep_for)
        hmc.execute_cmd "viosvrcmd -m #{frame} -p #{name} -c \" #{command} \" | grep #{grep_for}"
    end


    ####################################
    # Disk listing functions
    ####################################

    #List unmapped disks on VIOS
    #      lspv -free  doesn't include disks that have been mapped before and contain a 'VGID'
    def list_available_disks
        command = "lspv -avail -fmt : -field name pvid size"
        all_disk_output = execute_vios_cmd(command)
        mapped_disks = list_mapped_disks
        unmapped_disks = []
        all_disk_output.each_line do |line|
            line.chomp!
            disk_name,disk_pvid,disk_size = line.split(/:/)
            temp_lun = Lun.new(disk_name,disk_pvid,disk_size)
            if !mapped_disks.include?(temp_lun)
                unmapped_disks.push(temp_lun)
            end
        end
        
        #Update the objects local list of available disks and return it
        @available_disks = unmapped_disks
        return unmapped_disks
    end
	
    #List all Disk Mappings
    def list_mapped_disks
        command = "lsmap -all -type disk"
        result = execute_vios_cmd_grep(command, "Backing")

        mapped_disknames = []
        result.each_line do |line|
            line.chomp!
            line_elements=line.split(/[[:blank:]]+/)
            #3rd element should be disk name, since first is 'Backing' and
            #the second is 'device'
            disk_name = line_elements[2]
            mapped_disknames.push(disk_name) if !mapped_disknames.include?(disk_name)
        end

        command = "lspv -avail -fmt : -field name pvid size"
        full_disk_info = execute_vios_cmd_grep(command, "hdisk")
        mapped_disks = []
        full_disk_info.each_line do |line|
            line.chomp!
            disk_name,disk_pvid,disk_size = line.split(/:/)
            if mapped_disknames.include?(disk_name)
                mapped_disks.push(Lun.new(disk_name,disk_pvid,disk_size))
            end
        end

        @used_disks = mapped_disks
        return mapped_disks
    end    
    
    #Get a list of all disknames attached to a vhost
    def get_attached_disks(vhost)
        cmd = "lsmap -vadapter #{vhost} -field backing -fmt :"
        diskname_output = execute_vios_cmd(cmd).chomp
        disk_names = diskname_output.split(/:/)
        disks = []

        #After getting the list of disk names, iterate
        #over the used disks and collect an array of the
        #Luns found to be used.
        used_disks.each do |disk|
            if disk_names.include?(disk.name)
                disks.push(disk)
            end
        end
        return disks
    end
    
    #Map any disk on a pair of VIO's given the respective vhosts to map them to
    def map_any_disk(vhost, second_vio, second_vhost)
        #Select disk on each VIO
        lun_hash = select_any_avail_disk(second_vio)

        #Generate the vtd name to use on each VIO

        #Assign disk to the first VIO (self)
        assign_disk_vhost(lun_hash[:on_vio1],"vtd_name_test",vhost)

        #Assign disk to the second VIO
        second_vio.assign_disk_vhost(lun_hash[:on_vio2],"vtd_name_test",second_vhost)
    end

    #Find vhost to use when given the vSCSI adapter slot it occupies
    def find_vhost_given_virtual_slot(server_slot)
        command = "lsmap -all"
        
        #TODO: Save the vhost-to-virtualslot mapping somewhere in the class
        #and simply iterate over that, refreshing what the mappings are any
        #time an adapter is added or removed from this LPAR (???)
        
        #Execute an lsmap and grep for the line that contains the vhost
        #by finding the line that contains the physical adapter location.
        #This will definitely contain 'V#-C<slot number>' in it's name.
        result = execute_vios_cmd_grep(command,"V.-C#{server_slot}")
        raise StandardError.new("Unable to find vhost on #{name} for vSCSI adapter in slot #{server_slot}") if result.nil?
        
        #Split the result on whitespace to get the columns
        #vhost, physical location, client LPAR ID (in hex)
        mapping_cols = result.split(/[[:blank:]]+/)
        
        #The name of the vhost will be in the first column of the command output
        return mapping_cols[0]
    end
            
    #List Shared Ethernet Adapters on VIOS
    def list_shared_eth_adapters
        command = "lsmap -all -net"
        execute_vios_cmd(command)
    end
    
    #Use this in coordination with another VIO to find an available disk between the both of them
    def select_any_avail_disk(second_vio)
        primary_vio_disks = available_disks
        secondary_vio_disks = second_vio.available_disks
        
        return {} if primary_vio_disks.empty? or secondary_vio_disks.empty?
        
            vio1_lun = primary_vio_disks[0]
            vio2_lun = nil
            secondary_vio_disks.each do |lun|
            if vio1_lun == lun
                vio2_lun = lun
                break
            end
        end
    
        if vio2_lun.nil?
            raise StandardError.new("LUN with PVID #{vio1_lun.pvid} not found on #{vio2}")
        end
        # return [vio1_disk_name, vio2_disk_name]
        # return [vio1_lun, vio2_lun]
        return {:on_vio1 => vio1_lun, :on_vio2 => vio2_lun}
    end
    
    #Assign Disk/Logical Volume to a vSCSI Host Adapter
    def assign_disk_vhost(disk, vtd, vhost)
        command = "mkvdev -vdev #{disk.name} -dev #{vtd} -vadapter #{vhost}"
        execute_vios_cmd(command)

        #If this succeeds, remove disk from @available_disks
        #and add it to @used_disks
        @available_disks.delete(disk)
        @used_disks.push(disk)
    end
       
    #Recursively remove a Virtual SCSI Host Adapter
    def recursive_remove_vhost(vhost)
        command = "rmdev -dev #{vhost} -recursive"
        execute_vios_cmd(command)
    end
    
    #Remove Disk/Logical Volume from vSCSI Host Adapter
    def remove_vtd_from_vhost(vtd)
        command = "rmvdev -vtd #{vtd}"
        execute_vios_cmd(command)
    end
    
    #Remove physical disk from vhost adapter
    def remove_disk_from_vhost(disk)
        command = "rmvdev -vdev #{disk.name}"
        execute_vios_cmd(command)

        #If this succeeds, remove disk from @used_disks
        #and add it to @available_disks
        @used_disks.delete(disk)
        @available_disks.push(disk)
    end
    
    #Remove a Virtual SCSI Host Adapter
    def remove_vhost(vhost)
        command = "rmdev -dev #{vhost}"
        execute_vios_cmd(command)
    end
 
end