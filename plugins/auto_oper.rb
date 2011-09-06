Kh.start do
  @request = Regexp.compile(K.c[:request] || "")
  @channel_mask = Regexp.compile(K.c[:mask] || "")
end

Kh.privmsg do |m, module_|
  if module_.kind_of?(K::Client)
    channel_name = "#{m[0]}@#{module_.server_name}" 
    if @channel_mask =~ channel_name && @request =~ m[1].to_s
      nick, = K::UtilMethod.parse_prefix(m.prefix)
      module_.send_data("MODE #{m[0]} +o #{nick}\r\n")
    end
  end
end