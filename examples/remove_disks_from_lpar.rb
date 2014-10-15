require_relative '../lib/rbvppc/hmc'
require_relative '../lib/rbvppc/lpar'
require_relative '../lib/rbvppc/vio'

frame_name = "rslppc09"
lpar_name  = "rslpl003"
vio1_name  = "rslppc09a"
vio2_name  = "rslppc09b"
hmc_fqdn    = "dwinhmc.dub.usoh.ibm.com"
hmc_pass    = "ibm4darwin"

#Create HMC Object
hmc = Hmc.new(hmc_fqdn, "hscroot", {:password => hmc_pass})
#Connect to HMC
hmc.connect
#Populate options hash with lpar information
lpar_hash = hmc.get_lpar_options(frame_name,lpar_name)
#Create LPAR Object based on the hash
lpar = Lpar.new(lpar_hash)
#Create a VIO object for both vios
vio1 = Vio.new(hmc,frame_name,vio1_name)
vio2 = Vio.new(hmc,frame_name,vio2_name)
#Unmapp all the disks from the lpar using VIO1 passing the method the 2nd vio and the lpar
vio1.unmap_all_disks(vio2,lpar)
#Disconnect from the hmc
hmc.disconnect