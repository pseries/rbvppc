# RemoteHmc

Virtual Infrastructure management of IBM pSeries/AIX

## Installation

Add this line to your application's Gemfile:

    gem 'remote_hmc'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install remote_hmc

## Class Descriptions/Usage
### HMC
#### Creating/Instantiating
#### Connecting
#### Usage
#### Disconnecting
### NIM
#### Creating/Instantiating
#### Creating/Deleting/listing NIM Objects
#### Deploying a mksysb
#### General usage
### LPAR
#### Creating/Instantiating
#### Importing attributes
#### Creating/Deleting LPARs
#### Adding vSCSIs
#### Adding vNICs
#### Add/Remove Compute Resources
#### Add/Remove Disks (also see VIO)
### VIO
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

