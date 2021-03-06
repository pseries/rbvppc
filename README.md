﻿# rbvppc

Virtual Infrastructure management of IBM pSeries/AIX

## Installation

Add this line to your application's Gemfile:

    gem 'rbvppc'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install rbvppc
## Example end to end build in irb
In this example we will take you through the steps needed to create a new lpar on a pSeries hypervisor, and execute a network build of the AIX Operating System.
### Load required classes in your irb.
You will need to load the following classes to execute this example(not needed if you installed the gem)
```sh
load 'lpar.rb'
load 'hmc.rb'
load 'vio.rb'
load 'nim.rb'
```
### Create the needed objects for the build
	- Hmc 
	- Nim
	- Lpar
	- Vio - We used dual node VIOS in development and testing of this gem it is recommend to use at least a dual node setup

For the Hmc object you will need the fully qualified domain name or IP address of the HMC Server, as well as, credentials with hscroot level authority
```sh
hmc = Hmc.new("HMC.Fully.Qualified.Domain.Name","hscroot", {:password => "hscroot's password"})
```
For the Nim object you will need the fully qualified domain name or IP address of the NIM Server, as well as, credentials with root level authority
```sh
nim = Nim.new("NIM.Fully.Qualified.Domain.Name","root", {:password => "root's password"})
```
For the VIO objects you will pass the hmc object, the name of your frame/hypervisor and the name of each vio as it is listed in your HMC console.
```sh
vio1 = Vio.new(hmc,'frame name','vio1 lpar name')
vio2 = Vio.new(hmc,'frame name','vio2 lpar name')
```
For the Lpar object we use the minimum amount of data that is needed for this example. Which is the hmc object, the desired processing units, the desired memory, the desired number of vCPU, the frame/hypervisor name, and the lpar name.
```sh
lpar = Lpar.new({:hmc => hmc, :des_proc => '1.0', :des_mem => '4096', :des_vcpu => '1', :frame => '<frame name>', :name => '<lpar name>'})
```
### Open connections to the Hmc and Nim servers
By executing the connect methods you are using the Ruby NET::SSH gem to SSH to each server. These connections will stay open until you execute the disconnect method.
```sh
hmc.connect
nim.connect
```
### Create the LPAR
Executing the create method against you Lpar object will execute the appropriate commands against the HMC server to make an LPAR.
```sh
lpar.create
```
### Add vSCSI adapters
We create two vSCSI adapters on the LPAR itself linking it to each of the VIO servers.
```sh
lpar.add_vscsi(vio1)
lpar.add_vscsi(vio2)
```
### Add virtual ethernet adapter
For this you must pass at least the primary vlan id number to method. This will create a vNIC on the LPAR
```sh
lpar.create_vnic('<VLAN ID>')
```
### Map any available disk to the LPAR
In this example we execute the map_any_disk method, you may also choose to execute map_by_size to indicate a mimimum amount of space desired.
First we need to collect information on the vSCSI adapters we just created.
```sh
lpar_vscsi = lpar.get_vscsi_adapters
```
Then we need to find each vHost, and map a disk to the lpar
```sh
first_vhost = vio1.find_vhost_given_virtual_slot(lpar_vscsi[0].remote_slot_num)
second_vhost = vio2.find_vhost_given_virtual_slot(lpar_vscsi[1].remote_slot_num)
vio1.map_any_disk(first_vhost, vio2, second_vhost)
```
### Power Cycle the LPAR
This step is done so the vNIC gets a MAC address
```sh
lpar.activate
lpar.soft_shutdown
```
### Define the NIM client and bid
To execute a NIM mksysb deployment you must first define the lpar as a NIM client and define it a bid(BOS Install data)
```sh
nim.define_client(lpar)
nim.create_bid(lpar)
```
### Initiate image deployment and LPAR network boot
We then execute the deployment of a mksysb on the NIM server and use the HMC server to network boot the LPAR.
```sh
nim.deploy_image(lpar,"<mksysb>","<First boot script>") do |gw,snm| 
   hmc.lpar_net_boot("NIM IP ADDRESS", "LPAR IP ADDRESS",gw,snm,lpar.name,lpar.current_profile,lpar.frame)
end
```
### Disconnect
Finally we close our connections to the HMC and NIM servers. Congratulations you now have a basic AIX LPAR installed and running
```sh
nim.disconnect
hmc.disconnect
```
### Complete list of steps 
```sh
load 'lpar.rb'
load 'hmc.rb'
load 'vio.rb'
load 'nim.rb'
hmc = Hmc.new("HMC.Fully.Qualified.Domain.Name","hscroot", {:password => "hscroot's password"})
nim = Nim.new("NIM.Fully.Qualified.Domain.Name","root", {:password => "root's password"})
vio1 = Vio.new(hmc,'frame name','vio1 lpar name')
vio2 = Vio.new(hmc,'frame name','vio2 lpar name')
lpar = Lpar.new({:hmc => hmc, :des_proc => '1.0', :des_mem => '4096', :des_vcpu => '1', :frame => '<frame name>', :name => '<lpar name>'})
hmc.connect
nim.connect
lpar.create
lpar.add_vscsi(vio1)
lpar.add_vscsi(vio2)
lpar.create_vnic('<VLAN ID>')
lpar_vscsi = lpar.get_vscsi_adapters
first_vhost = vio1.find_vhost_given_virtual_slot(lpar_vscsi[0].remote_slot_num)
second_vhost = vio2.find_vhost_given_virtual_slot(lpar_vscsi[1].remote_slot_num)
vio1.map_any_disk(first_vhost, vio2, second_vhost)
lpar.activate
lpar.soft_shutdown
nim.define_client(lpar)
nim.create_bid(lpar)
nim.deploy_image(lpar,"<mksysb>","<First boot script>") do |gw,snm| 
   hmc.lpar_net_boot("NIM IP ADDRESS", "LPAR IP ADDRESS",gw,snm,lpar.name,lpar.current_profile,lpar.frame)
end
nim.disconnect
hmc.disconnect
```
## Example Removal of LUNs and deletion of LPAR in irb
This example will show you how to remove all the attached LUNs from an LPAR and delete the LPAR

