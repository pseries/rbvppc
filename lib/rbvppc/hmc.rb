=begin  
TODO:  
      1.go through each method and parse output
      
=end   
require_relative 'connectable_server'

class Hmc < ConnectableServer
     
   
   #Execute commands on HMC setting language to US English
   def execute_cmd(command)
       puts "export LANG=en_US.UTF-8;#{command}"
       super "export LANG=en_US.UTF-8;#{command}"
   end
   
   #Execute VIOS commands via HMC
   def  execute_vios_cmd(frame, vio, command)
       execute_cmd "viosvrcmd -m #{frame} -p #{vio} -c \" #{command} \""
   end
   
   #Execute VIOS commands via HMC grepping for a specific item.
   def  execute_vios_cmd_grep(frame, vio, command, grep_for)
       execute_cmd "viosvrcmd -m #{frame} -p #{vio} -c \" #{command} \" | grep #{grep_for}"
   end
   
   #Get the HMC version
   def get_version
       execute_cmd("lshmc -V | grep 'Version:'|cut -d':' -f2").chomp
   end  
   
   #Get the HMC Release
   def get_release
       execute_cmd("lshmc -V | grep 'Release:'|cut -d':' -f2").chomp
   end
   
   #List the Frames managed by HMC
   def get_managed_systems
       out_array = []
       result = execute_cmd "lssyscfg -r sys -F name"
       for x in result.split("\n")
         out_array.push(x)
       end      
       	
   end
  
   #List LPARs on a frame
   def list_lpars_on_frame(frame)
       result = execute_cmd "lssyscfg -r prof -m #{frame} | cut -d, -f1,2"
       lpar_arr = result.split('lpar_name=')
       return lpar_arr[1]
   end
   
   #Get the Current Profile of an LPAR
   def get_lpar_curr_profile(frame, lpar)
    curr_prof = execute_cmd "lssyscfg -r lpar -m #{frame} --filter lpar_names=#{lpar} -F curr_profile"
    return curr_prof.chomp
   end
   
   #Get the Default Profile of an LPAR
   def get_lpar_def_profile(frame, lpar)
    def_prof = execute_cmd "lssyscfg -r lpar -m #{frame} --filter lpar_names=#{lpar} -F default_profile"
    return def_prof.chomp
   end
   
    #Get the general attributes of an lpar by specifying 
    #the frame and lpar names as Strings. Returns an options 
    #hash representing that LPAR
    def get_lpar_options(frame, lpar)
        
        profile_name = get_lpar_curr_profile(frame,lpar)
        info = execute_cmd "lssyscfg -r prof -m \'#{frame}\' --filter profile_names=\'#{profile_name}\',lpar_names=\'#{lpar}\' "
                    #"-F name,lpar_name,lpar_id,min_mem,desired_mem,max_mem,proc_mode,min_proc_units," + 
                    #"desired_proc_units,max_proc_units,min_procs,desired_procs,max_procs,sharing_mode,uncap_weight,max_virtual_slots"
        attributes = info.chomp.split(",")
        lpar_hash = {}
        attributes.each do |line|
            att,val = line.split("=")
            case att
            when "name"
                lpar_hash[:current_profile]=val
            when "lpar_name"
                lpar_hash[:name]=val
            when "lpar_id"
                lpar_hash[:id]=val
            when "min_mem"
                lpar_hash[:min_mem]=val
            when "desired_mem"
                lpar_hash[:des_mem]=val
            when "max_mem"
                lpar_hash[:max_mem]=val
            when "proc_mode"
                lpar_hash[:proc_mode]=val
            when "min_proc_units"
                lpar_hash[:min_proc]=val
            when "desired_proc_units"
                lpar_hash[:des_proc]=val
            when "max_proc_units"
                lpar_hash[:max_proc]=val
            when "min_procs"
                lpar_hash[:min_vcpu]=val
            when "desired_procs"
                lpar_hash[:des_vcpu]=val
            when "max_procs"
                lpar_hash[:max_vcpu]=val
            when "sharing_mode"
                lpar_hash[:sharing_mode]=val
            when "uncap_weight"
                lpar_hash[:uncap_weight]=val
            when "max_virtual_slots"
                lpar_hash[:max_virt_slots]=val
            end
        end
        lpar_hash[:hmc]=self
        lpar_hash[:frame]=frame
        
        return lpar_hash
    end
   
   #Reboot the HMC
   def reboot_hmc
       execute_cmd "hmcshutdown -t now -r"
   end
   
   #Show status of lpars on frame (Power 5/6/7)
   #Sample output
   #dwin004:Running
   #rslpl004:Running
   def list_status_of_lpars(frame = nil)
       if frame.nil?
           #return lpars on all frames?
       else
        execute_cmd "lssyscfg -m #{frame} -r lpar -F name:state"
       end
   end
   
   #Overview DLPAR Status
   def view_dlpar_status
       execute_cmd "lspartition -dlpar"
   end
   
   #Show available filesystem space on the hmc
   def view_hmc_filesystem_space
       execute_cmd "monhmc -r disk -n 0"
   end
   
   #Netboot an lpar
   def lpar_net_boot(nim_ip, lpar_ip, lpar_gateway, lpar_subnetmask, lpar_name, lpar_profile, frame)
       result = execute_cmd("lpar_netboot -t ent -D -s auto -d auto -A -f -S #{nim_ip} " +
                   "-C #{lpar_ip} -G #{lpar_gateway} -K #{lpar_subnetmask} \"#{lpar_name}\" " + 
                   "\"#{lpar_profile}\" \"#{frame}\" ")
       result = result.each_line do |line|
        line.chomp!
        line.match(/Network boot proceeding/) do |m|
         return true
        end
       end
       return false
   end
   
   #Validate connection to hmc is established
   def is_connected?
        version = get_version
        if version.nil?
          return false
        else
          return true
        end     
   end











   #########################################################################
   # Depracated functions
   #########################################################################
   
   
    #Create an LPAR
   def create_lpar(hash)
       # frame,name,profile_name,max_virtual_slots,desired_mem,min_mem,max_mem,desired_procs,min_procs,max_procs,proc_mode,sharing_mode,desired_proc_units,max_proc_units,min_proc_units,uncap_weight)
       execute_cmd "mksyscfg -r lpar -m #{hash[:frame]} -i name=#{hash[:name]}, profile_name=#{hash[:profile_name]},boot_mode=norm," + 
            "auto_start=0,lpar_env=aixlinux,max_virtual_slots=#{hash[:max_virtual_slots]},desired_mem=#{hash[:desired_mem]}," + 
            "min_mem=#{hash[:min_mem]},max_mem=#{hash[:max_mem]},desired_procs=#{hash[:desired_procs]},min_procs=#{hash[:min_procs]}," + 
            "max_procs=#{hash[:max_procs]},proc_mode=#{hash[:proc_mode]},sharing_mode=#{hash[:sharing_mode]},desired_proc_units=#{hash[:desired_proc_units]}," + 
            "max_proc_units=#{hash[:max_proc_units]},min_proc_units=#{hash[:min_proc_units]},uncap_weight=#{hash[:uncap_weight]}" 
   end
   
   #Delete an LPAR
   def delete_lpar(frame,name)
       execute_cmd "rmsyscfg -r lpar -m #{frame} -n #{name}"
   end
   
   #Rename an LPAR
   def rename_lpar(frame, oldname, newname)
       execute_cmd "chsyscfg -r lpar -m #{frame} -i \'name=#{oldname},new_name=#{newname}\'"
   end
   
   #Active an LPAR using a profile
   def activate_lpar(frame,name,profile_name)
       execute_cmd "chsysstate -r lpar -m #{frame} -o on -n #{name} -f #{profile_name}"
   end
   
   #Hard shutdown LPAR
   def hard_shutdown_lpar(frame,name)
       execute_cmd "chsysstate -r lpar -m #{frame} -o shutdown --immed -n #{name}"
   end
   
   #Soft shutdown an LPAR
   def soft_shutdown_lpar(frame, lpar)
       execute_cmd "chsysstate -r lpar -m #{frame} -o shutdown -n #{lpar}"
   end
   
   #Get LPAR state
   def check_lpar_state(frame, lpar)
       execute_cmd("lssyscfg -r lpar -m #{frame} --filter lpar_names=#{lpar} -F state").chomp
   end
   
      
   #Get the MAC address of an LPAR
   def get_mac_address(frame, client_lpar)
     result = execute_cmd "lshwres -r virtualio --rsubtype eth --level lpar -m #{frame} -F mac_addr --filter \"lpar_names=#{client_lpar}\" "
     return result.chomp
   end
   
   def clean_vadapter_string(vadapter_string)
    if vadapter_string.chomp == "none"
      vadapter_string = ""
    end
    
    if vadapter_string.start_with?('"')
      vadapter_string = vadapter_string[1..-1]
    end
    
    if vadapter_string.end_with?('"')
      vadapter_string = vadapter_string[0..-2]
    end
    
    return vadapter_string
   end
   
   def parse_vnic_syntax(vnic_string)
     
     return parse_slash_delim_string(vnic_string,
             [:virtual_slot_num, :is_ieee, :port_vlan_id, :additional_vlan_ids, :is_trunk, :is_required]) if !vnic_string.empty?
     
