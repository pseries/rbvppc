class Network
	attr_accessor :ip_address, :is_primary, :subnet_mask, :gateway, :dns, :given_name, :vlan_id

	def initialize(options_hash)
		#Test for the explicitly required parameters
		raise StandardError.new("A Network cannot be defined without a IP Address") if options_hash[:ip_address].nil?
		raise StandardError.new("A Network cannot be defined without a Subnet Mask") if options_hash[:subnet_mask].nil?
		raise StandardError.new("A Network cannot be defined without specifying if it is the primary network or not") if options_hash[:is_primary].nil? or (options_hash[:is_primary] != "false" and options_hash[:is_primary] != "true")
        
		#Test for optional parameters
		warn ("Warning: Gateway not defined") if options_hash[:gateway].nil?
		warn ("Warning: DNS not defined") if options_hash[:dns].nil?
		warn ("Warning: VLAN ID not defined") if options_hash[:vlan_id].nil?
		warn ("Warning: Given Name not defined") if options_hash[:given_name].nil?
		
		#Parameters
		@ip_address				= options_hash[:ip_address]
		@is_primary 			= options_hash[:is_primary]
		@subnet_mask			= options_hash[:subnet_mask]
		@gateway				= options_hash[:gateway]
		@dns					= options_hash[:dns]
		@given_name				= options_hash[:given_name]
		@vlan_id				= options_hash[:vlan_id]
      
	end
	
	def update_dns(new_dns,old_dns=nil)
		if old_dns.nil?
			if new_dns.is_array?
				@dns = new_dns
			else
				@dns = [new_dns]
			end
		else
			#find index of old_entry in @dns
			i = @dns.index(old_dns)
			@dns[i] = new_entry
		end

	def update_gateway(new_gateway)
		@gateway = new_gateway
	end
	
	def update_given_name(new_name)
		@vlan_id = new_name
	end
end