### Load required classes in your irb.
You will need to load the following classes to execute this example(not needed if you installed the gem)
```sh
load 'lpar.rb'
load 'hmc.rb'
load 'vio.rb'
```
### Create HMC Object
For the Hmc object you will need the fully qualified domain name or IP address of the HMC Server, as well as, credentials with hscroot level authority
```sh
hmc = Hmc.new("HMC.Fully.Qualified.Domain.Name","hscroot", {:password => "hscroot's password"})
```
### Open connections to the Hmc server
By executing the connect methods you are using the Ruby NET::SSH gem to SSH to the server. This connection will stay open until you execute the disconnect method.
```sh
hmc.connect
```
### Create VIO objects
For the VIO objects you will pass the hmc object, the name of your frame/hypervisor and the name of each vio as it is listed in your HMC console.
```sh
vio1 = Vio.new(hmc,'frame name','vio1 lpar name')
vio2 = Vio.new(hmc,'frame name','vio2 lpar name')
```
### Populate a hash of options for the lpar you wish to destroy and use it to make an LPAR object
```sh
lpar_hash = hmc.get_lpar_options(frame_name,lpar_name)
lpar = Lpar.new(lpar_hash)
```

### Unmap all disks from LPAR (this does not format the disks simply detaches them)
```sh
vio1.unmap_all_disks(vio2,lpar)
```
### Delete the LPAR
```sh
lpar.delete
```
### Disconnect from HMC
```sh
hmc.disconnect
```

