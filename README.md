# rbvppc

Virtual Infrastructure management of IBM pSeries/AIX

## Installation

Add this line to your application's Gemfile:

    gem 'rbvhmc'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install rbvhmc

# Class Descriptions/Usage
## HMC
### Creating/Instantiating- To create a new HMC object simply call the .new function with the following options.
##### Hostname/IP Address - Can be either the hostname or the ip address.
##### Username - It is required that the id have hscroot level authority to function correctly.
##### Options -
##### :password - needed if not using rsa keys.
##### :port - defaults to 22 if not specified.
##### :key - fully qualified location of the rsa public key.
#### Example usage
* hmc = Hmc.new("hmc.mydomain.com","hscroot",{:password => "password"})
### Connecting
### Usage
### Disconnecting
### NIM
### Creating/Instantiating
### Creating/Deleting/listing NIM Objects
### Deploying a mksysb
### General usage
## LPAR
### Creating/Instantiating
### Importing attributes
### Creating/Deleting LPARs
### Adding vSCSIs
### Adding vNICs
### Add/Remove Compute Resources
### Add/Remove Disks (also see VIO
## VIO
#### Creating/Instantiating
#### Important Attributes
#### Using w/ LPAR objects
#### Selecting disks in a VIO pair
#### Mapping disks
#### Unmapping disks



## Contributing

1. Fork it ( http://github.com/<my-github-username>/remote_hmc/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

