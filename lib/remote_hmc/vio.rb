class Vio < Lpar
	
	attr_reader  :available_disks
	
    def initialize(options_hash)
    
        raise StandardError.new("A VIO cannot be defined without a managing HMC") if options_hash[:hmc].nil?
        raise StandardError.new("A VIO cannot be defined without a name") if options_hash[:name].nil?
        raise StandardError.new("A VIO cannot be difined without specifying the frame that it resides on") if options_hash[:frame].nil?
        
        @name  = options_hash[:name]
        @hmc   = options_hash[:hmc]
        @frame = options_hash[:frame]
        
        #Set to 'default' values to leverage parent class' constructor
        options_hash[:des_proc]   = "1.0"
        options_hash[:des_vcpu]       = "1"
        options_hash[:des_mem]       = "4096"
        options_hash[:current_profile]      = current_profile
        options_hash[:hostname]             = @name
        
        
        super(options_hash)
        
        @available_disks = list_available_disks
    end
		
    #Assign Disk/Logical Volume to a vSCSI Host Adapter
    def assign_disk_vhost(disk, vtd, vhost)
        command = "mkvdev -vdev #{disk.name} -dev #{vtd} -vadapter #{vhost}"
        execute_vios_cmd(command)
    end
    
    #Execute VIOS commands via HMC
    def  execute_vios_cmd(command)
        hmc.execute_cmd "viosvrcmd -m #{frame} -p #{name} -c \" #{command} \""
    end
    
    #Execute VIOS commands via HMC grepping for a specific item.
    def  execute_vios_cmd_grep(command, grep_for)
        hmc.execute_cmd "viosvrcmd -m #{frame} -p #{name} -c \" #{command} \" | grep #{grep_for}"
    end
    
    
    #Get a list of all disknames attached to a vhost
    def get_attached_disknames(vhost)
        cmd = "lsmap -vadapter #{vhost} -field backing -fmt :"
        diskname_output = execute_vios_cmd(cmd).chomp
        
        return diskname_output.split(/:/)
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
    
    #Get VIOS version
    def get_vio_version
        command = "ioslevel"
        execute_vios_cmd(command)
    end
    
    #List unmapped disks on VIOS
    #      lspv -free  doesn't include disks that have been mapped before and contain a 'VGID'
    def list_available_disks
        command = "lspv -avail -fmt : -field name pvid size"
        all_disk_output = execute_vios_cmd(command)
        mapped_disks = list_all_mapped_disks
        unmapped_disks = []
        all_disk_output.each_line do |line|
            line.chomp!
            disk_name,disk_pvid,disk_size = line.split(/:/)
            if !mapped_disks.include?(disk_name)
                unmapped_disks.push(Lun.new(disk_name,disk_pvid,disk_size))
            end
        end
        
        #Update the objects local list of available disks and return it
        @available_disks = unmapped_disks
        return unmapped_disks
    end
    
    #List all Disk Mappings
    def list_all_mapped_disks
        command = "lsmap -all -type disk"
        result = execute_vios_cmd_grep(command, "Backing")
        mapped_disks = []
        result.each_line do |line|
            line.chomp!
            line_elements=line.split(/[[:blank:]]+/)
            #3rd element should be disk name, since first is 'Backing' and
            #the second is 'device'
            disk_name = line_elements[2]
            mapped_disks.push(disk_name) if !mapped_disks.include?(disk_name)
        end
        return mapped_disks
    end
    
    #List Shared Ethernet Adapters on VIOS
    def list_shared_eth_adapters
        command = "lsmap -all -net"
        execute_vios_cmd(command)
    end
    
    #Use this in coordination with another VIO to find an available disk between the both of them
    def select_any_avail_disk(frame, vio1, vio2)
        primary_vio_disks = list_available_disks(frame,vio1) 
        secondary_vio_disks = list_available_disks(frame,vio2)
        
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
    
    #Reboot VIOS
    def reboot
        command ="shutdown -restart"
        execute_vios_cmd(command)
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
    def remove_disk_from_vhost(diskname)
        command = "rmvdev -vdev #{diskname}"
        execute_vios_cmd(command)
    end
    
    #Remove a Virtual SCSI Host Adapter
    def remove_vhost(vhost)
        command = "rmdev -dev #{vhost}"
        execute_vios_cmd(command)
    end
 
end