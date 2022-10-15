require_relative './tgcontext.rb'
require_relative './novelai.rb'
require 'tempfile'
require 'base64'

@bot = Tg::TgBot.new ENV['TELEGRAM_TOKEN']
@ai = NovelAI.new ENV['NAI_TOKEN']
@owner = ENV['OWNER_ID'].to_i

def nai_config ctx, text
  cmd, rest = text.split " ", 2
  if cmd == 'save'
    ctx.reply_message "`not implemented`"
  elsif cmd == 'load'
    ctx.reply_message "`not implemented`"
  elsif cmd == 'dump'
    ctx.reply_message "`#{@ai.config.to_s}`"
  elsif %w{get set reset}.include? cmd
    if rest.nil? or rest.empty?
      ctx.reply_message "you have to supply a field."
      return
    end
    field, rest = rest.split " ", 2
    if @ai.config.class.fields.keys.map(&:to_s).include? field
      if cmd == 'set'
        @ai.config.send "#{field}=", rest
        ctx.reply_message "done, price change to #{@ai.price}"
      elsif cmd == 'get'
        val = @ai.config.send field
        if val.nil? or val == ''
          ctx.reply_message "`<empty>`"
        else
          ctx.reply_message "`#{val.inspect}`"
        end
      elsif cmd == 'reset'
        @ai.config.send "#{field}=", @ai.config.class.fields[field.to_sym].initial
        ctx.reply_message "done, price change to #{@ai.price}"
      else
        ctx.reply_message <<-EOM.strip
          invalid field #{field}
          valid fields: [#{@ai.config.class.fields.keys.join(", ")}]
        EOM
      end
    else
      ctx.reply_message <<-EOM.strip
        invalid field #{field}
        valid fields: [#{@ai.config.class.fields.keys.join(", ")}]
      EOM
    end
  elsif cmd == 'list'
    ctx.reply_message "`#{@ai.config.class.fields.keys.join("\n")}`"
  else
    ctx.reply_message <<-EOM.strip
    invalid operation #{cmd}
    supported operations: `get, set, list, dump, save, load`
    EOM
  end
end

def nai_handle ctx, text
  if text.nil?
    ctx.reply_message [
      "missing subcommand",
      "subcommand available: `prompt, config, generate, price`"
    ].join("\n")
    return
  end

  cmd, rest = text.split " ", 2
  if cmd == 'prompt'
    if rest.nil? or rest.strip.empty?
      if @ai.prompt.nil? or @ai.prompt.empty?
        ctx.reply_message "`<empty>`"
      else
        ctx.reply_message "`#{@ai.prompt}`"
      end
    else
      @ai.prompt = rest.strip
      ctx.reply_message "done, price change to #{@ai.price}"
    end
  elsif cmd == 'model'
    m = @ai.model
    p cmd, rest, m
    if rest and rest.strip.size > 0
      @ai.model = rest.strip
      if m == @ai.model
        ctx.reply_message "model unchanged."
      else
        ctx.reply_message "model changed, price change to #{@ai.price}"
      end
    else
      if m.nil? or m.empty?
        ctx.reply_message "`<empty>`"
      else
        ctx.reply_message "`#{@ai.model}`"
      end
    end
  elsif cmd == 'config'
    if rest and rest.strip.size > 0
      nai_config ctx, rest
    else
      ctx.reply_message "operations: `get, set, list, dump, save, load`"
    end
  elsif cmd == 'generate'
    if @ai.prompt.nil? or @ai.prompt.empty?
      ctx.reply_message "empty prompt"
    else
      pmpt = @ai.prompt
      r = @ai.generate
      if r.empty?
        ctx.reply_message "Server returned empty response, retry later."
      else
        imev = r.select { |ev| ev['event'] == 'newImage' }.first
        if imev
          f = Tempfile.new ['generated', '.png']
          begin
            f.write Base64.decode64 imev['data']
            f.rewind
            r = ctx.reply_file f
            ctx.reply_message "Error: `#{r['description']}`" unless r['ok']
          ensure
            f.close
          end
        else
          ctx.reply_message "found events: `#{r.map{|e| e['event']}.join(", ")}`"
        end
      end
    end
  elsif cmd == 'price'
    ctx.reply_message "current settings will cost #{@ai.price} on generation."
  else
    ctx.reply_message <<-EOM
      invalid command #{cmd}
      current available options
    EOM
  end
rescue NovelAI::Exception => e
  puts e.full_message
  ctx.reply_message "NovelAI Error: #{e.message.dump}"
end

def handle ctx, msg
  return unless ctx.user_id == @owner 
  return unless msg['text']
  return unless msg['entities']
  return if msg['entities'].empty?
  return unless msg['entities'].first['type'] == 'bot_command'
  cmd_ent = msg['entities'].first
  cmd = msg['text'][cmd_ent['offset'], cmd_ent['length']]
  rest = msg['text'][cmd_ent['offset']+cmd_ent['length']+1, msg['text'].size]
  return nai_handle ctx, rest if cmd == '/nai'
  puts "unknown command: #{msg}"
rescue Tg::Exception => e
  puts e.full_message
end

loop do
  upds = @bot.get_updates
  puts "handling #{upds.size} update#{upds.size > 1 and "s" or ""}" unless upds.empty?
  upds
    .filter { |upd| upd and upd.type == 'message' }
    .each do |upd|
      handle Tg::TgContext.from(@bot, upd), upd.entity
    end
end
