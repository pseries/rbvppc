require_relative 'connectable_server'

=begin

Assumptions:
-We will adopt the following naming convention to find/use/manage bosinst_data (BID) for a client LPAR:
   LPAR Name = "lpar123" => BID Name = "lpar123_bid"
   
-All BID objects are assumed to be stored in /darwin of the NIM (for now)

TO-DO:
-Some functions that uses client_lpar as an input contains commented out versions of lines
 citing client_lpar.name instead of just client_lpar. Use these lines when we convert the functions
 to use LPAR obects and not just pass names.
=end

class Nim < ConnectableServer


   #Execute commands on NIM, outputting the full command
   #with puts first.
   def execute_cmd(command)
       puts "#{command}"
       super "#{command}"
   end  
  
   #list mksysb
   def list_images
      execute_cmd "lsnim -t mksysb"
   end
   
   #list all defined NIM objects
   def list_all_NIM_objects
       execute_cmd "lsnim"
   end
    
   #list all defined objects of a specific type
   #acceptable types are (standalone,ent,lpp_source,mksysb,spot,fb_script,script)
   def list_nim_objtype(type)
      case type
      when "standalone","ent","lpp_source","mksysb","spot","fb_script","script","bosinst_data"
         output = execute_cmd "lsnim -t #{type}"
      else
         raise StandardError.new("Unknown type of NIM Object passed")
      end
      objects = []
      output.each_line do |line|
         line.chomp!
         columns = line.split(/[[:blank:]]+/)
         objects.push(columns[0]) if !columns[0].empty?
      end
      
      return objects
   end
    
   #Is the NIM Client defined?
   def client_defined?(client_lpar)
      #lsnim -Z lpar_name_here 2>/dev/null | awk '(NR==2) {print $1}' | awk -F: '{print $2}'
      #result = execute_cmd "lsnim -Z #{client_lpar} 2>/dev/null | " + 
      result = execute_cmd "lsnim -Z #{client_lpar.name} 2>/dev/null | " +
                             "awk '(NR==2) {print $1}' | awk -F: '{print $2}'"
      return result.chomp == "machines"
   end
   
   #Define the NIM Client
   def define_client(client_lpar)
      #Call to TPM's define client script:
      #/tmp/nim_define_client_g01acxwas082.sh tio_name=g01acxwas082 ipaddr=9.57.170.114 ifname=en1 macaddr=82B1F2593C03 nic_speed=auto nic_duplex=auto nim_service=shell netboot_kernel=64 nim_name=
      if client_defined?(client_lpar)
         remove_client(client_lpar)
      end
      execute_cmd %Q{nim -o define -t standalone -a if1="find_net #{client_lpar.hostname} #{client_lpar.get_mac_address}" -a cable_type1="N/A" -a platform=chrp -a comments="Built by Darwin" -a net_settings1="auto auto" -a connect="shell" -a netboot_kernel=#{master_netboot_kernel} #{client_lpar.name}}
      #execute_cmd %Q{nim -o define -t standalone -a if1="find_net #{hostname} #{mac}" -a cable_type1="N/A" -a platform=chrp -a comments="Built by Darwin" -a net_settings1="auto auto" -a connect="shell" -a netboot_kernel=#{master_netboot_kernel} #{client_lpar}}
   end
   
   #Pull the netboot_kernel attribute from NIM master object
   def master_netboot_kernel
      result = execute_cmd "lsnim -l master | awk '{if ($1 ~ /netboot_kernel/) print $3}'"
      return result.chomp
   end
   
   #Reset a NIM client
   def reset_client(client_lpar)
       execute_cmd "nim -F -o reset #{client_lpar.name}"
       #execute_cmd "nim -F -o reset #{client_lpar}"
   end

   #Deallocates any/all NIM resources from the client manchine
   def deallocate_resources(client_lpar)
      execute_cmd "nim -o deallocate -a subclass=all #{client_lpar.name}"
   end
   
   #Remove a NIM client
   def remove_client(client_lpar)
      deallocate_resources(client_lpar)
      execute_cmd "nim -F -o remove #{client_lpar.name}"
   end
   
   #Check the install status of a NIM client
   #Returns current Cstate attribute of NIM client
   def check_install_status(client_lpar)
      #lsnim -Z -a Cstate -a Mstate -a Cstate_result -a info nim_client_name
      result = execute_cmd "lsnim -Z -a Cstate -a Mstate -a Cstate_result -a info #{client_lpar.name}"
      #result = execute_cmd "lsnim -Z -a Cstate -a Mstate -a Cstate_result -a info #{client_lpar}"
      result.each_line do |line|
         line.match(/#{client_lpar.name}/) do |m|
         #line.match(/#{client_lpar}/) do |m|
            #Cstate is the 2nd column of the : delimited output
            cstate = line.split(/:/)[1]
            return cstate
         end
      end
      return nil
   end
    
   #Capture a mksysb image from a NIM client
   def capture_image(source_lpar)
      #Pull mksysb from a NIM client, give it a name and place it in some location on the NIM
      execute_cmd "nim -o define -t mksysb -F -a server=master -a location=/mksysb/goes/here -a source=#{source_lpar.name} -a mk_image=yes -a mksysb_flags=XAe mksysbName"
      #execute_cmd "nim -o define -t mksysb -F -a server=master -a location=/mksysb/goes/here -a source=#{source_lpar} -a mk_image=yes -a mksysb_flags=XAe mksysbName"
      
      #Create SPOT resource from this mksysb, giving it a name and a location on the NIM to store it
      execute_cmd "nim -o define -t spot -a server=master -a source=mksysbName -a location=/spot/goes/here -a auto_expand=yes spotName"
      
   end
   
   #Deploy mksysb image to NIM client
   def deploy_image(client_lpar, mksysb_name, spot_name, firstboot_script, lpp_source = nil)
      
      bosinst_data_obj = client_lpar.name+"_bid"
      #NIM command to start a remote mksysb install on NIM client
      execute_cmd "nim -o bos_inst -a source=mksysb -a mksysb=#{mksysb_name} -a bosinst_data=#{bosinst_data_obj} -a no_nim_client=no " +
                  "-a fb_script=#{firstboot_script} -a accept_licenses=yes -a spot=#{spot_name} -a boot_client=no #{client_lpar.name}"
                  #"-a fb_script=#{firstboot_script} -a accept_licenses=yes -a spot=#{spot_name} -a boot_client=no #{client_lpar}"
      
      
      #Then, in order to actually start the install the HMC needs to netboot the LPAR
      #Should that be called from here or just utilized separately from the HMC object?
      #Maybe yeild to a block that should call the HMC LPAR netboot?
      #Then upon returning to this function, we poll the NIM client for Cstate statuses
      #until the build is finished?
      network_name = get_lpar_network_name(client_lpar)
      gateway = get_network_gateway(network_name)
      subnetmask = get_network_subnetmask(network_name)
      
      yield(client_lpar,gateway,subnetmask)
      
      until check_install_status(client_lpar).match(/ready for a NIM operation/i) do
         puts "Waiting for BOS install for #{client_lpar.name} to finish...."
         sleep 30
      end
      
   end
   
   #Returns the filesystem location of the mksysb with the specified name
   def get_mksysb_location(mksysb_name)
      execute_cmd("lsnim -l #{mksysb_name} | awk '{if ($1 ~ /location/) print $3}'").chomp
   end
   
   #Creates a bosinst_data object for the client_lpar specified
   def create_bid(client_lpar)
      if bid_exists?(client_lpar)
         #Force remove the BID and then continue to create a new one.
         remove_bid(client_lpar)
      end
      
      #Use heredoc to populate the bosinst_data file in a multiline string
      bid_contents = <<-EOS
      # bosinst_data file created for #{client_lpar.name}
      
      CONSOLE = Default
      RECOVER_DEVICES = no
      INSTALL_METHOD = overwrite
      PROMPT = no
      EXISTING_SYSTEM_OVERWRITE = any
      ACCEPT_LICENSES = yes
      
      locale:
      BOSINST_LANG = en_US
      CULTURAL_CONVENTION = en_US
      MESSAGES = en_US
      KEYBOARD = en_US
      EOS
      
      #Create bid contents file on NIM
      execute_cmd "mkdir -p /darwin; echo '#{bid_contents}' > /darwin/#{client_lpar.name}_bid"
      
      
      #Define the BID object
      execute_cmd "nim -o define -t bosinst_data -a location=/darwin/#{client_lpar.name}_bid -a server=master #{client_lpar.name}_bid"
      
      #Create bid contents file on NIM
      #execute_cmd "mkdir -p /darwin;echo \"#{bid_contents}\" > /darwin/#{client_lpar}_bid"
      
      #Define the BID object
      #execute_cmd "nim -o define -t bosinst_data -a location=/darwin/#{client_lpar}_bid -a server=master #{client_lpar}_bid"
   end
   
   #Remove the NIM BID object for a client LPAR
   def remove_bid(client_lpar)
      execute_cmd "nim -F -o remove #{client_lpar.name}_bid"
      #execute_cmd "nim -F -o remove #{client_lpar}_bid"
   end
   
   #Checks if BID object exists on NIM for the Client LPAR
   def bid_exists?(client_lpar)
      defined_bids = list_nim_objtype("bosinst_data")
      defined_bids.each do |obj_name|
         #Iterate through array elements returned by list_nim_objtype
         #and check if any of them line up with the BID name for our LPAR
         if (obj_name == "#{client_lpar.name}_bid")
         #if (obj_name == "#{client_lpar}_bid")
            return true
         end
      end
      return false
   end
   
   #Find NIM interface settings for client LPAR
   def get_lpar_network_name(client_lpar)
      output = execute_cmd "lsnim -Z -a if1 #{client_lpar.name}"
      nim_network=""
      output.each_line do |line|
         line.chomp!
         if line.match(/^#{client_lpar.name}/)
            network_args = line.split(/:/)
            nim_network = network_args[1]
         end
      end
      return nim_network
   end
   
   #Find Gateway IP for NIM network
   def get_network_gateway(network_name)
      output = execute_cmd "lsnim -Z -a net_addr -a snm -a routing #{network_name}"
      output.each_line do |line|
         line.chomp!
         if line.match(/^#{network_name}/)
            network_fields = line.split(/:/)
            return network_fields[-1]
         end
      end
   end
   
   #Find Subnet mask for NIM network
   def get_network_subnetmask(network_name)
      output = execute_cmd "lsnim -Z -a net_addr -a snm -a routing #{network_name}"
      output.each_line do |line|
         line.chomp!
         if line.match(/^#{network_name}/)
            network_fields = line.split(/:/)
            return network_fields[2]
         end
      end
   end
   
   #Add a NIM network object
   def add_network
      
   end
   
end
