#
# Authors: Christopher M Wood (<woodc@us.ibm.com>)
#		   John F Hutchinson (<jfhutchi@us.ibm.com)
# © Copyright IBM Corporation 2015.
#
# LICENSE: MIT (http://opensource.org/licenses/MIT)
# 
class Vscsi

	attr_accessor :virtual_slot_num, 
				  :client_or_server,
				  :remote_lpar_id,
				  :remote_lpar_name,
				  :remote_slot_num,
				  :is_required

	def initialize(virtual_slot_num, client_or_server, remote_lpar_id,
					 remote_lpar_name, remote_slot_num, is_required)


		#Test for the explicitly required parameters
		raise StandardError.new("A vSCSI cannot be defined without a virtual_slot_num") if virtual_slot_num.nil?
		raise StandardError.new("A vSCSI cannot be defined without a client_or_server") if client_or_server.nil?
		raise StandardError.new("A vSCSI cannot be defined without a remote_lpar_id") if remote_lpar_id.nil?
		raise StandardError.new("A vSCSI cannot be defined without a remote_lpar_name") if remote_lpar_name.nil?
		raise StandardError.new("A vSCSI cannot be defined without specifying is_required") if is_required.nil?

		@virtual_slot_num 	= virtual_slot_num
		@client_or_server 	= client_or_server
		@remote_lpar_id		= remote_lpar_id
		@remote_lpar_name   = remote_lpar_name
		@remote_slot_num	= remote_slot_num
		@is_required		= is_required
		
	end
end
