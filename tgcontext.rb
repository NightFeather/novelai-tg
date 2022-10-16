require 'net/https'
require 'json'
require_relative "./http_request.rb"

module Tg
  Exception = Class.new ::Exception
  YourFault = Class.new Exception
  TheirFault = Class.new Exception

  class Update
    attr_reader :entity, :type, :id
    def self.from obj
      o = obj.dup
      i = o.delete 'update_id'
      t = o.keys.first
      Update.new t, i, o[t]
    end
    def initialize type, id, entity
      @type = type
      @id = id
      @entity = entity
    end
  end
  
  class TgContext
    attr_reader :chat_id, :user_id, :message_id
 
    def self.from bot, upd
      TgContext.new bot, upd.entity['chat']['id'], upd.entity['from']['id'], upd.entity['message_id']
    end

    def initialize bot, chat_id, user_id, message_id
      @bot = bot
      @chat_id = chat_id
      @user_id = user_id
      @message_id = message_id
    end

    %w{edit_message delete_message}.each do |m|
      define_method(m) do |*args, **kwargs|
        @bot.send m, chat_id, *args, **kwargs
      end
    end

    %w{message photo file}.each do |m|
      define_method("send_#{m}") do |*args, **kwargs|
        @bot.send "send_#{m}", chat_id, *args, **kwargs
      end
      define_method("reply_#{m}") do |*args, **kwargs|
        @bot.send "send_#{m}", chat_id, *args, reply_to: message_id, **kwargs
      end
    end
  end
  
  class TgBot
    attr_reader :token
    def initialize token
      @token = token
      @offset = 0
    end
  
    def get_updates
      resp = http_request :get_response, 'getUpdates', params: { offset: @offset }
      unless resp.empty?
        @offset = resp.last['update_id'] + 1
      end
      resp.map { |upd| Update.from upd }
    end

    def edit_message chat_id, message_id, text, **kwargs
      http_request :post_form, 'editMessage', body: { chat_id: chat_id, message_id: message_id, text: text }, **kwargs
    end

    def delete_message chat_id, message_id, *, **kwargs
      http_request :post_form, 'deleteMessage', body: { chat_id: chat_id, message_id: message_id}, **kwargs
    end

    def send_message chat_id, text, *, reply_to: nil, **kwargs
      http_request :post_form, 'sendMessage', body: { chat_id: chat_id, text: text, reply_to_message_id: reply_to, parse_mode: 'MarkdownV2' }, **kwargs
    end
  
    def send_photo chat_id, photo, *, caption: nil, reply_to: nil, **kwargs
      http_request :post_multipart, 'sendPhoto',
        body: { chat_id: chat_id.to_s, photo: photo, caption: caption, reply_to_message_id: reply_to&.to_s },
        **kwargs
    end
  
    def send_file chat_id, file, *, caption: nil, reply_to: nil, **kwargs
      http_request :post_multipart,
        'sendDocument',
        body: { chat_id: chat_id.to_s, document: file, caption: caption, reply_to_message_id: reply_to&.to_s },
        **kwargs
    end
  
    private
    def http_request http_method, tg_method, body: nil, params: {}, headers: {}, raw: false, panic_on_error: false
      uri = URI"https://api.telegram.org/bot#{@token}/#{tg_method}"
      uri.query = URI.encode_www_form params
      resp = send_http_request(http_method, uri, body, headers.merge({ 'Accept' => 'application/json' }))
      if raw
        return resp
      else
        if resp.content_type == 'application/json'
          o = JSON.parse resp.read_body
          if o["ok"]
            return o["result"]
          else
            raise Tg::YourFault.new o["description"]
          end
        else
          raise Tg::TheirFault.new "Unexpected content-type: #{resp.content_type}"
        end
      end
    rescue Net::HTTPExceptions => e
      raise Tg::Exception.new e.response.body
    end
  end
end
