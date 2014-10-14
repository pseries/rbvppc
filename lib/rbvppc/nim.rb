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

require_relative 'connectable_server'

class Nim < ConnectableServer


   #Execute commands on NIM, outputting the full command
   #with puts first.
   def execute_cmd(command)
       puts "#{command}"
       super "#{command}"
   end  
         
   #list all defined objects of a specific type
   #acceptable types are (standalone,ent,lpp_source,mksysb,spot,fb_script,script,bosinst_data,ent)
   def list_objtype(type)
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

   #Return an array of names of mksysbs that exist on this NIM
   def list_images
      list_objtype("mksysb")
   end

   #Capture a mksysb image from a NIM client
   def capture_image(source_lpar,mksysb_name,path)
      #Pull mksysb from a NIM client, give it a name and place it in some location on the NIM
      execute_cmd "nim -o define -t mksysb -F -a server=master -a location=#{path} -a source=#{source_lpar.name} -a mk_image=yes -a mksysb_flags=XAe #{mksysb_name}"
            
      #Create SPOT resource from this mksysb, giving it a name and a location on the NIM to store it
      extract_spot(mksysb_name)     
   end
   
   #Add a mksysb image to this NIM based on the name given and
   #the local file path of the mksysb file on the NIM.
   #Returns the name of the image that is created.
   def add_image(file_path,mksysb_name)
      #Check to make sure a mksysb with this name doesn't already exist
      images = list_images
      if images.include?(mksysb_name)
         raise StandardError.new("A mksysb with the specified name #{mksysb_name} already exists, please specify another name")
      end

      #Add image to the NIM
      execute_cmd "nim -o define -t mksysb -F -a server=master -a location=#{file_path} -a mksysb_flags=XAe #{mksysb_name}"

      #Extract a SPOT from this mksysb
      extract_spot(mksysb_name)

      return mksysb_name
   end

   #Removes a mksysb from the NIM that identifies with the name specified.
   #Attempts to remove the SPOT that was extracted from this mksysb first.
   def remove_image(mksysb_name)
      #Find if this mksysb actually exists on the NIM
      images = list_images
      if !images.include?(mksysb_name)
         warn "#{mksysb_name} does not exist on this NIM."
         return
      end

      #Find and remove the SPOT for this mksysb
      spot_name = get_spot(mksysb_name)
      if !spot_name.nil?
         remove_spot(spot_name)
      end

      #Remove the mksysb from the NIM (along with it's mksysb file)
      execute_cmd("nim -o remove -a rm_image=yes #{mksysb_name}")
   end

   #Deploy mksysb image to NIM client
   def deploy_image(client_lpar, mksysb_name, firstboot_script = nil, lpp_source = nil)
      
      bosinst_data_obj = client_lpar.name+"_bid"
      
      if !lpp_source.nil?
         #TODO: Do something different if an lpp_source is specified...
      end

      #Get the SPOT to use for this image deployment
      spot_name = get_spot(mksysb_name)
      if spot_name.nil?
         #Extract the spot from this mksysb and use it
         spot_name = extract_spot(mksysb_name)
      end

      command = "nim -o bos_inst -a source=mksysb -a mksysb=#{mksysb_name} -a bosinst_data=#{bosinst_data_obj} -a no_nim_client=no " +
                "-a accept_licenses=yes -a boot_client=no"
      command += " -a spot=#{spot_name}" if !spot_name.nil?
      command += " -a fb_script=#{firstboot_script}" if !firstboot_script.nil?
      command += " -a lpp_source=#{lpp_source}" if !lpp_source.nil?
      command += " #{client_lpar.name}"
      #NIM command to start a remote mksysb install on NIM client
      execute_cmd(command)                        
      
      #Then, in order to actually start the install the HMC needs to netboot the LPAR
      #Should that be called from here or just utilized separately from the HMC object?
      #Maybe yeild to a block that should call the HMC LPAR netboot?
      #Then upon returning to this function, we poll the NIM client for Cstate statuses
      #until the build is finished?
      network_name = get_lpar_network_name(client_lpar)
      gateway = get_network_gateway(network_name)
      subnetmask = get_network_subnetmask(network_name)
      
      yield(gateway,subnetmask)
      
      until check_install_status(client_lpar).match(/ready for a NIM operation/i) do
         puts "Waiting for BOS install for #{client_lpar.name} to finish...."
         sleep 30
      end
      
   end

   #Returns the filesystem location of the mksysb with the specified name
   def get_mksysb_location(mksysb_name)
      execute_cmd("lsnim -l #{mksysb_name} | awk '{if ($1 ~ /location/) print $3}'").chomp
   end


   #Returns the name of the SPOT extracted from the supplied mksysb
   def get_spot(mksysb_name)
      spot = execute_cmd("lsnim -l #{mksysb_name} | awk '{if ($1 ~ /extracted_spot/) print $3}'").chomp
      if spot.empty?
         return nil
      else
         return spot
      end
   end

   #Extracts a SPOT from the mksysb image name specified.
   #places the SPOT in a directory location adjacent to 
   #where the mksysb resides
   #If a spot already exists for this mksysb, it's name is
   #simply returned.
   def extract_spot(mksysb_name)
      #Find out if this mksysb exists on the NIM
      if !list_objtype("mksysb").include?(mksysb_name)
         #Mksysb not found - error out?
      end

      spot_name = mksysb_name+"_spot"
      #Find out if a SPOT already exists for this mksysb
      #if so, just return that name.
      temp_name = get_spot(mksysb_name)
      if !temp_name.nil?
         return temp_name
      end

      #Get the location of this mksysb
      mksysb_loc = get_mksysb_location(mksysb_name)

      #Make sure the mksysb location is non-null
      raise StandardError.new("Cannot locate where the image #{mksysb_name} exists on this NIM") if mksysb_loc.nil?

      #Split the mksysb location on '/', pop the mksysb name and directory it resides
      #in off of the array and push "spot" and the spot name onto the array to end up placing
      #the SPOT in ../spot/spot_name
      split_mksysb_path = mksysb_loc.split("/")
      split_mksysb_path.pop
      split_mksysb_path.pop
      split_mksysb_path.push("spot")
      split_mksysb_path.push(mksysb_name+"_spot")
      spot_path = split_mksysb_path.join("/")

      #Make a SPOT from this mksysb with the name <mksysb_name>_spot
      execute_cmd("nim -o define -t spot -a server=master -a source=#{mksysb_name} -a location=#{spot_path} -a auto_expand=yes #{spot_name}")

      #Return the name of the SPOT.
      return spot_name
   end

   #Removes a SPOT object from a NIM based on the name
   def remove_spot(spot_name)
      execute_cmd("nim -Fo remove #{spot_name}")
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
      defined_bids = list_objtype("bosinst_data")
      defined_bids.each do |obj_name|
         #Iterate through array elements returned by list_objtype
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
   
   #Add a NIM network object using the given name, network address,
   #subnet mask, gateway
   def add_network(network_name,network_addr,snm,gw)
      #Ensure that network with this address doesn't already exist
      raise StandardError.new("Network #{network_name} already exists on this NIM") if network_exists?(network_name,network_addr)

      #Execute NIM command to create the network
      #It is assumed that the network addess and the gateway are the same
      execute_cmd("nim -o define -t ent -a net_addr=#{network_addr} -a snm=#{snm} #{network_name}")

      #Add default route to the specified gateway
      add_default_route(network_name,gw)
   end

   #Remove a NIM network given it's name and/or it's
   #network address
   def remove_network(network_name,network_addr=nil)
      #Ensure that the network to remove is actually defined currently
      raise StandardError.new("Network #{network_name} does not exist on this NIM to be removed") if !network_exists?(network_name,network_addr)
      
      #Run command that removes this network from the NIM      
      execute_cmd("nim -Fo remove #{network_name}")
   end

   #Returns true if a network object exists on the NIM
   #with either the specified name or network address.
   #Returns false otherwise.
   def network_exists?(network_name,network_addr=nil)
      network_names = list_objtype("ent")
      if network_names.include?(network_name)
         return true
      end
      network_names.each do |net_name|
         address = execute_cmd("lsnim -l #{net_name} | awk '{if ($1 ~ /net_addr/) print $3}'").chomp
         if address == network_addr
            return true
         end
      end

      return false
   end

   def add_default_route(network_name,gateway)
      #TODO: Add more robust creation/management of NIM network routes, if necessary      
      execute_cmd("nim -o change -a routing1='default #{gateway}' #{network_name}")
   end
end
