=begin
    Assumptions:
    -operations on LPARs will be done simultaneously to both their current profile and
     the LPAR's hardware itself, removing the need to abstract data into both LPAR attributes
     and attributes of that LPAR's profile.
    Future features:
    -May split lpar_profile into a subclass of LPAR in the future, to allow greater levels of 
    customization.
=end
require_relative 'hmc'
require_relative 'vscsi'
require_relative 'network'

class Lpar 
    
    attr_accessor   :min_proc_units, :max_proc_units, :desired_proc_units,
                    :min_memory, :max_memory, :desired_memory,
                    :min_vcpu, :max_vcpu, :desired_vcpu,
                    :id, :current_profile, :default_profile, :name,
                    :hostname, :proc_mode, :sharing_mode, :uncap_weight,
                    :frame, :max_virtual_slots

    attr_reader		:hmc
                
    def initialize(options_hash)
        
        #Test for the explicitly required parameters
        raise StandardError.new("An Lpar cannot be defined without a managing HMC") if options_hash[:hmc].nil? or !options_hash[:hmc].respond_to?(:execute_cmd)
        raise StandardError.new("An Lpar cannot be defined without a name") if options_hash[:name].nil?
        raise StandardError.new("An Lpar cannot be defined without specifying the frame it resides/will reside on") if options_hash[:frame].nil?
        raise StandardError.new("An Lpar cannot be defined without specifying it's desired processing units") if options_hash[:des_proc].nil?
        raise StandardError.new("An Lpar cannot be defined without specifying it's desired virtual CPUs") if options_hash[:des_vcpu].nil?
        raise StandardError.new("An Lpar cannot be defined without specifying it's desired memory") if options_hash[:des_mem].nil?
        
        #TODO: We should not really be storing the hostname (or vlan_id, or management_ip) as an attribute of LPAR, much less any network configuration stuff...
        #Maybe we should consider a NetworkSettings class that is just an attribute of LPAR, which we leverage to find any network info we need here...?
        raise StandardError.new("An Lpar cannot be defined without specifying it's FQDN") if options_hash[:hostname].nil? && options_hash[:name].nil?
        
        #Parameters that are explicitly required to make an LPAR object
        @hmc				= options_hash[:hmc]
        @desired_proc_units = options_hash[:des_proc].to_f
        @desired_memory     = options_hash[:des_mem].to_i
        @desired_vcpu       = options_hash[:des_vcpu].to_i
        @frame				= options_hash[:frame]
        @name               = options_hash[:name]
        
        #Parameters that can be defaulted if they are not provided
        !options_hash[:hostname].nil? ? @hostname = options_hash[:hostname] : @hostname = @name
        !options_hash[:min_proc].nil? ? @min_proc_units = options_hash[:min_proc].to_f : @min_proc_units = @desired_proc_units
        !options_hash[:max_proc].nil? ? @max_proc_units = options_hash[:max_proc].to_f : @max_proc_units = @desired_proc_units
        !options_hash[:max_mem].nil? ? @max_memory = options_hash[:max_mem].to_i : @max_memory = @desired_memory
        !options_hash[:min_mem].nil? ? @min_memory = options_hash[:min_mem].to_i : @min_memory = @desired_memory
        !options_hash[:max_vcpu].nil? ? @max_vcpu = options_hash[:max_vcpu].to_i : @max_vcpu = @desired_vcpu
        !options_hash[:min_vcpu].nil? ? @min_vcpu = options_hash[:min_vcpu].to_i : @min_vcpu = @desired_vcpu
        !options_hash[:max_virt_slots].nil? ? @max_virtual_slots = options_hash[:max_virt_slots].to_i : @max_virtual_slots = 30
        !options_hash[:current_profile].nil? ? @current_profile = options_hash[:current_profile] : @current_profile = @name + "_profile"
        !options_hash[:default_profile].nil? ? @default_profile	= options_hash[:default_profile] : @default_profile = @current_profile
        !options_hash[:sharing_mode].nil? ? @sharing_mode = options_hash[:sharing_mode] : @sharing_mode = "cap"
        @sharing_mode == "uncap" ? @uncap_weight = options_hash[:uncap_weight].to_i : @uncap_weight = nil
        !options_hash[:proc_mode].nil? ? @proc_mode = options_hash[:proc_mode] : @proc_mode = "shared"
        
        #Parameters that hold no value unless the LPAR already exists
        #or create() is called
        !options_hash[:id].nil? ? @id = options_hash[:id] : @id = nil
        
        #TODO: Implement the VIO pair as attributes of the LPAR???
    end
    
    #Create an LPAR
    def create
        
        #TODO: Stop function from proceeding if LPAR with this name already exists on the frame
        command = "mksyscfg -r lpar -m #{@frame} -i name=#{@name}, profile_name=#{@current_profile},boot_mode=norm," + 
            "auto_start=0,lpar_env=aixlinux,max_virtual_slots=#{@max_virtual_slots},desired_mem=#{@desired_memory}," + 
            "min_mem=#{@min_memory},max_mem=#{@max_memory},desired_procs=#{@desired_vcpu},min_procs=#{@min_vcpu}," + 
            "max_procs=#{@max_vcpu},proc_mode=#{@proc_mode},sharing_mode=#{@sharing_mode},desired_proc_units=#{@desired_proc_units}," + 
            "max_proc_units=#{@max_proc_units},min_proc_units=#{@min_proc_units}"
        command += ",uncap_weight=#{@uncap_weight}" if !@uncap_weight.nil?
        
        hmc.execute_cmd(command)
    end
    
    #Delete an LPAR
    def delete
        #TO-DO: Check that the LPAR with this name exists on the frame before trying to shutdown and delete it
        #TO-DO: Remove all of the LPAR's disks/vSCSIs before deleting
        #Do a hard shutdown and then remove the LPAR definition
        hard_shutdown
        hmc.execute_cmd "rmsyscfg -r lpar -m #{frame} -n #{name}"
    end
    
    #Rename an LPAR
    def rename(newname)
        hmc.execute_cmd "chsyscfg -r lpar -m #{frame} -i \'name=#{name},new_name=#{newname}\'"
        @name = newname
    end
    
    #Active an LPAR using a profile
    def activate(profile_name = @current_profile)
        hmc.execute_cmd "chsysstate -r lpar -m #{frame} -o on -n #{name} -f #{profile_name}"
        @current_profile = profile_name if @current_profile != profile_name
    end
    
    #Hard shutdown LPAR
    def hard_shutdown
        hmc.execute_cmd "chsysstate -r lpar -m #{frame} -o shutdown --immed -n #{name}"
    end
    
    #Soft shutdown an LPAR
    def soft_shutdown
        hmc.execute_cmd "chsysstate -r lpar -m #{frame} -o shutdown -n #{name}"
    end
    
    #Get LPAR state
    def check_state
        hmc.execute_cmd("lssyscfg -r lpar -m #{frame} --filter lpar_names=#{name} -F state").chomp
    end
    
    #Returns true/false value depending on if the LPAR is running or not
    #Since an LPAR can have states such as "Not Activated", "Open Firmware", "Shutting Down",
    #this function only helps for when we are explicitly looking for an LPAR to be either "Running" or not.
    def is_running?
        #TODO: should this return true if "Open Firmware" is the status as well..? No, it shouldn't
        return check_state == "Running"	
    end

    #Similar to is_running? - only returns true if the LPAR's state is "Not Activated".
    #Any other state is percieved as false
    def not_activated?
        return check_state == "Not Activated"
    end
    
    def get_info
        info = hmc.execute_cmd "lssyscfg -r lpar -m \'#{frame}\' --filter lpar_names=\'#{lpar}\'"
        return info.chomp
    end
    
    #Get the ID of an LPAR
    def id
        if @id.nil?
            #Use an HMC command to pull the LPAR's ID if this is the first time that
            #the LPAR's ID is being accessed
            @id = hmc.execute_cmd("lssyscfg -r lpar -m #{frame} --filter lpar_names=#{name} -F lpar_id").chomp
        end
        return @id
    end
    
    #Get the Current Profile of an LPAR
    def current_profile
        if @current_profile.nil?
            @current_profile = hmc.execute_cmd("lssyscfg -r lpar -m #{frame} --filter lpar_names=#{name} -F curr_profile").chomp
        end
        return @current_profile
    end
    
    #Get the Default Profile of an LPAR
    def default_profile
        if @default_profile.nil?
            @default_profile = hmc.execute_cmd("lssyscfg -r lpar -m #{frame} --filter lpar_names=#{name} -F default_profile").chomp
        end
        return @default_profile
    end
    
    #Get the MAC address of an LPAR
    def get_mac_address
        result = hmc.execute_cmd("lshwres -r virtualio --rsubtype eth --level lpar -m #{frame} -F mac_addr --filter \"lpar_names=#{name}\" ")
        return result.chomp
    end    
    
    #Set an LPAR profile's attribute, specifying the units to set the attribute to and the HMC label for the attribute
    def set_attr_profile(units,hmc_label)
        cmd = "chsyscfg -m #{frame} -r prof -i \"name=#{current_profile}, lpar_name=#{name}, #{hmc_label}=#{units} \" "
        hmc.execute_cmd(cmd)
    end
    
    #Function to use for all Min/Max attribute changing
    def set_attr_and_reactivate(units,hmc_label)
        #Change the profile attribute
        set_attr_profile(units,hmc_label)
        #Shut down the LPAR
        soft_shutdown
        #Wait until it's state is "Not Activated"
        sleep(10) until not_activated?
        #Reactivate the LPAR so that the attribute changes take effect
        activate
    end

    #####################################
    # Processing Unit functions
    #####################################
        
    #Set the processing units for an LPAR
    def desired_proc_units=(units)
        
        raise StandardError.new("Processing unit value is lower than the Minimum Processing Units specified for this LPAR: #{min_proc_units}") if units < min_proc_units
        raise StandardError.new("Processing unit value is higher than the Maximum Processing Units specified for this LPAR: #{max_proc_units}") if units > max_proc_units
        
        #Validate that this value adheres to the vCPU:Proc_unit ratio of 10:1
        raise StandardError.new("Desired processing unit value must be less than or equal to Desired vCPU value: #{desired_vcpu}") if units > desired_vcpu
        raise StandardError.new("Desired processing unit value must be at least 1/10 the Desired vCPU value: #{desired_vcpu}") if desired_vcpu/units > 10

        #Set processing units on the Profile
        set_attr_profile(units,"desired_proc_units")
        #Set processing units via DLPAR
        set_proc_units_dlpar(units)
        
        #After the Desired Proc units are set on the profile and hardware, set
        #the private attribute
        @desired_proc_units = units
    end
    
    #Set the max processing units for an LPAR
    def max_proc_units=(units)
        raise StandardError.new("Maximum processing unit value is lower than the Desired Processing Units specified for this LPAR") if units < desired_proc_units
        
        #Validate that the value specified does not violate the 10:1 ratio requirement between max vCPU and max proc units.
        raise StandardError.new("Maximum processing unit value must be less than or equal to Maximum vCPU value: #{max_vcpu}") if units > max_vcpu
        raise StandardError.new("Maximum processing unit value must at least be 1/10 the Maximum vCPU value: #{max_vcpu}") if max_vcpu/units > 10
        
        #Set the Max Proc Units on the LPAR profile
        #and reactivate the LPAR
        set_attr_and_reactivate(units,"max_proc_units")
        
        #Set the private member        
        @max_proc_units = units
    end
    
    #Set the min processing units for an LPAR
    def min_proc_units=(units)
        raise StandardError.new("Minimum processing unit value is greater than the Desired Processing Units specified for this LPAR") if units > desired_proc_units
        
        #Validate that this value adheres to the vCPU:Proc_unit ratio of 10:1
        raise StandardError.new("Minimum processing unit value must be less than or equal to Minimum vCPU value: #{min_vcpu}") if units > min_vcpu
        raise StandardError.new("Minimum processing unit value must be at least 1/10 the Minimum vCPU value: #{min_vcpu}") if min_vcpu/units > 10

        #Set the Max Proc Units on the LPAR profile
        #and reactivate the LPAR
        set_attr_and_reactivate(units,"min_proc_units")
        
        #Set the private member
        @min_proc_units = units	
    end
    
    #Set the processing units for an LPAR via DLPAR
    def set_proc_units_dlpar(units)
        #This command adds or removes, doesn't 'set'
        #TODO: add logic to make it behave like a 'set' and not an add/remove
        units > desired_proc_units ? op="a" : op="r"
        difference = (units-desired_proc_units).abs
        if is_running?
            if proc_mode == "shared"
                hmc.execute_cmd("chhwres -r proc -m #{frame} -o #{op} -p #{name} --procunits #{difference} ")
            elsif proc_mode == "dedicated"
                #Apparently if the proccessor sharing mode is 'dedicated',
                #then you need to use the --procs flag when changing processor units
                hmc.execute_cmd("chhwres -r proc -m #{frame} -o #{op} -p #{name} --procs #{difference} ")
            end
        end
    end
    
    #####################################
    # Virtual CPU functions
    #####################################
    
    #Set the virtual CPUs for an LPAR
    def desired_vcpu=(units)
        raise StandardError.new("Virtual CPU value is lower than the Minimum Virtual CPU value specified for this LPAR: #{min_vcpu}") if units < min_vcpu
        raise StandardError.new("Virtual CPU value is higher than the Maximum Virtual CPU value specified for this LPAR: #{max_vcpu}") if units > max_vcpu
        
        #Validate that this value adheres to the vCPU:Proc_unit ratio of 10:1
        raise StandardError.new("Desired vCPU value must be greater than or equal to Desired processing unit value: #{desired_proc_units}") if units < desired_proc_units
        raise StandardError.new("Desired vCPU value must be at most 10 times as large as Desired processing unit value: #{desired_proc_units}") if units/desired_proc_units > 10

        #Set processing units on the Profile
        set_attr_profile(units,"desired_procs")
        #Set processing units via DLPAR
        set_vcpu_dlpar(units)
        
        #After the Desired Proc units are set on the profile and hardware, set
        #the private attribute
        @desired_vcpu = units
    end
    
    #Set the minimum virtual CPUs for an LPAR
    def min_vcpu=(units)
        raise StandardError.new("Minimum vCPU value is higher than the Desired Virtual CPU specified for this LPAR: #{desired_vcpu}") if units > desired_vcpu
        
        #Validate that this value adheres to the vCPU:Proc_unit ratio of 10:1
        raise StandardError.new("Minimum vCPU value must be greater than or equal to Minimum processing unit value: #{min_proc_units}") if units < min_proc_units
        raise StandardError.new("Minimum vCPU value must be at most 10 times as large as Minimum processing unit value: #{min_proc_units}") if units/min_proc_units > 10

        #Set the Min vCPU on the LPAR profile
        #and reactivate the LPAR
        set_attr_and_reactivate(units,"min_procs")
        
        #Set the private member
        @min_vcpu = units
    end

    #Set the maximum virtual CPUs for an LPAR
    def max_vcpu=(units)
        raise StandardError.new("Maximum vCPU value is lower than the Desired Virtual CPU specified for this LPAR: #{desired_vcpu}") if units < desired_vcpu
        
        #Validate that this value adheres to the vCPU:Proc_unit ratio of 10:1
        raise StandardError.new("Maximum vCPU value must be greater than or equal to Maximum processing unit value: #{max_proc_units}") if units < max_proc_units
        raise StandardError.new("Maximum vCPU value must be at most 10 times as large as Maximum processing unit value: #{max_proc_units}") if units/max_proc_units > 10

        #Set the Max vCPU on the LPAR profile
        #and reactivate the LPAR
        set_attr_and_reactivate(units,"max_procs")
        
        #Set the private member
        @max_vcpu = units
    end

    #Set the desired number of virtual CPUs for an LPAR using DLPAR commands
    def set_vcpu_dlpar(units)
        #This command adds or removes, it doesn't 'set'
        units > desired_vcpu ? op="a" : op="r"
        difference = (units-desired_vcpu).abs
        if is_running?
            hmc.execute_cmd("chhwres -r proc -m #{frame} -o #{op} -p #{name} --procs #{difference}")
        end
    end

    ############################################
    # Memory allocation/deallocation functions
    ############################################

    #Set the Memory allocated to an LPAR (in MB)
    def desired_memory=(units)
        
        raise StandardError.new("Memory value is lower than the Minimum Memory specified for this LPAR") if units < min_memory
        raise StandardError.new("Memory value is higher than the Maximum Memory specified for this LPAR") if units > max_memory
        
        #Set the desired memory of the LPAR in the profile
        set_attr_profile(units,"desired_mem")
        
        #Set the desired memory of the LPAR via DLPAR
        set_memory_dlpar(units)
        
        #After it has been set on the profile and the LPAR, set the attribute for the object
        @desired_memory = units
    end

    #Set the minimum virtual CPUs for an LPAR
    def min_memory=(units)
        raise StandardError.new("Minimum Memory value is higher than the Desired Memory specified for this LPAR: #{desired_memory}") if units > desired_memory
        
        #Set the Min Memory on the LPAR profile
        #and reactivate
        set_attr_and_reactivate(units,"min_mem")
        
        #Set private member
        @min_memory = units
    end

    #Set the maximum virtual CPUs for an LPAR
    def max_memory=(units)
        raise StandardError.new("Maximum Memory value is lower than the Desired Memory specified for this LPAR: #{desired_memory}") if units < desired_memory
        
        #Set the Max vCPU on the LPAR profile
        #and reactivate
        set_attr_and_reactivate(units,"max_mem")
        
        #Set private member
        @max_memory = units
    end

    #Set the Memory allocated to an LPAR via DLPAR (in MB)
    def set_memory_dlpar(units)
        
        units > desired_memory ? op="a" : op="r"
        difference = (units-desired_memory).abs
        
        if is_running?
            hmc.execute_cmd("chhwres -r mem -m #{frame} -o #{op} -p #{name} -q #{difference}") 
            # chhwres -r mem -m Managed-System -o a -p Lpar_name -q 1024
        end
    end   
    
    
    
    ####################################
    # vSCSI Adapter functions
    ####################################
    
    #Returns array of output with vSCSI adapter information
    #about the client LPAR
    def get_vscsi_adapters
        
        #Get vSCSI adapter info from this LPAR's profile
        scsi_adapter_output = clean_vadapter_string(hmc.execute_cmd("lssyscfg -r prof -m #{frame} --filter 'lpar_names=#{name},profile_names=#{current_profile}' -F virtual_scsi_adapters").chomp)
        vscsi_adapters  = []
        if scsi_adapter_output.include?(",")
            scsi_adapters = scsi_adapter_output.split(/,/)
            #split on /
            #11/client/1/rslppc09a/17/0,12/client/2/rslppc09b/17/0
            scsi_adapters.each do |scsi_adapter|
              scsi_adapter = scsi_adapter.split("/")
              vscsi = Vscsi.new(scsi_adapter[0],scsi_adapter[1],scsi_adapter[2],scsi_adapter[3],scsi_adapter[4],scsi_adapter[5])
              vscsi_adapters.push(vscsi)
            end
        elsif !scsi_adapter_output.empty?
            scsi_adapter = scsi_adapter_output
            scsi_adapter = scsi_adapter.split("/")
            vscsi = Vscsi.new(scsi_adapter[0],scsi_adapter[1],scsi_adapter[2],scsi_adapter[3],scsi_adapter[4],scsi_adapter[5])
            vscsi_adapters.push(vscsi)
        end
        return vscsi_adapters
    end
    
    #Unnecessary??? using the accessor lpar.max_virtual_slots should
    #result in the same effect without the need for an HMC command...
    #Returns 30 when test in dublin lab on frame: rslppc03 lpar:dwin004
    def get_max_virtual_slots
        #max_slots = execute_cmd "lshwres --level lpar -r virtualio --rsubtype slot  -m #{frame} --filter lpar_names=#{lpar} -F curr_max_virtual_slots"
        #lpar_prof = get_lpar_curr_profile(frame,lpar)
        max_slots = hmc.execute_cmd "lssyscfg -r prof -m '#{frame}' --filter 'lpar_names=#{name},profile_names=#{current_profile}' -F max_virtual_slots"
        return max_slots.chomp.to_i
    end
    
    #Return array of used virtual adapter slots
    #for an LPAR
    def get_used_virtual_slots
        #scsi_slot_output = execute_cmd "lshwres -r virtualio --rsubtype scsi -m #{frame} --level lpar --filter lpar_names=#{lpar} -F slot_num"
        #eth_slot_output = execute_cmd "lshwres -r virtualio --rsubtype eth -m #{frame} --level lpar --filter lpar_names=#{lpar} -F slot_num"
        #serial_slot_output = execute_cmd "lshwres -r virtualio --rsubtype serial -m #{frame} --level lpar --filter lpar_names=#{lpar} -F slot_num"
        #lpar_prof = get_lpar_curr_profile(frame,lpar)
        
        scsi_slot_output = clean_vadapter_string(hmc.execute_cmd "lssyscfg -r prof -m '#{frame}' --filter 'lpar_names=#{name},profile_names=#{current_profile}' -F virtual_scsi_adapters")
        serial_slot_output = clean_vadapter_string(hmc.execute_cmd "lssyscfg -r prof -m '#{frame}' --filter 'lpar_names=#{name},profile_names=#{current_profile}' -F virtual_serial_adapters")
        eth_slot_output = clean_vadapter_string(hmc.execute_cmd "lssyscfg -r prof -m '#{frame}' --filter 'lpar_names=#{name},profile_names=#{current_profile}' -F virtual_eth_adapters")
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
        
        return used_slots
    end
    
    #Get next usable virtual slot on an LPAR
    #Returns nil if no usable slots exist
    def get_available_slot(type = nil)
        max_slots = max_virtual_slots
        used_slots = get_used_virtual_slots
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
    
    #Remove vSCSI from LPAR
    #Handles removing from the LPAR profiles as well as DLPAR
    #Last parameter is optional and if it isn't specified
    #then it looks for an adapter on lpar that is attached to server_lpar
    #and removes that from the profile/hardware of both the client
    #and server
    #MAY BE DANGEROUS- if multiple vSCSI adapters on a single lpar pointing at the same VIO
    def remove_vscsi(server_lpar,adapter_details=nil)
        if adapter_details.nil?
            adapters = get_vscsi_adapters
            adapters.each do |adapter|
                adapter_details = adapter if adapter.remote_lpar_name == server_lpar.name
            end
        end
        
        #Remove this vSCSI from the lpar and server lpar profiles
        remove_vscsi_from_profile(server_lpar,adapter_details)
    
        #Remove this vSCSI from the actual hardware of lpar and server lpar
        remove_vscsi_dlpar(server_lpar,adapter_details)
    
    end
    
    #Remove vSCSI from the LPAR profiles only
    def remove_vscsi_from_profile(server_lpar,vscsi)
        remote_lpar_profile = server_lpar.current_profile
        client_lpar_id = id
             
        client_slot = vscsi.virtual_slot_num
        server_lpar_id = vscsi.remote_lpar_id
        if server_lpar != vscsi.remote_lpar_name
            #server_lpar and the LPAR cited in the
            #vscsi hash aren't the same...
            #error out or do something else here...?
        end
        server_slot = vscsi.remote_slot_num
        is_req = vscsi.is_required
    
        #Modify client LPAR's profile to no longer include the adapter
        #whose details occupy the vscsi_hash
        hmc.execute_cmd("chsyscfg -r prof -m #{frame} -i \"name=#{current_profile},lpar_name=#{name}," +
            "virtual_scsi_adapters-=#{client_slot}/client/#{server_lpar_id}/#{server_lpar.name}/#{server_slot}/#{is_req}\" ")
          
        #Modify the server LPAR's profile to no longer include the client
        hmc.execute_cmd("chsyscfg -r prof -m #{server_lpar.frame} -i \"name=#{remote_lpar_profile},lpar_name=#{server_lpar.name}," +
            "virtual_scsi_adapters-=#{server_slot}/server/#{client_lpar_id}/#{name}/#{client_slot}/#{is_req}\" ")
    
    end
    
    #Remove vSCSI from LPARs via DLPAR
    def remove_vscsi_dlpar(server_lpar,vscsi)
    
        client_slot = vscsi.virtual_slot_num
        server_slot = vscsi.remote_slot_num
    
        #If the client LPAR is running, we have to do DLPAR on it.
        #if check_lpar_state(frame,lpar) == "Running"
        #execute_cmd("chhwres -r virtualio -m #{frame} -p #{lpar} -o r --rsubtype scsi -s #{client_slot}")
        #-a \"adapter_type=client,remote_lpar_name=#{server_lpar},remote_slot_num=#{server_slot}\" ")
        #end
    
        #If the server LPAR is running, we have to do DLPAR on it.
        if server_lpar.is_running?
            hmc.execute_cmd("chhwres -r virtualio -m #{server_lpar.frame} -p #{server_lpar.name} -o r --rsubtype scsi -s #{server_slot}")
            #-a \"adapter_type=server,remote_lpar_name=#{lpar},remote_slot_num=#{client_slot}\" ")
        end
    end
    
    #Add vSCSI to LPAR
    #Handles adding to profile and via DLPAR
    def add_vscsi(server_lpar)
        #Add vscsi to client and server LPAR profiles
        #Save the adapter slots used
        client_slot, server_slot = add_vscsi_to_profile(server_lpar)
    
        #Run DLPAR commands against LPARs themselves (if necessary)
        add_vscsi_dlpar(server_lpar, client_slot, server_slot)
    
        return [client_slot, server_slot]
    end
    
    #Add vSCSI adapter to LPAR profile
    def add_vscsi_to_profile(server_lpar)
        virtual_slot_num = get_available_slot
        remote_slot_num = server_lpar.get_available_slot
        lpar_profile = current_profile
        remote_lpar_profile = server_lpar.current_profile
    
        raise StandardError.new("No available virtual adapter slots on client LPAR #{lpar}") if virtual_slot_num.nil?
        raise StandardError.new("No available virtual adapter slots on server LPAR #{server_lpar}") if remote_slot_num.nil?
    
        #Modify client LPAR's profile
        hmc.execute_cmd("chsyscfg -r prof -m #{frame} -i \"name=#{lpar_profile},lpar_name=#{name},virtual_scsi_adapters+=#{virtual_slot_num}/client//#{server_lpar.name}/#{remote_slot_num}/0\" ")
        #Modify server LPAR's profile
        hmc.execute_cmd("chsyscfg -r prof -m #{server_lpar.frame} -i \"name=#{remote_lpar_profile},lpar_name=#{server_lpar.name},virtual_scsi_adapters+=#{remote_slot_num}/server//#{name}/#{virtual_slot_num}/0\" ")
    
        #Return the client slot and server slot used in the LPAR profiles
        return [virtual_slot_num, remote_slot_num]
    end
    
    #Add vSCSI adapter via DLPAR command
    def add_vscsi_dlpar(server_lpar,client_slot_to_use = nil, server_slot_to_use = nil)
        if client_slot_to_use.nil? and server_slot_to_use.nil?
            client_slot_to_use = get_available_slot
            server_slot_to_use = server_lpar.get_available_slot
        end
    
        #If the client LPAR is running, we have to do DLPAR on it.
        if is_running?
            hmc.execute_cmd("chhwres -r virtualio -m #{frame} -p #{name} -o a --rsubtype scsi -s #{client_slot_to_use} -a \"adapter_type=client,remote_lpar_name=#{server_lpar.name},remote_slot_num=#{server_slot_to_use}\" ")
        end
    
        #If the server LPAR is running, we have to do DLPAR on it.
        if server_lpar.is_running?
            hmc.execute_cmd("chhwres -r virtualio -m #{server_lpar.frame} -p #{server_lpar.name} -o a --rsubtype scsi -s #{server_slot_to_use} -a \"adapter_type=server,remote_lpar_name=#{name},remote_slot_num=#{client_slot_to_use}\" ")
        end
        #chhwres -r virtualio -m "FrameName" -p VioName -o a --rsubtype scsi -s 11 -a "adapter_type=server,remote_lpar_name=ClientLPAR,remote_slot_num=5" 
    end
    
    #TODO: Function that lists Vscsis attached to the LPAR



    #####################################
    # vNIC functions
    #####################################
    
    #TODO: Function that lists any/all vNICs attached to LPAR

    #TODO: remove_vnic function

    #Create vNIC on LPAR
    def create_vnic(vlan_id,addl_vlan_ids = "")
        #default value for is_trunk = 0
        #default value for is_required = 1
        slot_num = get_available_slot("eth")
        create_vnic_profile(slot_num,vlan_id,addl_vlan_ids,0,1)
        
        create_vnic_dlpar(slot_num,vlan_id)
    end
    
    #Create vNIC on LPAR profile
    def create_vnic_profile(slot_number, vlan_id, addl_vlan_ids, is_trunk, is_required)
        ##chsyscfg -m Server-9117-MMA-SNxxxxx -r prof -i 'name=server_name,lpar_id=xx,"virtual_eth_adapters=596/1/596//0/1,506/1/506//0/1,"'
        #slot_number/is_ieee/port_vlan_id/"additional_vlan_id,additional_vlan_id"/is_trunk(number=priority)/is_required
        lpar_prof = current_profile
        
        #Going to assume adapter will always be ieee
        #For is Trunk how do we determine the number for priority? Do we just let the user pass it?
        hmc.execute_cmd("chsyscfg -m #{frame} -r prof -i \'name=#{lpar_prof},lpar_name=#{name},"+
            "\"virtual_eth_adapters+=#{slot_number}/1/#{vlan_id}/\"#{addl_vlan_ids}" +
            "\"/#{is_trunk}/#{is_required} \"\'")
    end
    
    #Create vNIC on LPAR via DLPAR
    #As writen today defaulting ieee_virtual_eth=0 sets us to Not IEEE 802.1Q compatible. To add compatability set value to 1
    def create_vnic_dlpar(slot_number,vlan_id)
        if is_running?
            hmc.execute_cmd("chhwres -r virtualio -m #{frame} -o a -p #{name} --rsubtype eth -s #{slot_number} -a \"ieee_virtual_eth=0,port_vlan_id=#{vlan_id}\"")
        end
    end

    
    #####################################
    # Utility Functions
    #####################################
    
    #Handle strings of multiple vadapters that could be surrounded by
    #stray '"' or evaluate to "none" if there are no vadapters
    def clean_vadapter_string(vadapter_string)
        vadapter_string = "" if vadapter_string.chomp == "none"
        vadapter_string = vadapter_string[1..-1] if vadapter_string.start_with?('"')
        vadapter_string = vadapter_string[0..-2] if vadapter_string.end_with?('"')
        
        return vadapter_string
    end
    
    
    #Three functions used to parse out vSCSI, vSerial
    #and vNIC adapter syntax
    
    def parse_vscsi_syntax(vscsi_string)
        return parse_slash_delim_string(vscsi_string, 
            [:virtual_slot_num, :client_or_server, :remote_lpar_id, :remote_lpar_name, :remote_slot_num, :is_required]) if !vscsi_string.empty?
    end      
    
    def parse_vserial_syntax(vserial_string)
        return parse_slash_delim_string(vserial_string,
            [:virtual_slot_num, :client_or_server, :supports_hmc, :remote_lpar_id, :remote_lpar_name, :remote_slot_num, :is_required]) if !vserial_string.empty?
    end
    
    def parse_vnic_syntax(vnic_string)
        return parse_slash_delim_string(vnic_string,
            [:virtual_slot_num, :is_ieee, :port_vlan_id, :additional_vlan_ids, :is_trunk, :is_required]) if !vnic_string.empty?
    end         
    
    #Parse the slash delimited string (used for vadapters) by
    #separating the elements in the string into a hash
    #with keys based on what is specified in field_specs
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
end