### Complete script
```sh
#Create HMC Object
hmc = Hmc.new(hmc_fqdn, "hscroot", {:password => hmc_pass})

#Connect to HMC
hmc.connect

#Create a VIO object for both vios
vio1 = Vio.new(hmc,frame_name,vio1_name)
vio2 = Vio.new(hmc,frame_name,vio2_name)

#Populate options hash with lpar information
lpar_hash = hmc.get_lpar_options(frame_name,lpar_name)

#Create LPAR Object based on the hash
lpar = Lpar.new(lpar_hash)

#Unmapp all the disks from the lpar using VIO1 passing the method the 2nd vio and the lpar
vio1.unmap_all_disks(vio2,lpar)

#Delete the LPAR
lpar.delete

#Disconnect from the hmc
hmc.disconnect
```

## Example modifying CPU on an lpar in irb
The following example will show you how to change the processing units and virtual cpu of an LPAR

### Load required classes in your irb.
You will need to load the following classes to execute this example(not needed if you installed the gem)
```sh
load 'lpar.rb'
load 'hmc.rb'
load 'vio.rb'
```
### Create HMC Object
For the Hmc object you will need the fully qualified domain name or IP address of the HMC Server, as well as, credentials with hscroot level authority
```sh
hmc = Hmc.new("HMC.Fully.Qualified.Domain.Name","hscroot", {:password => "hscroot's password"})
```
### Open connections to the Hmc server
By executing the connect methods you are using the Ruby NET::SSH gem to SSH to the server. This connection will stay open until you execute the disconnect method.
```sh
hmc.connect
```
### Populate a hash of options for the lpar you wish to modify and use it to make an LPAR object
```sh
lpar_hash = hmc.get_lpar_options(frame_name,lpar_name)
lpar = Lpar.new(lpar_hash)
```
### Change maximum vCPU
This will change the maximum number of virtual cpus the LPAR has (warning: power cycles the LPAR)
```sh
lpar.max_vcpu=(<non float number>) 
```

### Change the maximum number of processing units 
This will change the maximum number of physical CPU, warning: power cycles the LPAR
```sh
lpar.max_proc_units=(<float number>)
```
example float number 2.0
### Disconnect from the hmc
```sh
hmc.disconnect
```

### Complete script
```sh
#Create HMC Object
hmc = Hmc.new(hmc_fqdn, "hscroot", {:password => hmc_pass})

#Connect to HMC
hmc.connect

#Populate options hash with lpar information
lpar_hash = hmc.get_lpar_options(frame_name,lpar_name)

#Create LPAR Object based on the hash
lpar = Lpar.new(lpar_hash)

#Change vCPU
lpar.max_vcpu=(<non float number>) 

#Change proc units
lpar.max_proc_units=(<float number>)

#Disconnect from the hmc
hmc.disconnect
```


## Contributing

### Coding

* Pick a task:
  * Offer feedback on open [pull requests](https://github.com/pseries/rbvppc/pulls).
  * Review open [issues](https://github.com/pseries/rbvppc/issues) for things to help on.
  * [Create an issue](https://github.com/pseries/rbvppc/issues/new) to start a discussion on additions or features.
* Fork the project, add your changes and tests to cover them in a topic branch.
* Commit your changes and rebase against `softlayer/fog` to ensure everything is up to date.
* [Submit a pull request](https://github.com/pseries/rbvppc/compare/).

### Non-Coding

* Offer feedback on open [issues](https://github.com/pseries/rbvppc/issues).
* Organize or volunteer at events.

## Legal stuff
Use of this software requires runtime dependencies.  Those dependencies and their respective software licenses are listed below.

* [net-ssh](https://github.com/net-ssh/net-ssh/) - LICENSE: [MIT](https://github.com/net-ssh/net-ssh/blob/master/LICENSE.txt)
* [net-scp](https://github.com/net-ssh/net-scp/) - LICENSE: [MIT](https://github.com/net-ssh/net-scp/blob/master/LICENSE.txt)