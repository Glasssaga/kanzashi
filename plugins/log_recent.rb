Kanzashi::Server.plugin do
  @directory = K::Config.config[:log][:directory] || "log"
  @filename = K::Config.config[:log][:filename] || "%Y.%m.%d.txt"
  @lines = K.c[:lines] || 20

  on :join do |m, server|
    filename = Time.now.strftime(@filename)
    m[0].to_s.split(",").each do |channel_name|
      path = "#{@directory}/#{channel_name}/#{filename}"
      if File.exist?(path)
        File.open(path) do |f|
          recent_log = f.lines.reverse_each.first(@lines)
          recent_log.reverse_each do |line, i|
            line.chomp!
            server.send_data(":Kanzashi NOTICE #{channel_name} :#{line}\r\n")
          end
        end
      end
    end
  end
end
