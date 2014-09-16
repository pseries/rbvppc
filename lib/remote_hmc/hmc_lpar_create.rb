require_relative 'hmc_base'

hmc = Hmc.new("1.2.3.4","hscroot","password")
hmc.connect

result = hmc.get_managed_systems

create = hmc.create_lpar(frame:             result[1],
			                 name:              "John",
			                 profile:           "Hutch",
 			                 max_virtual_slots: "30",
			     			 desired_mem:       "1024",
			     			 min_mem		    "512",
			    			 max_mem: 			"4096",
						     desired_procs		"1",
			     			 min_procs:         "1",
			    			 max_procs			"1",
			     			 proc_mode: 	    "shared",
			     			 sharing_mode:      "uncap",
			                 desired_proc_units:"1.0",
			     		     max_proc_units: 	"1.0",
			     		     min_proc_units:    "1.0",
			    		 	 uncap_weight:      "128")


hmc.disconnect

