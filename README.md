# rbvppc

Virtual Infrastructure management of IBM pSeries/AIX

## Installation

Add this line to your application's Gemfile:

    gem 'rbppc'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install rbppc
## Example end to end build in irb
In this example we will take you through the steps needed to create a new lpar on a pSeries hypervisor, and execute a network build of the AIX Operating System.
### Load required classes in your irb.
You will need to load the following classes to execute this example
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
first_vhost = lpar.find_vhost_given_virtual_slot(lpar_vscsi[0].remote_slot_num)
second_vhost = lpar.find_vhost_given_virtual_slot(lpar_vscsi[1].remote_slot_num)
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
first_vhost = lpar.find_vhost_given_virtual_slot(lpar_vscsi[0].remote_slot_num)
second_vhost = lpar.find_vhost_given_virtual_slot(lpar_vscsi[1].remote_slot_num)
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






## Contributing

1. Fork it ( http://github.com/<my-github-username>/remote_hmc/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

