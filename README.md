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
## <bold>HMC</bold>
### Creating/Instantiating-
 To create a new HMC object simply call the .new method with the following options.
##### Hostname/IP Address - Can be either the hostname or the ip address.
##### Username - It is required that the id have hscroot level authority to method correctly.
##### Options -
###### :password - needed if not using rsa keys.
###### :port - defaults to 22 if not specified.
###### :key - fully qualified location of the rsa public key.
#### <bold>Example usage</bold>
##### hmc = Hmc.new(hostname,user,{:password => "password"})
### Usage
#### Connecting - To open a connection to your hmc simply call the .connect method 
##### Example usage
###### hmc.connect
#### Disconnecting - To close the connection to your hmc simply call the .disconnect method
##### Example usage
###### hmc.disconnect
#### Executing command - To execute a command against the hmc call the .execute_cmd method with the following options.
##### command - valid hmc command you wish to execute.
##### Example usage
###### hmc.execute_cmd(command)
#### Executing commands against VIOS via HMC - call the .execute_vios_cmd method with the following options.
##### Frame - name of the hypervisor managed by your HMC. 
##### VIO - name of the VIO lpar you with to execute command against.
##### command - the VIO command you wish to execute.
##### Example Usage
###### hmc.execute_vios_cmd(frame,vios,command)
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

