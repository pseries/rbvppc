#
# Authors: Christopher M Wood (<woodc@us.ibm.com>)
#		   John F Hutchinson (<jfhutchi@us.ibm.com)
# © Copyright IBM Corporation 2015.
#
# LICENSE: MIT (http://opensource.org/licenses/MIT)
# 
class Lun
    attr_reader :name, :pvid, :size_in_mb    
    def initialize(name,pvid, size_in_mb)
        @name = name
        #@serial_number = serial_number
        @pvid = pvid
        @size_in_mb = size_in_mb.to_i
    end
    
    
    #Override == to test equality of two disk's PVIDs??
    def ==(other_lun)
       return self.pvid == other_lun.pvid 
    end
    
end
