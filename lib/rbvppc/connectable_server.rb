#
# Authors: Christopher M Wood (<woodc@us.ibm.com>)
#      John F Hutchinson (<jfhutchi@us.ibm.com)
# © Copyright IBM Corporation 2015.
#
# LICENSE: MIT (http://opensource.org/licenses/MIT)
#

require 'rubygems'
require 'net/ssh'
require_relative 'command_failure'

# Class representing servers connected to via SSH
class ConnectableServer
  attr_reader :debug

  def initialize(hostname, username, options)
    options[:protocol] = :ssh unless options.key? :protocol
    options[:port] = 22 if (options[:protocol] == :ssh) && (!options.key? :port)
    @hostname = hostname
    @username = username
    @options = options
    @session = nil
    @debug ||= true
  end

  def connected?
    !@session.nil?
  end

  # Debug attribute toggle for childen classes
  # to employ for logging purposes
  def toggle_debug
    @debug ^= true
  end

  def connect
    if @options[:key] && !@options[:password]
      @session = Net::SSH.start(@hostname, @username,
                                key: @options[:key],
                                port: @options[:port])
    elsif @options[:key] && @options[:password]
      @session = Net::SSH.start(@hostname, @username,
                                key: @options[:key],
                                passphrase: @options[:password],
                                port: @options[:port])
    elsif @options[:key_data] && @options[:passphrase]
      @session = Net::SSH.start(@hostname, @username,
                                keys: @options[:keys],
                                key_data: @options[:key_data],
                                keys_only: @options[:keys_only],
                                passphrase: @options[:passphrase],
                                port: @options[:port])
    else
      @session = Net::SSH.start(@hostname, @username,
                                password: @options[:password],
                                port: @options[:port])
    end
    true
  end

  def execute_cmd(command)
    raise(StandardError, 'No connection has been established') unless connected?
    stdout_data = ''
    stderr_data = ''
    exit_code = nil
    exit_signal = nil
    @session.open_channel do |channel|
      channel.exec(command) do |_, success|
        unless success
          abort "FAILED: couldn't execute command (@session.channel.exec)"
        end
        channel.on_data do |_, data|
          stdout_data += data
        end
        channel.on_extended_data do |_, _, data|
          stderr_data += data
        end
        channel.on_request('exit-status') do |_, data|
          exit_code = data.read_long
        end
        channel.on_request('exit-signal') do |_, data|
          exit_signal = data.read_long
        end
      end
    end
    @session.loop
    if exit_code != 0
      raise CommandFailure.new(stderr_data, exit_code, exit_signal)
    end
    stdout_data
  end

  def disconnect
    @session.close
    @session = nil
  end
end
