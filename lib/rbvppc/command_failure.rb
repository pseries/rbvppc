#
# Authors: Christopher M Wood (<woodc@us.ibm.com>)
#		   John F Hutchinson (<jfhutchi@us.ibm.com)
# © Copyright IBM Corporation 2015.
#
# LICENSE: MIT (http://opensource.org/licenses/MIT)
# 
class CommandFailure < StandardError
    attr_reader :stderr, :exit_code, :exit_signal
    
    def initialize(stderr, exit_code, exit_signal)
        @stderr, @exit_code, @exit_signal = stderr, exit_code, exit_signal
    end
    
    def to_s
        return @stderr
    end
end
