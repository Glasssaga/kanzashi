module Kanzashi
  # a module to communicate with IRC servers as a client
  module Client
    include Kanzashi
    class << self
      include UtilMethod

      # add new connection from clients
      def add_connection(connection)
        @@relay_to << connection
      end
    end

    @@relay_to = [] # an array includes connections to relay

    attr_reader :channels, :nick, :server_name

    def initialize(server_name, encoding, use_tls=false)
      @server_name = server_name.freeze
      @encoding = Encoding.find(encoding)
      @channels = {}
      @buffer = BufferedTokenizer.new(CRLF)
      @use_tls = use_tls
      @nick = config.user.nick
    end

    def client?; true; end
    def server?; false; end
    alias from_server? client?
    alias from_client? server?

    def inspect
      "#<Client:#{@server_name}>"
    end

    alias to_s inspect

    def post_init
      start_tls if @use_tls # enable TLS
    end

    # process received data
    def receive_data(data)
      data.encode!(Encoding::UTF_8, @encoding, EncodeOpt)
      @buffer.extract(data).each do |line|
        line.chomp! # some IRC servers send CR+CR+LF in message of the day
        line.concat(CRLF)
        receive_line(line)
      end
    end

    def send_data(data)
      data.concat(CRLF)
      log.debug("Client #{@server_name}:send_data") { data.inspect }
      data.encode!(@encoding, Encoding::UTF_8, EncodeOpt)
      super
    end

    def nick=(new_nick)
      log.debug("Client #{@server_name}:change_nick") { new_nick.inspect }
      send_data "NICK #{new_nick}"
    end

    def join(channel_name)
      log.debug("Client #{@server_name}:join") { channel_name }
      channel_sym = channel_name.to_sym
      if @channels.has_key?(channel_sym) # cases that kanzashi already joined specifed channnel
        @channels[channel_sym][:cache].each_value {|line| relay(line) } # send cached who list
      else # cases that kanzashi hasn't joined specifed channnel yet
        send_data "JOIN #{channel_name}"
      end
    end

    private

    def relay(data)
      @@relay_to.each { |r| r.receive_from_server(data) }
    end

    def receive_line(line)
      line.force_encoding(Encoding::BINARY)
      begin
        m = Net::IRC::Message.parse(line)
      rescue Net::IRC::Message::InvalidMessage => ex
        puts ex.message.encode!(Encoding::UTF_8)
        return
      end
      line.force_encoding(Encoding::UTF_8)
      m.params.each{|x| x.force_encoding(Encoding::UTF_8) }
      Hook.call(m.command.downcase.to_sym, m, self)
      Hook.call((m.command.downcase + "_from_server").to_sym, m, self)
      case m.command
      when "PING"
        send_data "PONG #{config.user.nick}" # reply to ping
      when "JOIN"
        channel_sym = m[0].to_s.to_sym
        /^(.+?)(!.+?)?(@.+?)?$/ =~ m.prefix
        nic = $1
        if nic == @nick
          @channels[channel_sym] = { :cache => {}, :names => [] } unless @channels.has_key?(channel_sym)
        else
          @channels[channel_sym][:names] << nic
          relay(channel_rewrite(line))
        end
      when "INVITE"
        if K.config[:others][:join_when_invited]
          send_data "JOIN #{m[1]}"
        else
          log.debug("Client #{@server_name}:recv") { line.inspect }
          relay(channel_rewrite(line))    
        end
      when "NICK"
        @nick = m[0].to_s if m.prefix.nick == @nick
        relay(channel_rewrite(line))
      when "002"
        config.networks[@server_name].join_to.each do |channel| # join to channel specifed in config file
          unless /^#/ =~ channel
            if channel.respond_to?(:prepend)
              channel.prepend("#")
            else
              channel.replace("##{channel}")
            end
          end
          join(channel)
          sleep 0.2 # to avoid excess flood
        end
        Kh.call(:client_welcome, self)
      when "332", "333", "366" # TODO: Able to refact
        channel_sym = m[1].to_s.to_sym
        rewrited_message = channel_rewrite(line)
        @channels[channel_sym][:cache][m.command.to_sym] = rewrited_message
        relay(rewrited_message)
      when "353" # reply to NAMES
        channel_sym = m[2].to_s.to_sym
        rewrited_message = channel_rewrite(line)
        @channels[channel_sym][:cache]["353".to_sym] = rewrited_message
        @channels[channel_sym][:names] = m[3].to_s.split # make names list
        relay(rewrited_message)
      else
        log.debug("Client #{@server_name}:recv") { line.inspect }
        begin
          m.params[1].force_encoding(Encoding::BINARY)
          relay(channel_rewrite(line)) unless m.ctcp?
        ensure
          m.params[1].force_encoding(Encoding::UTF_8)
        end
      end
    end

    # rewrite channel names for Kanzashi clients
    def channel_rewrite(line)
      begin
        params = line.split
      rescue ArgumentError => ex
        puts ex.message
      end
      params.each do |param|
        if /^:?(#|&)/ =~ param
          channels = param.split(",")
          channels.each do |channel|
            channel.concat(config.separator)
            channel.concat(@server_name)
          end
          param.replace(channels.join(","))
          break
        end
      end
      params.join(" ").concat(CRLF)
    end
  end
end
