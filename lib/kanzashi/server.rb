module Kanzashi
  # a module behaves like an IRC server to IRC clients.
  module Server
    include Kanzashi
    class << self; include UtilMethod; end

    def initialize
      Client.add_connection(self)
      @buffer = BufferedTokenizer.new("\r\n")
    end

    def post_init
      if config[:server][:tls] # enable TLS
        start_tls(config[:server][:tls].kind_of?(Hash) ? config[:server][:tls] : {})
      end
    end

    def self.start_and_connect
      @@servers = {}
      # connect to specified server
      config[:networks].each do |server_name, value|
        connection = EventMachine::connect(value[:host], value[:port], Client, server_name, value[:encoding], value[:tls])
        @@servers[server_name] = connection
        connection.send_data("NICK #{config[:user][:nick]}\r\nUSER #{config[:user][:user]||config[:user][:nick]} 8 * :#{config[:user][:real]}\r\n")
      end
    end

    def receive_line(line)
      m = Net::IRC::Message.parse(line)
      p m
      if  m.command ==  "PASS"
        p config[:server][:pass]
        p m[0].to_s
        @auth = (config[:server][:pass] == Digest::SHA256.hexdigest(m[0].to_s) || config[:server][:pass] == m[0].to_s)
        p @auth
      end
      close_connection unless @auth
      case m.command
      when "NICK", "PONG"
      when "USER"
        send_data "001 #{m[0]} welcome to Kanzashi.\r\n"
      when "JOIN"
        m[0].split(",").each do |channel|
          channel_name, server = split_channel_and_server(channel)
          server.join(channel_name)
        end
      when "QUIT"
        send_data "ERROR :Closing Link.\r\n"
        close_connection
      else
        send_server(line)
      end
    end

    def receive_data(data)
      @buffer.extract(data).each do |line|
        line.concat("\r\n")
        receive_line(line)
      end
    end

    def split_channel_and_server(channel)
      if /^:?((?:#|%|!).+)@(.+)/ =~ channel
        channel_name = $1
        server = @@servers[$2.to_sym]
      end
      unless server # in the case where the user specifies invaild server
        channel_name = channel
        server = @@servers.first[1] # the first connection of servers list
      end
      [channel_name, server]
    end

    # send data to specified server
    def send_server(line)
      params = line.split
      channels = nil
      channel_pos = params.each.find_index do |param|
        if /#|%|!/ =~ param
          channels = param
          true
        else
          false
        end
      end
      if channels
        channels.split(",").each do |channel|
          channel_name, server = split_channel_and_server(channel)
          params[channel_pos].replace(channel_name)
          server.send_data("#{params.join(" ")}\r\n")
        end
      end
    end

    def receive_from_server(data)
      send_data(data)
    end
  end

end
