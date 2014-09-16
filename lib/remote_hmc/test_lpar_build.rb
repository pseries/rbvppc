=begin
Creating the LPAR: (HMC)
    specify min, max, desired values for Processing Units, Memory, and vCPUs
    Command : mksyscfg -r lpar -m "rslppc03" -i "name=dwin006,
                                                 profile_name=dwin006_prof,
                                                 boot_mode=norm,
                                                 auto_start=0,
                                                 lpar_env=aixlinux,
                                                 max_virtual_slots=30,
                                                 desired_mem=1024,
                                                 min_mem=1024,
                                                 max_mem=1024,
                                                 desired_procs=1,
                                                 min_procs=1,
                                                 max_procs=1,
                                                 proc_mode=shared,
                                                 sharing_mode=uncap,
                                                 desired_proc_units=1.0,
                                                 max_proc_units=1.00,
                                                 min_proc_units=1.00,
                                                 uncap_weight=1,
                                                 \"virtual_eth_adapters=2/1/73//0/1\"" 
                                                 
Activate the LPAR initially:  (HMC)
    turn on LPAR and allow the HMC to allocate vCPU,Memory, and Processing Units to the LPAR
    Command : chsysstate -r lpar -m #FRAME -o on -n #LPAR  -f Profile_ name
    
Create Virtual Ethernet Adapter: (HMC possibly VIOS)
	can be done as a part of the initial LPAR creation
	either:
		i) Create a vNIC(object) via the HMC and attach to correct VLAN
		ii) Create vNIC on correct VLAN and attach to client LPAR via Network VIOs (?)
	
Create 2 vSCSI Adapters:
	i) Find unused adapter slot for both the client LPAR and the Primary VIO
	ii) Add vSCSI adapter to the client's LPAR profile, using the unused client and server (VIO) adapter slots
	    Command: chsyscfg -m #FRAME -r prof -i 'name=server_name,
	                                            lpar_id=xx,
	                                            "virtual_scsi_adapters=301/client/4/vio01_server/301/0,303/client/4/vio02/303/0,305/client/4/vio01_server/305/0,307/client/4/vio02_server/307/0"'
	iii) Run DLPAR command(s) to create that same exact vSCSI adapter in real time
	iv) Repeat (i)-(iii), creating an adapter that is mapped to the Secondary VIO
	
Assign rootvg disk to LPAR:  (VIOS via HMC)
	i) Find disk that is both unused and satisfies any size requirements of rootvg
	ii) Find vhost that is associated with the vSCSI created previously, which attaches to the client LPAR
	iii) Create a new Virtual Target Device (VTD) underneath this vhost which maps to the hdisk identified in (i)
	iv) Using either the S/N or PVID of the disk selected in (i), identify this same disk on the Secondary VIO
	v) Find vhost that is associated with the vSCSI created previously, which attaches the Secondary VIO to the client LPAR
	vi) Create a new VTD underneath this vhost which maps to the hdisk identified in (iv)

Install Base OS: (NIM)
	i) Connect to NIM that will build this LPAR's OS:
		a) Create NIM client representing this client LPAR
		b) Create NIM Base OS Install Data (bosinst_data) object specifying build attributes
		c) Check (or create) NIM network in which the client LPAR will reside
		d) Initiate a remote mksysb push to the NIM client
	ii) LPAR Netboot the client LPAR from the HMC so that it receives the remote mksysb push
	iii) Monitor the status of the mksysb deploy by checking the NIM client's status

Attach non-rootvg disks to LPAR: (VIOS via HMC)
	i) For every extra volume group specified:
			a) For every disk needed to satisfy the space required for this volume group:
				1) Assign a disk to the LPAR in a fashion similar to how rootvg's disk was assigned.
			b) Create a Volume Group for all the disks added in (a)
			

Create FSes, Users, Groups, etc: (LPAR? OS?)
	Chef client handles these
  
 
=end

require_relative 'hmc'
require_relative 'nim'
require_relative 'lpar'
require_relative 'automation_request'

class TestLparBuild
    
    vios_array = [vio1, vio2]
    hmc_ip = '1.2.3.4'
    hmc_user = 'hscroot'
    hmc_password = 'password'
    lpar_hash = {:frame              => 'rslppc09',
                 :name               => 'pRuby',
                 :profile_name       => 'pRuby',
                 :max_virtual_slots  => '30',
                 :desired_mem        => '1024',
                 :min_mem            => '1024',
                 :max_mem            => '1024',
                 :desired_procs      => '1',
                 :min_procs          => '1',
                 :max_procs          => '1',
                 :proc_mode          => 'shared',
                 :sharing_mode       => 'uncap',
                 :desired_proc_units => '1.0',
                 :max_proc_units     => '1.0',
                 :min_proc_units     => '1.0',
                 :uncap_weight       => '1'}

                 
    nim_ip = '1.2.3.4'
    nim_user = 'root'
    nim_password = 'password'
    
def build_lpar(options)
        #initialize hmc object and open a connection to hmc
        hmc = Hmc.new(hmc_ip, hmc_user , {:password => hmc_password}) 
        hmc.connect
        
        #create the lpar 
        hmc.create_lpar(lpar_hash)
        
        #add virtual ethernet adapter to lpar                          #no method yet
        #hmc.create_vnic(lpar)
                 
        #add a vscsi adapter to each of the storage vios
        first_vscsi_vios = hmc.add_vscsi(lpar_hash[:frame],lpar_hash[:name],vios_array[0])
        second_vscsi_vios = hmc.add_vscsi(lpar_hash[:frame],lpar_hash[:name], vios_array[1])
           
        #find vhost given slot
        first_vios_vhost = hmc.find_vhost_given_virtual_slot(lpar_hash[:frame],vios_array[0],first_vscsi_vios[1])
        second_vios_vhost = hmc.find_vhost_given_virtual_slot(lpar_hash[:frame],vios_array[0],second_vscsi_vios[1])
        
        #select any available disk
        available_disk = hmc.select_any_avail_disk(lpar_hash[:frame], vios_array[0], vios_array[1])
        
        #assign disk to vhost
        hmc.assign_disk_vhost(lpar_hash[:frame],vios_array[0], available_disk, "hutch_vtd", first_vios_vhost)
        hmc.assign_disk_vhost(lpar_hash[:frame],vios_array[1], available_disk, "hutch_vtd", second_vios_vhost)
        
        #activate the lpar (power on)
        hmc.activate_lpar(lpar)
        
        #disconnect from hmc
        hmc.disconnect
        
=begin        
        nim = Nim.new(nim_ip, nim_user, {:password => nim_password})
        nim.define_client(lpar)
        nim.deploy_image(lpar) #Will Lpar have what image it uses?      #no method yet
        hmc.lpar_net_boot(lpar)                                         #no method yet
        nim.check_install_status(lpar)  
        
         unless nim.check_install_status(lpar) == "CstateSuccess" #Find the actual status message
            puts "installing mysksyb"
         else
            puts "mksysb deployed"   #remember to check for other than installing and success. 
         end
         
         #power down?
         disks_on_vio1[] = hmc.find_disk(vio1)         #no method yet
         disks_on_vio2[] = hmc.find_disk(vio2)         #no method yet
         #Do we make another vHost?

         Attach non-rootvg disks to LPAR: (VIOS via HMC)
     	i) For every extra volume group specified:
			a) For every disk needed to satisfy the space required for this volume group:
				1) Assign a disk to the LPAR in a fashion similar to how rootvg's disk was assigned.
			b) Create a Volume Group for all the disks added in (a)
=end
        
        
        
end
    
end