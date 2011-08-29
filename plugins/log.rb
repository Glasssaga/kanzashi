#encoding: utf-8

class Kanzashi::Plugin::Log
  def initialize
    @directory = K.c[:directory] || "log"
    @header = K.c[:header] || "%T"
    @filename = K.c[:filename] || "%Y.%m.%d.txt" 
    @persistent = K.c[:persistent]

    Dir.mkdir(@directory) unless File.directory?(@directory)
  end  

  attr_reader :persistent

  def self.puts(str, dst)
    str = "#{Time.now.strftime(K.c[:header])} #{str}"
    STDOUT.puts(str)
    if @persistent
      @logfiles[server_name][channel].puts(str)
    else
      path = "log/#{dst}/#{Time.now.strftime(K.c[:filename])}"
      File.open(path, "a", ) { |f| f.puts(str) }
    end
  end

  def file_open(dir)
    File.open("#{dir}/#{Time.now.strftime("%Y-%m-%d")}", "a")
  end
end

Kh.start do
  @log = Kanzashi::Plugin::Log.new
  @logfiles = {} if @log.persistent
end

Kh.join do |m, module_|
  if module_.kind_of?(K::Client)
    nick, = K::UtilMethod.parse_prefix(m.prefix)
    if nick == module_.nick # Kanzashi's join
      dir = "log/#{m[0]}@#{module_.server_name}"
      Dir.mkdir(dir) unless File.directory?(dir)
      if @log.persistent 
        @logfiles[module_.server_name.to_sym] = { m[0].to_s.to_sym => K::Plugin::Log.file_open(dir) }
      end
    else # others join
      K::Plugin::Log.puts("+ #{nick} (#{m.prefix}) to #{m[0]}@#{module_.server_name}", "#{m[0]}@#{module_.server_name}")
    end
  end
end

Kh.part do |m, module_|
  if module_.kind_of?(K::Client)
    nick, = K::UtilMethod.parse_prefix(m.prefix)
    K::Plugin::Log.puts("- #{nick} (\"#{m[1]}\")", "#{m[0]}@#{module_.server_name}")
  end
end

Kh.kick do |m, module_|
  if module_.kind_of?(K::Client)
    nick, = K::UtilMethod.parse_prefix(m.prefix)
    K::Plugin::Log.puts("- #{m[1]} by #{nick} from#{m[0]}@#{module_.server_name} (#{m[2]})", "#{m[0]}@#{module_.server_name}")
  end
end

Kh.mode do |m, module_|
  if module_.kind_of?(K::Client) && /^(#|&).+$/ =~ m[0].to_s # to avoid usermode MODE messages
    nick, = K::UtilMethod.parse_prefix(m.prefix)
    K::Plugin::Log.puts("Mode by #{nick}: #{m[0]} #{m[1]} #{m[2]}", "#{m[0]}@#{module_.server_name}")
  end
end

Kh.privmsg do |m, module_|
  p K.c
  unless m.ctcp?
    nick, = K::UtilMethod.parse_prefix(m.prefix)
    if module_.kind_of?(K::Client) # from others
      K::Plugin::Log.puts("<#{m[0]}:#{nick}> #{m[1]}", "#{m[0]}@#{module_.server_name}")
    else # from Kanzashi's client
      K::Plugin::Log.puts(">#{m[0]}:#{module_.user[:nick]}< #{m[1]}", m[0].to_s)
    end
  end
end

Kh.notice do |m, module_|
  unless m.ctcp?
    nick, = K::UtilMethod.parse_prefix(m.prefix)
    if module_.kind_of?(K::Client) # from others
      K::Plugin::Log.puts("(#{m[0]}:#{nick}) #{m[1]}", "#{m[0]}@#{module_.server_name}") unless m[0] == "*"
    else # from Kanzashi's client
      K::Plugin::Log.puts(")#{m[0]}:#{module_.user[:nick]}( #{m[1]}", m[0].to_s)
    end
  end
end

Kh.nick do |m, module_|
  if module_.kind_of?(K::Client)
    nick, = K::UtilMethod.parse_prefix(m.prefix)
    module_.channels.each do |channel, value|
      K::Plugin::Log.puts("#{nick} -> #{m[0]}", "#{channel}@#{module_.server_name}") if value[:names].include?(nick)
    end
  end
end
