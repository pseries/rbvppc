#
# Authors: Christopher M Wood (<woodc@us.ibm.com>)
#      John F Hutchinson (<jfhutchi@us.ibm.com)
# © Copyright IBM Corporation 2015.
#
# LICENSE: MIT (http://opensource.org/licenses/MIT)
# 
#
# Assumptions:
# Operations on LPARs will be done simultaneously to both their current profile and
# the LPAR's hardware itself, removing the need to abstract data into both LPAR attributes
# and attributes of that LPAR's profile.
# Future features:
# May split lpar_profile into a subclass of LPAR in the future, to allow greater levels of 
# customization.

require_relative 'hmc'
require_relative 'vscsi'
require_relative 'network'
require_relative 'vnic'

class Lpar 
    
    attr_accessor   :min_proc_units, :max_proc_units, :desired_proc_units,
                    :min_memory, :max_memory, :desired_memory,
                    :min_vcpu, :max_vcpu, :desired_vcpu,
                    :hostname, :uncap_weight, :max_virtual_slots

    attr_reader   :hmc, :id, :name, :proc_mode, :sharing_mode, :frame,
                    :current_profile, :default_profile
                    
    #Class variable to hold all 'valid' attributes that can be set on an LPAR
    @@valid_attributes = ["min_mem", "desired_mem", "max_mem", "min_num_huge_pages", "desired_num_huge_pages", "max_num_huge_pages",
              "mem_mode", "hpt_ratio", "proc_mode", "min_proc_units", "desired_proc_units", "max_proc_units", "min_procs",
              "desired_procs", "max_procs", "sharing_mode", "uncap_weight", "shared_proc_pool_id", "shared_proc_pool_name",
              "io_slots", "lpar_io_pool_ids", "max_virtual_slots", "hca_adapters", "boot_mode", "conn_monitoring", "auto_start",
              "power_ctrl_lpar_ids", "work_group_id", "redundant_err_path_reporting", "bsr_arrays", "lhea_logical_ports", "lhea_capabilities", "lpar_proc_compat_mode", "electronic_err_reporting"]
  #Small hash to handle translating HMC labels to Lpar class attributes
    @@attr_mapping = {"min_mem"            => "min_memory",
              "max_mem"            => "max_memory",
              "desired_mem"        => "desired_memory",
              "min_proc_units"     => "min_proc_units",
              "max_proc_units"     => "max_proc_units",
              "desired_proc_units" => "desired_proc_units",
              "min_procs"          => "min_vcpu",
              "max_procs"          => "max_vcpu",
              "desired_procs"      => "desired_vcpu"
             }
                
    def initialize(options_hash, disable_auto_reboot = false)
        
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
        @hmc        = options_hash[:hmc]
        @desired_proc_units = options_hash[:des_proc].to_f
        @desired_memory     = options_hash[:des_mem].to_i
        @desired_vcpu       = options_hash[:des_vcpu].to_i
        @frame        = options_hash[:frame]
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
        !options_hash[:default_profile].nil? ? @default_profile = options_hash[:default_profile] : @default_profile = @current_profile
        !options_hash[:sharing_mode].nil? ? @sharing_mode = options_hash[:sharing_mode] : @sharing_mode = "cap"
        @sharing_mode == "uncap" ? @uncap_weight = options_hash[:uncap_weight].to_i : @uncap_weight = nil
        !options_hash[:proc_mode].nil? ? @proc_mode = options_hash[:proc_mode] : @proc_mode = "shared"
        
        #Parameters that hold no value unless the LPAR already exists
        #or create() is called
        !options_hash[:id].nil? ? @id = options_hash[:id] : @id = nil
        @disable_auto_reboot = disable_auto_reboot
        #TODO: Implement the VIO pair as attributes of the LPAR???
    end
    
    #Create an LPAR
    def create
        
        #Stop the create from proceeding if this LPAR already exists
        raise StandardError.new("This LPAR already exists on #{frame}, cannot create #{name}") if exists?

        command = "mksyscfg -r lpar -m #{@frame} -i name=#{@name}, profile_name=#{@current_profile},boot_mode=norm," + 
            "auto_start=0,lpar_env=aixlinux,max_virtual_slots=#{@max_virtual_slots},desired_mem=#{@desired_memory}," + 
            "min_mem=#{@min_memory},max_mem=#{@max_memory},desired_procs=#{@desired_vcpu},min_procs=#{@min_vcpu}," + 
            "max_procs=#{@max_vcpu},proc_mode=#{@proc_mode},sharing_mode=#{@sharing_mode},desired_proc_units=#{@desired_proc_units}," + 
            "max_proc_units=#{@max_proc_units},min_proc_units=#{@min_proc_units}"
        command += ",uncap_weight=#{@uncap_weight}" if !@uncap_weight.nil?
        
        hmc.execute_cmd(command)
    end
    
    #Delete an LPAR
    #Takes an optional array of Vio objects representing
    #the VIO pair that serves storage to this LPAR.
    def delete(vio_array = nil)
        #Check that this LPAR exists before attempting to delete it.
        #If the LPAR does not exist, simply output a warning stating such
        if !exists?
            warn "This LPAR (#{name}) does not currently exist on #{frame} to be deleted."
            return
        end

        #Do a hard shutdown and then remove the LPAR definition
        hard_shutdown unless not_activated?
        sleep(10) until not_activated?

        #If not passed, try to find the VIO servers by looking
        #at this LPAR's vSCSI adapters
        server_lpars = []
        if vio_array.nil?
            vscsis = get_vscsi_adapters
            vscsis.each do |adapter|
                server_lpars.push(adapter.remote_lpar_name)
            end
            server_lpars.uniq!

            #Now if there are only two unique server LPARs
            #that serve this LPAR, we have our VIO servers
            if server_lpars.length == 2
                vio_array = []
                vio_array.push(Vio.new(hmc,frame,server_lpars[0]))
                vio_array.push(Vio.new(hmc,frame,server_lpars[1]))
            else
                warn "Unable to determine this LPAR's VIO servers, proceeding without removing disks"
                vio_array = nil
            end
        end

        #Attempt to remove all of the LPAR's disks/vSCSIs before deleting
        remove_storage(vio_array[0],vio_array[1]) if !vio_array.nil?
        
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
    
    #Returns true if this LPAR actually exists on it's frame
    #Returns false if it doesn't
    def exists?
        #List all LPARs residing underneath this frame
        result = hmc.execute_cmd("lssyscfg -r lpar -m #{frame} -F name").chomp
        #See if any of their names match this Lpar's name
        result.each_line do |line|
            line.chomp!
            if line == name
                return true
            end
        end
        #Return false if none the names listed match this Lpar's name
        return false
    end

    #Returns true/false value depending on if the LPAR is running or not
    #Since an LPAR can have states such as "Not Activated", "Open Firmware", "Shutting Down",
    #this function only helps for when we are explicitly looking for an LPAR to be either "Running" or not.
    def is_running?
        return check_state == "Running" 
    end

    #Similar to is_running? - only returns true if the LPAR's state is "Not Activated".
    #Any other state is percieved as false
    def not_activated?
        return check_state == "Not Activated"
    end
    
    def get_info
        info = hmc.execute_cmd "lssyscfg -r lpar -m \'#{frame}\' --filter lpar_names=\'#{name}\'"
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

    # Set multiple LPAR profile attributes in a single call.
    def set_multi_attr_profile(options)
        profile_options = options.map{|key,val| "#{key}=#{val}"}.join(',')
        cmd = "chsyscfg -m #{frame} -r prof -i \"name=#{current_profile}, lpar_name=#{name}, #{profile_options} \" "
        hmc.execute_cmd(cmd)
    end
    
    #Function to use for all Min/Max attribute changing
    def set_attr_and_reactivate(units,hmc_label)
        #Change the profile attribute
        set_attr_profile(units,hmc_label)
        reactivate unless @disable_auto_reboot
    end

    # Shutdown and reactivate the LPAR so that the attribute changes take effect
    def reactivate
        # Shut down the LPAR
        soft_shutdown unless not_activated?
        # Wait until it's state is "Not Activated"
        sleep(10) until not_activated?
        # Reactivate the LPAR so that the attribute changes take effect
        activate
    end

  # Bulk modifies an LPAR's resources based on the provided hash.
  # The Hash is required to have it's keys represent labels for HMC attributes (ie, min_mem, max_mem, etc)
  # while it's values are what the user requests those attributes be set to for this LPAR.
  # The LPAR is then reactivated once all of the changes are made for them to take effect.
  # The Class Instance variable @@valid_attributes is used to determine if a key in options is a valid
  # attribute. If an attribute in options is deemed invalid, nothing is done with respect to that attribute.
  def modify_resources(options, reboot = true)
    execute = false
    options.each do |key,val|
      execute = false
      if @@valid_attributes.include?(key)
        # Check for min/max/desired in the key to determine if
        # some bound needs to be checked first
        verify_and_handle_attr_bounds(options,key,val)              
        # Handle setting of any instance variables that should change
        # due to this
        map_key_to_attr(key, val)
        execute = true                
      end            
    end 
    # Set LPAR profile 
    set_multi_attr_profile(options) if execute 
    reactivate if reboot
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

    ####################################
    # Misc LPAR Attribute functions
    ####################################

    #Set the Uncapped Processor Weight for this LPAR
    #TODO: change set_attr_profile to set_attr_and_reactivate?
    def uncap_weight=(units)
        if sharing_mode == "uncap"
            set_attr_profile(units,"uncap_weight")
            #set_attr_and_reactivate(units,"uncap_weight")
            @uncap_weight = units
        else
            #Warn user that the sharing mode doesn't permit modifying uncap_weight
            warn "Cannot change uncap_weight on a capped LPAR"
            return nil
        end
    end

    #Set the Maximum number of virtual adapters for this LPAR
    #TODO: change set_attr_profile to set_attr_and_reactivate?
    def max_virtual_slots=(units)
        if units < max_virtual_slots
            #Test to make sure that any occupied slots are
            #less than units
            used_slots = get_used_virtual_slots
            max = used_slots.sort[0]
            raise StandardError.new("Cannot reduce the maximum number of virtual slots to #{units} because slot #{max} is currently in use") if units < max            
        end

        set_attr_profile(units,"max_virtual_slots")
        @max_virtual_slots = units
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
        if is_running?
            hmc.execute_cmd("chhwres -r virtualio -m #{frame} -p #{name} -o r --rsubtype scsi -s #{client_slot}")
            #-a \"adapter_type=client,remote_lpar_name=#{server_lpar},remote_slot_num=#{server_slot}\" ")
        end
    
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
        if client_slot_to_use.nil? or server_slot_to_use.nil?
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
    
    
    #####################################
    # Disk management functions
    #####################################

    #Adds storage to this LPAR using the provided Primary and Secondary VIOs
    #and the amount of storage requested, in GB
    def add_storage(primary_vio,secondary_vio,size_in_gb)
        #Get info about all vSCSIs attached to this LPAR
        attached_vscsis = get_vscsi_adapters

        #Keep track of the number of vSCSI adapters that attach to the
        #VIOs. This should be 2 after finding the vSCSI adapters that attach
        #to each of the VIOs (one for each VIO). If it is more, then there must
        #be more than one vSCSI attached to one or both of the VIOs.
        adapter_count = 0
        primary_vscsi = nil
        secondary_vscsi = nil
        #Find the vSCSI adapters for each VIO
        attached_vscsis.each do |vscsi|
            if vscsi.remote_lpar_name == primary_vio.name
                primary_vscsi = vscsi
                adapter_count += 1
            end

            if vscsi.remote_lpar_name == secondary_vio.name
                secondary_vscsi = vscsi
                adapter_count += 1
            end
        end

        #If the adapter count is greater than 2, that means that at least one of the
        #VIOs in this pair has more than one vSCSI that attaches to this LPAR.
        #Fail out for now.
        #TODO: Add better handling logic that can avoid this issue.
        if adapter_count > 2
            warn "This LPAR has multiple adapter connections to it's VIOs; unable to determine which adapter to attach new disks to..."
            return nil
        end

        #If an adapter cannot not be found for either of the VIOs, fail out
        #because a disk cannot be attached.
        if primary_vscsi.nil? or secondary_vscsi.nil?
            raise StandardError.new("Cannot attach storage to this LPAR. It does not have a vSCSI adapter defined to one of it's VIOs")
        end

        #Use the remote_slot_num attribute of the two vSCSIs that were found
        #to find out the names of the vhosts they reference on each of the VIOs
        primary_vhost = primary_vio.find_vhost_given_virtual_slot(primary_vscsi.remote_slot_num)
        secondary_vhost = secondary_vio.find_vhost_given_virtual_slot(secondary_vscsi.remote_slot_num)

        #Use Vio map_by_size function to map the appropriate disks to both VIOs
        primary_vio.map_by_size(primary_vhost, secondary_vio, secondary_vhost, size_in_gb)
    end

    #Removes/deallocates all storage from this LPAR and unmaps all of these disks
    #on the specified Primary and Secondary VIO servers. The disks attached to
    #the LPAR are assumed to be supplied by the Primary and Secondary VIOs specified.
    def remove_storage(primary_vio,secondary_vio)
        #Deallocates all storage and vSCSI adapters from this LPAR
        primary_vio.unmap_all_disks(secondary_vio, self)
    end

    #Removes/deallocates a disk from the LPAR specified by it's PVID.
    #This disk is assumed to be supplied by the Primary and Secondary VIO specified
    def remove_disk(primary_vio,secondary_vio,pvid)
        #Use unmap_by_pvid Vio function to unmap a single disk from this LPAR.
        primary_vio.unmap_by_pvid(secondary_vio, pvid)
    end

    #####################################
    # vNIC functions
    #####################################
    
    #Gets a list of vNIC objects
    def get_vnic_adapters
        #Get vNIC adapter info from this LPARs profile
        eth_adapter_output = clean_vadapter_string(hmc.execute_cmd("lssyscfg -r prof -m #{frame} --filter 'lpar_names=#{name},profile_names=#{current_profile}' -F virtual_eth_adapters").chomp)
        eth_adapters = []
        #If there are multiple vNICs,
        #they must be split on ',' and handled
        #individually
        if eth_adapter_output.include?(",")
            #TODO: 
            # => Test with vNICs that have Additional VLAN IDs.
            # => If Additional VLAN IDs have commas too, re-evaluate the logic here.
            adapters = eth_adapter_output.split(/,/)
            adapters.each do |adapter|
                split_adapter = adapter.split("/")
                vnic = Vnic.new(split_adapter[0],split_adapter[1],split_adapter[2],split_adapter[3],split_adapter[4],split_adapter[5])
                eth_adapters.push(vnic)
            end
        elsif !eth_adapter_output.empty?
            #If there are no ','s assume the there is only one vNIC defined
            split_adapter = eth_adapter_output.split("/")
            vnic = Vnic.new(split_adapter[0],split_adapter[1],split_adapter[2],split_adapter[3],split_adapter[4],split_adapter[5])
            eth_adapters.push(vnic)
        end

        return eth_adapters
    end

    #Create vNIC on LPAR
    def create_vnic(vlan_id,addl_vlan_ids = "")
        if validate_vlan_id(vlan_id)
            #default value for is_trunk = 0
            #default value for is_required = 1
            slot_num = get_available_slot("eth")
            create_vnic_profile(slot_num,vlan_id,addl_vlan_ids,0,1)
        
            #TODO: Handle logic for dealing with an LPAR
            #that isn't Not Activated, but also isn't
            #Running
            create_vnic_dlpar(slot_num,vlan_id)

            #LPAR requires a power cycle in order to
            #get a MAC address from this vNIC
            if not_activated?
                activate 
                sleep(10) until !not_activated?
                soft_shutdown
            end
        else
           raise StandardError.new("VLAN ID: #{vlan_id} not found on #{frame}")
        end 
    end
    
    #Create vNIC on LPAR profile
    def create_vnic_profile(slot_number, vlan_id, addl_vlan_ids, is_trunk, is_required)
        if validate_vlan_id(vlan_id)
            ##chsyscfg -m Server-9117-MMA-SNxxxxx -r prof -i 'name=server_name,lpar_id=xx,"virtual_eth_adapters=596/1/596//0/1,506/1/506//0/1,"'
            #slot_number/is_ieee/port_vlan_id/"additional_vlan_id,additional_vlan_id"/is_trunk(number=priority)/is_required
            lpar_prof = current_profile
        
            #Going to assume adapter will always be ieee
            #For is Trunk how do we determine the number for priority? Do we just let the user pass it?
            hmc.execute_cmd("chsyscfg -m #{frame} -r prof -i \'name=#{lpar_prof},lpar_name=#{name},"+
                "\"virtual_eth_adapters+=#{slot_number}/1/#{vlan_id}/\"#{addl_vlan_ids}" +
                "\"/#{is_trunk}/#{is_required} \"\'")
        else
            raise StandardError.new("VLAN ID: #{vlan_id} not found on #{frame}")
        end    
    end
    
    #Create vNIC on LPAR via DLPAR
    #As writen today defaulting ieee_virtual_eth=1 sets us to Not IEEE 802.1Q compatible. To add compatability set value to 1
    def create_vnic_dlpar(slot_number,vlan_id)
        if is_running?
            if validate_vlan_id(vlan_id)
                hmc.execute_cmd("chhwres -r virtualio -m #{frame} -o a -p #{name} --rsubtype eth -s #{slot_number} -a \"ieee_virtual_eth=1,port_vlan_id=#{vlan_id}\"")
            else
                raise StandardError.new("VLAN ID: #{vlan_id} not found on #{frame}")
            end      
        end
    end
   
    #Change vlan id of vnic
    def modify_vnic!(slot_number, vlan_id, is_trunk, is_required)

        if validate_vlan_id(vlan_id)
           #Power down
           soft_shutdown unless not_activated?
           sleep 5 until not_activated? 
           hmc.execute_cmd("chsyscfg -r prof -m #{frame} -i \'name=#{current_profile},lpar_name=#{name},\"virtual_eth_adapters=#{slot_number}/1//#{vlan_id}//#{is_trunk}/#{is_required}\"\'")
           activate
        else
          raise StandardError.new("VLAN ID: #{vlan_id} not found on #{frame}")
        end  
    end    

    #list available vlans 
    def list_vlans
        vlans = []
        vlans = hmc.list_vlans_on_frame(frame)
        return vlans
    end

    #validate vlan exists on frame
    def validate_vlan_id(vlan_id)
        vlans = []
        vlans = hmc.list_vlans_on_frame(frame)
        count = 0 
        vlans_length = vlans.length
        vlans.each do |vlan|
            if vlan_id == vlan
               puts "VLAN ID is valid for #{frame}"
               return true
               break
            end            
            count+1
        end
        if count == vlans_length
            puts "VLAN ID not valid for #{frame}"
            return false
        end
    end

    #Removes a vNIC adapter on an LPAR based on the 
    #slot number that the vNIC occupies
    #TODO: Overload parameters to allow a different way to remove vNICs ???
    def remove_vnic(slot_number)
        #Find the vNIC that is desired to be
        #removed
        vnics = get_vnic_adapters
        vnic = nil
        vnics.each do |adapter|
            if adapter.virtual_slot_num == slot_number
                vnic = adapter
            end
        end
        #If no vNIC occupies the slot specified, error out
        raise StandardError.new("vNIC adapter does not currently occupy slot #{slot_number}") if vnic.nil?
        #Remove the vNIC from this LPAR's profile
        remove_vnic_profile(vnic)
        #Remove the vNIC from the LPAR hardware if the LPAR is currently activated
        remove_vnic_dlpar(slot_number)
    end

    #Remove a vNIC on the LPAR's profile denoted by
    #the virtual slot number occupied by the vNIC
    def remove_vnic_profile(vnic)
        hmc.execute_cmd("chsyscfg -m #{frame} -r prof -i 'name=#{current_profile},lpar_name=#{name},"+
                        "\"virtual_eth_adapters-=#{vnic.virtual_slot_num}/#{vnic.is_ieee}/#{vnic.vlan_id}/#{vnic.additional_vlan_ids}" +
                        "/#{vnic.is_trunk}/#{vnic.is_required}\"'")
    end

    #Remove a vNIC on the LPAR via DLPAR denoted by
    #the virtual slot number occupied by the vNIC
    def remove_vnic_dlpar(slot_number)
        if is_running?
            hmc.execute_cmd("chhwres -r virtualio -m #{frame} -o r -p #{name} --rsubtype eth -s #{slot_number}")
        end
    end
    

    #####################################################
    # Private Methods
    #####################################################
    private
    
    #Private function that handles bulk setting of instance variables
    #Used by modify_resources() to handle setting attribute values
    #on the Lpar object after modifying the value on the HMC.
    def map_key_to_attr(key, value)
      if @@attr_mapping.has_key?(key)
        attr_name = @@attr_mapping[key]       
        #Use Object function instance_variable_set to take
        #a string that is the name of an instance variable
        #and change it's value
        instance_variable_set("@" + attr_name, value)
      end
    end
    
    #Private function that is used to ensure that the LPAR attribute key
    #is set to value, while adhereing to any min, max, or desired qualification.
    #options_hash represents a collection of other LPAR attributes that also will be changed.
    #So this hash is checked to see if it contains any bounds shifts that would allow key to
    #also be changed. If none of the bounds related to the attribute key are cited in the hash,
    #the assumption that the attribute bounds should be changed to accomodate this is made.
    def verify_and_handle_attr_bounds(options_hash, key, value)
      split_key = key.split('_')
      #Save the qualifier for the attribute
      #as well it's the base name
      qualifier = split_key[0]      
      split_key.delete_at(0)
      base_attr = split_key.join('_')
      fix_bounds = false
      if ["min","max","desired"].include?(qualifier)
        other_bounds = ["min","max","desired"].select { |x| x!=qualifier }        
        #Since there will only ever be 2 more array elements in other_bounds at this point,
        #assign them, find their labels, find their attribute names,
        #find their current values, and continue with validation
        other_bound_a = other_bounds[0]
        other_bound_b = other_bounds[1]
        bound_a_label = [other_bound_a,base_attr].join('_')
        bound_b_label = [other_bound_b,base_attr].join('_')
        bound_a_instance_var = @@attr_mapping[bound_a_label]
        bound_b_instance_var = @@attr_mapping[bound_b_label]
        bound_a = instance_variable_get("@" + bound_a_instance_var)
        bound_b = instance_variable_get("@" + bound_b_instance_var)
        #Find out if this attribute change doesn't satisfy the current bounds
        this_attr_label = key
        this_attr_value = value
        
        bound_a_new_val = nil
        bound_b_new_val = nil
        
        #If this value does not satisfy the current bounds, take note and
        #rectify it later
        if !satisfies_bounds?(qualifier, this_attr_value, bound_a, bound_b)       
          #Make the new bounds values be what is in the options hash, unless
          #it isn't specified, then just make it the same as what we're trying to change.
          if options_hash.has_key?(bound_a_label)
            bound_a_new_val = options_hash[bound_a_label]
          else
            bound_a_new_val = value
          end
          
          if options_hash.has_key?(bound_b_label)
            bound_b_new_val = options_hash[bound_b_label]
          else
            bound_b_new_val = value
          end
          
          #Check if the bounds might be satisfied if *only one* of the bounds changed
          if satisfies_bounds?(qualifier, this_attr_value, bound_a_new_val, bound_b)
            bound_b_new_val = bound_b
          elsif satisfies_bounds?(qualifier, this_attr_value, bound_a, bound_b_new_val)
            bound_a_new_val = bound_a
          end       
        end
        
        #If this is a vCPU or a Proc Units change, we need to ensure that
        #the new change adheres to the fact that the ratio between vCPUs and
        #Proc Units needs to be 10:1
        if ["procs","proc_units"].include?(base_attr)
          #TODO: Add logic that handles ensuring this 10:1 ratio remains in
          #place after this change.
        end
        
        if !bound_a_new_val.nil? and !bound_b_new_val.nil?
          #Based on how the other_bounds array is constructed earlier,
          #other_bound_a can either be "min" or "max", which helps determine the order
          #in which to set bound_a and bound_b. Also, if the new bound is less than or greater than
          #the old bound will further determine this order.       
          
          #If other_bound_a == 'min', and it's new value is less than the old one,
          #Change this one first, and then the second bound
          #Same for if bound_a is 'max' and it's new value is greater than the old
          if (other_bound_a == "min" and bound_a_new_val <= bound_a) or
             (other_bound_a == "max" and bound_a_new_val > bound_a)
            set_attr_profile(bound_a_new_val, bound_a_label)
            set_attr_profile(bound_b_new_val, bound_b_label)
          elsif (other_bound_a == "min" and bound_a_new_val > bound_a) or
                (other_bound_a == "max" and bound_a_new_val <= bound_a)
            set_attr_profile(bound_b_new_val, bound_b_label)
            set_attr_profile(bound_a_new_val, bound_a_label)
          end
          instance_variable_set("@" + bound_a_instance_var, bound_a_new_val)
          instance_variable_set("@" + bound_b_instance_var, bound_b_new_val)
        end
      end
    end
    
    def satisfies_bounds?(op, val1, val2, val3)
      if op == "min"
        return (val1 <= val2 and val1 <= val3 and val2 >= val3)
      elsif op == "max"
        return (val1 >= val2 and val1 >= val3 and val2 <= val3)
      elsif op == "desired"
        return (val1 >= val2 and val1 <= val3 and val2 <= val3)
      end
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

    #Set the desired number of virtual CPUs for an LPAR using DLPAR commands
    def set_vcpu_dlpar(units)
        #This command adds or removes, it doesn't 'set'
        units > desired_vcpu ? op="a" : op="r"
        difference = (units-desired_vcpu).abs
        if is_running?
            hmc.execute_cmd("chhwres -r proc -m #{frame} -o #{op} -p #{name} --procs #{difference}")
        end
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
