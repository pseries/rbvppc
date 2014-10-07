class CommandFailure < StandardError
    attr_reader :stderr, :exit_code, :exit_signal
    
    def initialize(stderr, exit_code, exit_signal)
        @stderr, @exit_code, @exit_signal = stderr, exit_code, exit_signal
    end
    
    def to_s
        return @stderr
    end
end