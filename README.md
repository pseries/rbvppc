# rbvppc

Virtual Infrastructure management of IBM pSeries/AIX

## Installation

Add this line to your application's Gemfile:

    gem 'rbppc'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install rbppc

## Example End to End build in irb
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
nim.connect
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

