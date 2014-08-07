=begin
	Assumptions:
	-operations on LPARs will be done simultaneously to both their current profile and
	 the LPAR's hardware itself, removing the need to abstract data into both LPAR attributes
	 and attributes of that LPAR's profile.
	Future features:
	-May split lpar_profile into a subclass of LPAR in the future, to allow greater levels of 
	customization.
=end
require_relative 'connectable_server'

class Lpar 
	
	attr_accessor :min_proc_units, :max_proc_units, :desired_proc_units,
				:min_memory, :max_memory, :desired_memory,
				:min_vcpu, :max_vcpu, :desired_vcpu,
				:id, :status, :current_profile, :name,
				:hostname, :proc_sharing_mode,
				:frame, :hmc
				
				
   	def initialize(des_proc, min_proc, max_proc, des_mem, min_mem, max_mem, des_vcpu, min_vcpu, max_vcpu, id, status, profile, name, hostname, sharing_mode, frame, hmc)
		#super(hostname, user, options_hash)
		@min_proc_units     = min_proc
		@desired_proc_units = des_proc
		@max_proc_units     = max_proc
		@min_memory         = min_mem
		@desired_memory     = des_mem
		@max_memory         = max_mem
		@min_vcpu           = min_vcpu
		@desired_vcpu       = des_vcpu
		@max_vcpu           = max_vcpu
		@id                 = id
		@status             = status
		@current_profile    = profile
		@name               = name
		@hostname 		    = hostname
		@proc_sharing_mode  = sharing_mode
		@frame				= frame
		@hmc				= hmc
   	end
   
    def assign_rootvg_disk
		hmc.assign_rootvg_disk_to_lpar(self)
		   
    end
    
    def get_hmc
   
   end
end