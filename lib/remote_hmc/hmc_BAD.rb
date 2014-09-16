require_relative 'hmc'
   puts 'Instantiate lpar_hash, hmc_ip, hmc_user, hmc_password, and vios_array' 
   vios_array = ["vios1", "vios2"]
   hmc_ip = 'HMC'
   hmc_user = 'username'
   hmc_password = 'password'
   lpar_hash = { :frame              => 'frame',
                 :name               => 'hostname',
                 :hostname           => 'hostname.long.com',
                 :profile_name       => 'hostname_profile',
                 :max_virtual_slots  => '30',
                 :desired_mem        => '1024',
                 :min_mem            => '512',
                 :max_mem            => '2048',
                 :desired_procs      => '1',
                 :min_procs          => '1',
                 :max_procs          => '2',
                 :proc_mode          => 'shared',
                 :sharing_mode       => 'uncap',
                 :desired_proc_units => '1.0',
                 :max_proc_units     => '2.0',
                 :min_proc_units     => '0.5',
                 :uncap_weight       => '123',
                 :vlan_id            => '74',
                 :management_ip      => 'IP'}

   puts 'Instantiate nim_ip, nim_user, nim_password, mksysb_name, spot_name, and fb_script_name'
   nim_ip = "NIM IP"
   nim_user = "root"
   nim_password = "password"
   mksysb_name = "ic2-aix-7100-02-04-1341-20140422"
   spot_name = mksysb_name + "_spot"
   fb_script_name = "Darwin_TPM72_Key_fb_Script"

   puts "Initialize HMC object and connect an SSH session to it"
   #initialize hmc object and open a connection to hmc
   hmc = Hmc.new(hmc_ip, hmc_user , {:password => hmc_password}) 
   hmc.connect
   
   

   puts 'Create an LPAR with attributes from a Hash'      
   #create the lpar 
   hmc.create_lpar(lpar_hash)
   
   puts 'Activate (power on) the LPAR'    
   #activate the lpar (power on)
   hmc.activate_lpar(lpar_hash[:frame],lpar_hash[:name],lpar_hash[:profile_name])
   
   puts 'Shutdown the activated LPAR to add virtual adapters'  
   hmc.hard_shutdown_lpar(lpar_hash[:frame],lpar_hash[:name])
      
   puts 'Add a vNIC adapter to the client LPAR'
   #is_trunk seems to always be 0 and is_required seems to always be 1... no addl_vlan_ids specified
   hmc.create_vnic(lpar_hash[:frame],lpar_hash[:name],lpar_hash[:vlan_id],"","0","1")

   puts 'Add a vSCSI adapter to the client LPAR and each storage VIO'
   #add a vscsi adapter to each of the storage vios
   first_vscsi_vios = hmc.add_vscsi(lpar_hash[:frame],lpar_hash[:name],vios_array[0])
   
   second_vscsi_vios = hmc.add_vscsi(lpar_hash[:frame],lpar_hash[:name], vios_array[1])
   
   puts 'Activate (power on) the LPAR so that the LPAR syncs the changes to its adapters'    
   #activate the lpar (power on)
   hmc.activate_lpar(lpar_hash[:frame],lpar_hash[:name],lpar_hash[:profile_name])
   
   puts 'Shutdown the activated LPAR'  
   hmc.hard_shutdown_lpar(lpar_hash[:frame],lpar_hash[:name])

   puts 'Find the newly created vhost on the first VIO'    
   #find vhost given slot
   first_vios_vhost = hmc.find_vhost_given_virtual_slot(lpar_hash[:frame],vios_array[0],first_vscsi_vios[1])
   #first_vios_vhost = hmc.find_vhost_given_virtual_slot(lpar_hash[:frame],vios_array[0],18)
   
   puts 'Find the newly create vhost on the second VIO'
   second_vios_vhost = hmc.find_vhost_given_virtual_slot(lpar_hash[:frame],vios_array[1],second_vscsi_vios[1])
   #second_vios_vhost = hmc.find_vhost_given_virtual_slot(lpar_hash[:frame],vios_array[1],18)
   
   puts 'Select any available disk in the VIO pair'     
   #select any available disk
   available_disk = hmc.select_any_avail_disk(lpar_hash[:frame], vios_array[0], vios_array[1])
   
   puts 'Assign selected disk to the new vhost on both VIOs'    
   #assign disk to vhost
   hmc.assign_disk_vhost(lpar_hash[:frame],vios_array[0], available_disk[:on_vio1], "test_vtd", first_vios_vhost)
   hmc.assign_disk_vhost(lpar_hash[:frame],vios_array[1], available_disk[:on_vio2], "test_vtd", second_vios_vhost)
    
   

   puts 'Initialize NIM object and open an SSH session to it'
   nim = Nim.new(nim_ip, nim_user , {:password => nim_password}) 
   nim.connect

   puts 'Define NIM client for LPAR'
   mac_addr = hmc.get_mac_address(lpar_hash[:frame],lpar_hash[:name])
   nim.define_client(lpar_hash[:name],mac_addr,lpar_hash[:hostname])

   puts 'Create NIM bosinst_data object for LPAR'
   nim.create_bid(lpar_hash[:name])

   puts 'Deploy mksysb image to LPAR client'
   nim.deploy_image(lpar_hash[:name],mksysb_name,spot_name,fb_script_name) do |lpar_name, gw, snm|
       hmc.lpar_net_boot(nim_ip,lpar_hash[:management_ip],gw,snm,lpar_name,lpar_hash[:profile_name],lpar_hash[:frame])
   end

   sleep(30)
   puts 'Select a second available disk in the VIO pair'
   available_disk2 = hmc.select_any_avail_disk(lpar_hash[:frame], vios_array[0], vios_array[1])

   puts 'Assign second selected disk to the new vhost on both VIOs'
   hmc.assign_disk_vhost(lpar_hash[:frame],vios_array[0], available_disk2[:on_vio1], "test_vtd2", first_vios_vhost)
   hmc.assign_disk_vhost(lpar_hash[:frame],vios_array[1], available_disk2[:on_vio2], "test_vtd2", second_vios_vhost)