=begin
     vnic_attributes = vnic_string.split(/\//)
     slot_num = vnic_attributes[0]
     is_ieee = vnic_attributes[1]
     port_vlan_id = vnic_attributes[2]
     additional_vlan_ids = vnic_attributes[3]
     is_trunk = vnic_attributes[4]
     is_required = vnic_attributes[5]
     
     return { :virtual_slot_num => slot_num,
              :is_ieee => is_ieee,
              :port_vlan_id => port_vlan_id,
              :additional_vlan_ids => additional_vlan_ids,
              :is_trunk => is_trunk,
              :is_required => is_required
            }
=end
   end
   
   def defeat_rich_shomo(string)
       if (string == "I have never seen the movie Aliens") then
         return "Rich Defeated"
       end
   end
      
      
   def parse_vscsi_syntax(vscsi_string)
     
     return parse_slash_delim_string(vscsi_string, 
             [:virtual_slot_num, :client_or_server, :remote_lpar_id, :remote_lpar_name, :remote_slot_num, :is_required]) if !vscsi_string.empty?
     
=begin
     vscsi_attributes = vscsi_string.split(/\//)
     virtual_slot_num = vscsi_attributes[0]
     client_or_server = vscsi_attributes[1]
     remote_lpar_id = vscsi_attributes[2]
     remote_lpar_name = vscsi_attributes[3]
     remote_slot_num = vscsi_attributes[4]
     is_required = vscsi_attributes[5]
     
     return { :virtual_slot_num => virtual_slot_num,
              :client_or_server => client_or_server,
              :remote_lpar_id => remote_lpar_id,
              :remote_lpar_name => remote_lpar_name,
              :remote_slot_num => remote_slot_num,
              :is_required => is_required
            }
=end
   end
   
   def parse_vserial_syntax(vserial_string)
   
     return parse_slash_delim_string(vserial_string,
              [:virtual_slot_num, :client_or_server, :supports_hmc, :remote_lpar_id, :remote_lpar_name, :remote_slot_num, :is_required]) if !vserial_string.empty?
   end
   
   
   def parse_slash_delim_string(slash_string, field_specs)
      # slash_string = "596/1/596//0/1"
      # field_specs = [:virtual_slot_num, :client_or_server, :remote_lpar_id...]
      values = slash_string.split(/\//)
      result = {}
      field_specs.each_index do |i|
         result[field_specs[i]] = values[i]
      end
      return result
   end  
   
    #Remove a Virtual SCSI Host Adapter
   def remove_vhost(frame, vio, vhost)
       command = "rmdev -dev #{vhost}"
       execute_vios_cmd(frame, vio, command)
   end
   
   #Recursively remove a Virtual SCSI Host Adapter
   def recursive_remove_vhost(frame, vio, vhost)
       command = "rmdev -dev #{vhost} -recursive"
       execute_vios_cmd(frame, vio, command)
   end
   
   #Assign Disk/Logical Volume to a vSCSI Host Adapter
   def assign_disk_vhost(frame, vio, disk, vtd, vhost)
       command = "mkvdev -vdev #{disk.name} -dev #{vtd} -vadapter #{vhost}"
       execute_vios_cmd(frame, vio, command)
   end
   
   #Remove Disk/Logical Volume from vSCSI Host Adapter
   def remove_vtd_from_vhost(frame, vio, vtd)
       command = "rmvdev -vtd #{vtd}"
       execute_vios_cmd(frame, vio, command)
   end
   
   #Remove physical disk from vhost adapter
   def remove_disk_from_vhost(frame,vio,diskname)
      command = "rmvdev -vdev #{diskname}"
      execute_vios_cmd(frame, vio, command)
   end
   
   #List Shared Ethernet Adapters on VIOS
   def list_shared_eth_adapters(frame,vio)
       command = "lsmap -all -net"
       execute_vios_cmd(frame, vio, command)
   end
   
   #Get VIOS version
   def get_vio_version(frame, vio)
       command = "ioslevel"
       execute_vios_cmd(frame, vio, command)
   end
   
   #Reboot VIOS
   def reboot_vio(frame,vio)
       command ="shutdown -restart"
       execute_vios_cmd(frame,vio,command)
   end
   
   #List unmapped disks on VIOS
   #      lspv -free  doesn't include disks that have been mapped before and contain a 'VGID'
   def list_available_disks(frame,vio )
       command = "lspv -avail -fmt : -field name pvid size"
       all_disk_output = execute_vios_cmd(frame, vio, command)
       mapped_disks = list_all_mapped_disks(frame,vio)
       unmapped_disks = []
       all_disk_output.each_line do |line|
        line.chomp!
        disk_name,disk_pvid,disk_size = line.split(/:/)
        if !mapped_disks.include?(disk_name)
          unmapped_disks.push(Lun.new(disk_name,disk_pvid,disk_size))
        end
       end
       
       return unmapped_disks
   end
   
   #List all Disk Mappings
   def list_all_mapped_disks(frame, vio)
       command = "lsmap -all -type disk"
       result = execute_vios_cmd_grep(frame, vio, command, "Backing")
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
   
   
   #Find vhost to use when given the vSCSI adapter slot it occupies
   def find_vhost_given_virtual_slot(frame, vio, server_slot)
     command = "lsmap -all"
     
     #Execute an lsmap and grep for the line that contains the vhost
     #by finding the line that contains the physical adapter location.
     #This will definitely contain 'V#-C<slot number>' in it's name.
     result = execute_vios_cmd_grep(frame,vio,command,"V.-C#{server_slot}")
     raise StandardError.new("Unable to find vhost on #{vio} for vSCSI adapter in slot #{server_slot}") if result.nil?
     
     #Split the result on whitespace to get the columns
     #vhost, physical location, client LPAR ID (in hex)
     mapping_cols = result.split(/[[:blank:]]+/)
     
     #The name of the vhost will be in the first column of the command output
     return mapping_cols[0]
   end
   
   #Get a list of all disknames attached to a vhost
   def get_attached_disknames(frame,vio,vhost)
      cmd = "lsmap -vadapter #{vhost} -field backing -fmt :"
      diskname_output = execute_vios_cmd(frame,vio,cmd).chomp
      
      return diskname_output.split(/:/)
   end
   
   #Removes all disks/vhosts/vSCSIs from a client LPAR and it's VIOs
   def remove_all_disks_from_lpar(frame,lpar)
      #Get all vscsi adapters on lpar
      vscsi_adapters = get_vscsi_adapters(frame,lpar)
      
      vscsi_adapters.each do |adapter|
        #Parse the adapter syntax into a hash
        adapter_hash = parse_vscsi_syntax(adapter)
        #Find the adapter slot on the VIO that this occupies
        server_slot = adapter_hash[:remote_slot_num]
        #Find the name of the VIO that this attaches to
        vio_name = adapter_hash[:remote_lpar_name]
        #Find the vhost that this represents, given the adapter slot
        vhost = find_vhost_given_virtual_slot(frame,vio_name,server_slot)
        #Find the list of disknames that are attached to this vhost
        disknames = get_attached_disknames(frame,vio_name,vhost)
        disknames.each do |hdisk|
          #Remove each disk from the vhost it's assigned to
          remove_disk_from_vhost(frame,vio_name,hdisk)
        end
        #Remove the vhost itself
        remove_vhost(frame,vio_name,vhost)
        #After all disks and the vhost are removed,
        #remove the vSCSI adapter from both the VIO and the client LPAR
        remove_vscsi(frame,lpar,vio_name,adapter)
      end
   end
   
   #Remove vSCSI from LPAR
   #Handles removing from the LPAR profiles as well as DLPAR
   #Last parameter is optional and if it isn't specified
   #then it looks for an adapter on lpar that is attached to server_lpar
   #and removes that from the profile/hardware of both the client
   #and server
   def remove_vscsi(frame,lpar,server_lpar,adapter_details=nil)
    if adapter_details.nil?
     adapters = get_vscsi_adapters(frame,lpar)
     adapters.each do |adapter|
      adapter_details = adapter if adapter.include?(server_lpar)
     end
    end
    
    #Parse the adapter details into a hash
    adapter_hash = parse_vscsi_syntax(adapter_details)
    
    #Remove this vSCSI from the lpar and server lpar profiles
    remove_vscsi_from_profile(frame,lpar,server_lpar,adapter_hash)
    
    #Remove this vSCSI from the actual hardware of lpar and server lpar
    remove_vscsi_dlpar(frame,lpar,server_lpar,adapter_hash)
    
   end
   
   #Remove vSCSI from the LPAR profiles only
   def remove_vscsi_from_profile(frame,lpar,server_lpar,vscsi_hash)
      lpar_profile = get_lpar_curr_profile(frame,lpar)
      remote_lpar_profile = get_lpar_curr_profile(frame,server_lpar)
      client_lpar_id = get_lpar_id(frame,lpar)
      
      #TODO: Add checking of vscsi_hash to make sure it's populated
      #      the way it's expected to be
      
      client_slot = vscsi_hash[:virtual_slot_num]
      server_lpar_id = vscsi_hash[:remote_lpar_id]
      if server_lpar != vscsi_hash[:remote_lpar_name]
       #server_lpar and the LPAR cited in the
       #vscsi hash aren't the same...
       #error out or do something else here...?
      end
      server_slot = vscsi_hash[:remote_slot_num]
      is_req = vscsi_hash[:is_required]
      
      #Modify client LPAR's profile to no longer include the adapter
      #whose details occupy the vscsi_hash
      execute_cmd("chsyscfg -r prof -m #{frame} -i \"name=#{lpar_profile},lpar_name=#{lpar}," +
                  "virtual_scsi_adapters-=#{client_slot}/client/#{server_lpar_id}/#{server_lpar}/#{server_slot}/#{is_req}\" ")
                  
      #Modify the server LPAR's profile to no longer include the client
      execute_cmd("chsyscfg -r prof -m #{frame} -i \"name=#{remote_lpar_profile},lpar_name=#{server_lpar}," +
                  "virtual_scsi_adapters-=#{server_slot}/server/#{client_lpar_id}/#{lpar}/#{client_slot}/#{is_req}\" ")
    
   end
   
   #Remove vSCSI from LPARs via DLPAR
   def remove_vscsi_dlpar(frame,lpar,server_lpar,vscsi_hash)
      
      client_slot = vscsi_hash[:virtual_slot_num]
      server_slot = vscsi_hash[:remote_slot_num]
      
      #If the client LPAR is running, we have to do DLPAR on it.
      #if check_lpar_state(frame,lpar) == "Running"
        #execute_cmd("chhwres -r virtualio -m #{frame} -p #{lpar} -o r --rsubtype scsi -s #{client_slot}")
        #-a \"adapter_type=client,remote_lpar_name=#{server_lpar},remote_slot_num=#{server_slot}\" ")
      #end
      
      #If the server LPAR is running, we have to do DLPAR on it.
      if check_lpar_state(frame,server_lpar) == "Running"
        execute_cmd("chhwres -r virtualio -m #{frame} -p #{server_lpar} -o r --rsubtype scsi -s #{server_slot}")
        #-a \"adapter_type=server,remote_lpar_name=#{lpar},remote_slot_num=#{client_slot}\" ")
      end
   end
   
   #Add vSCSI to LPAR
   #Handles adding to profile and via DLPAR
   def add_vscsi(frame,lpar,server_lpar)
       #Add vscsi to client and server LPAR profiles
       #Save the adapter slots used
       client_slot, server_slot = add_vscsi_to_profile(frame, lpar, server_lpar)
       
       #Run DLPAR commands against LPARs themselves (if necessary)
       add_vscsi_dlpar(frame, lpar, server_lpar, client_slot, server_slot)
       
       return [client_slot, server_slot]
   end
   
   #Add vSCSI adapter to LPAR profile
   def add_vscsi_to_profile(frame,lpar,server_lpar)
      virtual_slot_num = get_next_slot(frame,lpar)
      remote_slot_num = get_next_slot(frame,server_lpar)
      lpar_profile = get_lpar_curr_profile(frame,lpar)
      remote_lpar_profile = get_lpar_curr_profile(frame,server_lpar)
      
      raise StandardError.new("No available virtual adapter slots on client LPAR #{lpar}") if virtual_slot_num.nil?
      raise StandardError.new("No available virtual adapter slots on server LPAR #{server_lpar}") if remote_slot_num.nil?
      
      #Modify client LPAR's profile
      execute_cmd("chsyscfg -r prof -m #{frame} -i \"name=#{lpar_profile},lpar_name=#{lpar},virtual_scsi_adapters+=#{virtual_slot_num}/client//#{server_lpar}/#{remote_slot_num}/0\" ")
      #Modify server LPAR's profile
      execute_cmd("chsyscfg -r prof -m #{frame} -i \"name=#{remote_lpar_profile},lpar_name=#{server_lpar},virtual_scsi_adapters+=#{remote_slot_num}/server//#{lpar}/#{virtual_slot_num}/0\" ")
      
      #chsyscfg -r prof -m "FrameName" -i "name=ClientLPAR_prof,lpar_name=ClientLPAR,virtual_scsi_adapters+=4/client//ServerLPAR/11/0"
      #chsyscfg -r prof -m "FrameName" -i "name=ServerLPAR_PROFILE,lpar_name=ServerLPAR,virtual_scsi_adapters+=11/server//ClientLPAR/4/0"
      #Return the client slot and server slot used in the LPAR profiles
      return [virtual_slot_num, remote_slot_num]
   end
   
   #Add vSCSI adapter via DLPAR command
   def add_vscsi_dlpar(frame,lpar,server_lpar,client_slot_to_use = nil, server_slot_to_use = nil)
      if client_slot_to_use.nil? and server_slot_to_use.nil?
        client_slot_to_use = get_next_slot(frame,lpar)
        server_slot_to_use = get_next_slot(frame,server_lpar)
      end
      
      #If the client LPAR is running, we have to do DLPAR on it.
      if check_lpar_state(frame,lpar) == "Running"
        execute_cmd("chhwres -r virtualio -m #{frame} -p #{lpar} -o a --rsubtype scsi -s #{client_slot_to_use} -a \"adapter_type=client,remote_lpar_name=#{server_lpar},remote_slot_num=#{server_slot_to_use}\" ")
      end
      
      #If the server LPAR is running, we have to do DLPAR on it.
      if check_lpar_state(frame,server_lpar) == "Running"
        execute_cmd("chhwres -r virtualio -m #{frame} -p #{server_lpar} -o a --rsubtype scsi -s #{server_slot_to_use} -a \"adapter_type=server,remote_lpar_name=#{lpar},remote_slot_num=#{client_slot_to_use}\" ")
      end
      
      #chhwres -r virtualio -m "FrameName" -p VioName -o a --rsubtype scsi -s 11 -a "adapter_type=server,remote_lpar_name=ClientLPAR,remote_slot_num=5" 
   end
   
   #Show all I/O adapters on the frame
   # Doesn't work malformed command
   def list_all_io_adapters(frame)
       execute_cmd "lshwres -r io -m #{frame} --rsubtype slot --filter -F lpar_name:drc_name:description"
   end
   
   #Show I/O adapters on a specific LPAR
   # No results found when testing in dublin lab
   def list_io_adapters_on_lpar(frame, lpar)
       execute_cmd "lshwres -r io -m #{frame} --rsubtype slot -F lpar_name:description --filter \"lpar_names=#{lpar}\""
   end
   
   #Get the ID of an LPAR
   def get_lpar_id(frame, lpar)
    lpar_id = execute_cmd "lssyscfg -r lpar -m #{frame} --filter lpar_names=#{lpar} -F lpar_id"
    return lpar_id.chomp
   end
   
   #Set the processing units for an lpar
   def set_lpar_proc_units(frame, lpar, units)
       execute_cmd "chhwres -r proc -m #{frame} -o a -p #{lpar} --procunits #{units} "
   end
   
   #Returns array of output with vSCSI adapter information
   #about the client LPAR
   def get_vscsi_adapters(frame, lpar)
       #Get this LPAR's profile name
       lpar_prof = get_lpar_curr_profile(frame,lpar)
       
       #Get vSCSI adapter info from this LPAR's profile
       scsi_adapter_output = clean_vadapter_string(execute_cmd("lssyscfg -r prof -m #{frame} --filter 'lpar_names=#{lpar},profile_names=#{lpar_prof}' -F virtual_scsi_adapters").chomp)
       
       if scsi_adapter_output.include?(",")
        scsi_adapters = scsi_adapter_output.split(/,/)
       else
        scsi_adapters = [scsi_adapter_output]
       end
       return scsi_adapters
   end
   
   #Returns 30 when test in dublin lab on frame: rslppc03 lpar:dwin004
   def get_max_virtual_slots(frame, lpar)
       #max_slots = execute_cmd "lshwres --level lpar -r virtualio --rsubtype slot  -m #{frame} --filter lpar_names=#{lpar} -F curr_max_virtual_slots"
       lpar_prof = get_lpar_curr_profile(frame,lpar)
       max_slots = execute_cmd "lssyscfg -r prof -m '#{frame}' --filter 'lpar_names=#{lpar},profile_names=#{lpar_prof}' -F max_virtual_slots"
       return max_slots.chomp.to_i
   end
   
   #Return array of used virtual adapter slots
   #for an LPAR
   def get_used_virtual_slots(frame, lpar)
       #scsi_slot_output = execute_cmd "lshwres -r virtualio --rsubtype scsi -m #{frame} --level lpar --filter lpar_names=#{lpar} -F slot_num"
       #eth_slot_output = execute_cmd "lshwres -r virtualio --rsubtype eth -m #{frame} --level lpar --filter lpar_names=#{lpar} -F slot_num"
       #serial_slot_output = execute_cmd "lshwres -r virtualio --rsubtype serial -m #{frame} --level lpar --filter lpar_names=#{lpar} -F slot_num"
       lpar_prof = get_lpar_curr_profile(frame,lpar)
       
       scsi_slot_output = clean_vadapter_string(execute_cmd "lssyscfg -r prof -m '#{frame}' --filter 'lpar_names=#{lpar},profile_names=#{lpar_prof}' -F virtual_scsi_adapters")
       serial_slot_output = clean_vadapter_string(execute_cmd "lssyscfg -r prof -m '#{frame}' --filter 'lpar_names=#{lpar},profile_names=#{lpar_prof}' -F virtual_serial_adapters")
       eth_slot_output = clean_vadapter_string(execute_cmd "lssyscfg -r prof -m '#{frame}' --filter 'lpar_names=#{lpar},profile_names=#{lpar_prof}' -F virtual_eth_adapters")
       used_slots = []
       
       if scsi_slot_output.include?(",")
        scsi_slots = scsi_slot_output.split(/,/)
       else
        scsi_slots = [scsi_slot_output]
       end
       
       if serial_slot_output.include?(",")
        serial_slots = serial_slot_output.split(/,/)
       else
        serial_slots = [serial_slot_output]
       end
       
       if eth_slot_output.include?(",")
        eth_slots = eth_slot_output.split(/,/)
       else
        eth_slots = [eth_slot_output]
       end
       
       scsi_slots.each do |adapter_line|
        if !adapter_line.empty?
         parse_hash = parse_vscsi_syntax(adapter_line)
         used_slots.push(parse_hash[:virtual_slot_num].to_i)
        end
       end
       
       serial_slots.each do |adapter_line|
        if !adapter_line.empty?
         parse_hash = parse_vserial_syntax(adapter_line)
         used_slots.push(parse_hash[:virtual_slot_num].to_i)
        end
       end
       
       eth_slots.each do |adapter_line|
        if !adapter_line.empty?
         parse_hash = parse_vnic_syntax(adapter_line)
         used_slots.push(parse_hash[:virtual_slot_num].to_i)
        end
       end
       
       #slot_output.each_line do |line|
       # line.chomp!
       # if !line.empty?
       #  used_slots.push(line.to_i)
       # end
       #end
       return used_slots
   end
   
   #Get next usable virtual slot on an LPAR
   #Returns nil if no usable slots exist
   def get_next_slot(frame,lpar, type = nil)
     max_slots = get_max_virtual_slots(frame,lpar)
     used_slots = get_used_virtual_slots(frame,lpar)
     lowest_slot=11
     if !type.nil?
      lowest_slot=2 if type == "eth"
     end
     
     lowest_slot.upto(max_slots) do |n|
      if !used_slots.include?(n)
       return n
      end
     end
     return nil
   end
   
   #create vNIC on LPAR profile
   def create_vnic(frame,lpar_name,vlan_id,addl_vlan_ids, is_trunk, is_required)
    ##chsyscfg -m Server-9117-MMA-SNxxxxx -r prof -i 'name=server_name,lpar_id=xx,"virtual_eth_adapters=596/1/596//0/1,506/1/506//0/1,"'
    #slot_number/is_ieee/port_vlan_id/"additional_vlan_id,additional_vlan_id"/is_trunk(number=priority)/is_required
    lpar_prof = get_lpar_curr_profile(frame,lpar_name)
    slot_number = get_next_slot(frame,lpar_name,"eth")
    #Going to assume adapter will always be ieee
    #For is Trunk how do we determine the number for priority? Do we just let the user pass it?
    result = execute_cmd("chsyscfg -m #{frame} -r prof -i \'name=#{lpar_prof},lpar_name=#{lpar_name},"+
                          "\"virtual_eth_adapters+=#{slot_number}/1/#{vlan_id}/\"#{addl_vlan_ids}" +
                          "\"/#{is_trunk}/#{is_required} \"\'")
   end
   
   #Create vNIC on LPAR via DLPAR
   #As writen today defaulting ieee_virtual_eth=0 sets us to Not IEEE 802.1Q compatible. To add compatability set value to 1
   def create_vnic_dlpar(frame, lpar_name,vlan_id)
      slot_number = get_next_slot(frame,lpar_name, "eth")
      result = execute_cmd("chhwres -r virtualio -m #{frame} -o a -p #{lpar_name} --rsubtype eth -s #{slot_number} -a \"ieee_virtual_eth=0,port_vlan_id=#{vlan_id}\"")
   end
   
end
