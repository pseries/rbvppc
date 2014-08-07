class Lun
    attr_reader :name, :pvid, :size_in_mb    
    def initialize(name,pvid, size_in_mb)
        @name = name
        #@serial_number = serial_number
        @pvid = pvid
        @size_in_mb = size_in_mb
    end
    
    
    #Override == to test equality of two disk's PVIDs??
    def ==(other_lun)
       return self.pvid == other_lun.pvid 
    end
    
end