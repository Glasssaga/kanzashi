module Kanzashi
  # a module to communicate with IRC servers as a client
  module Client
    include Kanzashi
    @@relay_to = [] # an array includes connections to relay

    def initialize(server_name, encoding, use_tls=false)
      @server_name = server_name
      @encoding = Encoding.find(encoding)
      @channels = {}
      @buffer = BufferedTokenizer.new("\r\n")
      @use_tls = use_tls
    end

    def post_init
      start_tls if @use_tls # enable TLS
    end

    # add new connection from clients
    def self.add_connection(connection)
      @@relay_to << connection
    end

    # rewrite channel names for Kanzashi clients
    def channel_rewrite(line)
      params = line.split
      params.each do |param|
        if /^:?(#|%|!)/ =~ param
          channels = param.split(",")
          channels.map! { |channel| "#{channel}@#{@server_name}" }
          param.replace(channels.join(","))
          break
        end
      end
      params.join(" ").concat("\r\n")
    end

    def receive_line(line)
      m = Net::IRC::Message.parse(line)
      line.encode!(Encoding::UTF_8, @encoding, {:invalid => :replace})
      case m.command
      when "PING"
        send_data "PONG #{config[:user][:nick]}\r\n" # reply to ping
      when "JOIN"
        channel_sym = m[0].to_s.to_sym
        @channels[channel_sym] = [] unless @channels.has_key?(channel_sym)
#        relay(channel_rewrite(line))
      when "332", "333", "366"
        channel_sym = m[1].to_s.to_sym
        rewrited_message = channel_rewrite(line)
        @channels[channel_sym] << rewrited_message if @channels.has_key?(channel_sym)
        relay(rewrited_message)
      when "353"
        channel_sym = m[2].to_s.to_sym
        rewrited_message = channel_rewrite(line)
        @channels[channel_sym] << rewrited_message if @channels.has_key?(channel_sym)
        relay(rewrited_message)
      else
        debug_p line
        relay(channel_rewrite(line))
      end
    end

    # process receiveed data
    def receive_data(data)
      @buffer.extract(data).each do |line|
        line.concat("\r\n")
        receive_line(line)
      end
    end

    def relay(data)
      @@relay_to.each { |r| r.receive_from_server(data) }
    end

    def join(channel_name)
      channel_sym = channel_name.to_sym
      if @channels.has_key?(channel_sym) # cases that kanzashi already joined specifed channnel
        @channels[channel_sym].each {|line| relay(line) } # send cached who list
      else # cases that kanzashi hasn't joined specifed channnel yet
        send_data("JOIN #{channel_name}\r\n")
      end
    end

    def send_data(data)
      debug_p self
      debug_p data
      data.encode!(@encoding, Encoding::UTF_8, {:invalid => :replace})
      super
    end
  end
end