#
# Authors: Christopher M Wood (<woodc@us.ibm.com>)
#      John F Hutchinson (<jfhutchi@us.ibm.com)
# © Copyright IBM Corporation 2015.
#
# LICENSE: MIT (http://opensource.org/licenses/MIT)
#
class Vnic
  attr_accessor :virtual_slot_num, :is_ieee, :vlan_id,
                :additional_vlan_ids, :is_trunk, :is_required

  def initialize(virtual_slot_num, is_ieee, vlan_id,
                 additional_vlan_ids, is_trunk, is_required)
    # Test for the explicitly required parameters
    if virtual_slot_num.nil?
      raise(StandardError, 'A vNIC requires a virtual_slot_num')
    end
    if vlan_id.nil?
      raise(StandardError, 'A vNIC requires a vlan_id')
    end
    if is_trunk.nil?
      raise(StandardError, 'A vNIC requires is_trunk be specified')
    end
    if is_required.nil?
      raise(StandardError, 'A vNIC requires is_required be specified')
    end

    is_ieee     ||= 1
    is_trunk    ||= 0
    is_required ||= 1

    @virtual_slot_num    = virtual_slot_num.to_i
    @is_ieee             = is_ieee.to_i
    @vlan_id             = vlan_id.to_i
    @additional_vlan_ids = additional_vlan_ids
    @is_trunk            = is_trunk.to_i
    @is_required         = is_required.to_i
  end
end
