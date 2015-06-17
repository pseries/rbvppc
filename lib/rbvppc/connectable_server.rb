=begin  
TODO:  
      1.Add Connectivity Methods for Non SSH connections.
      2.Check if the password is passed in clear text or not
      
=end    

require 'rubygems'
require 'net/ssh'
require_relative 'command_failure'

class ConnectableServer

    attr_reader  :debug

    def initialize(hostname, username, options)
        options[:protocol] = :ssh if !options.has_key? :protocol
        options[:port] = 22 if (options[:protocol] == :ssh) && (!options.has_key? :port)
        @hostname, @username, @options = hostname, username, options
        @session = nil
        @debug ||= false
    end 

    def connected?
        ! @session.nil?
    end

    #Debug attribute toggle for childen classes
    #to employ for logging purposes
    def toggle_debug
      @debug ^= true
    end

    def connect
        # @session = Net::SSH.start(@hostname, @username, :password => @password, :port => @port)
        if (@options[:key] && !@options[:password]) then
            @session = Net::SSH.start(@hostname, @username, :key => @options[:key], :port => @options[:port])
        elsif (@options[:key] && @options[:password])
            @session = Net::SSH.start(@hostname, @username, :key => @options[:key], :passphrase => @options[:password], :port => @options[:port])
        else
            @session = Net::SSH.start(@hostname, @username, :password => @options[:password], :port => @options[:port])
        end
        true
    end
   
    def execute_cmd(command)
        raise StandardError.new("No connection has been established") if !connected?
        stdout_data = ""
        stderr_data = ""
        exit_code = nil
        exit_signal = nil
        @session.open_channel do |channel|
    	 channel.exec(command) do |ch, success|
      	  unless success
           abort "FAILED: couldn't execute command (@session.channel.exec)"
          end
      	  channel.on_data do |ch,data|
           stdout_data+=data
          end

          channel.on_extended_data do |ch,type,data|
           stderr_data+=data
          end

          channel.on_request("exit-status") do |ch,data|
           exit_code = data.read_long
      	  end

      	  channel.on_request("exit-signal") do |ch, data|
           exit_signal = data.read_long
      	  end
        end
       end
      @session.loop
      raise CommandFailure.new(stderr_data, exit_code, exit_signal) if exit_code != 0
      return stdout_data
      # {:stdout => stdout_data, :stderr => stderr_data, :exit_code => exit_code, :exit_signal => exit_signal}
    end

    def disconnect
      @session.close
      @session = nil
    end

    def toggle_debug
      @debug ^= true
    end
end