require 'net/https'
require 'json'
require_relative "./http_request.rb"

module Tg
  class Update
    attr_reader :entity, :type, :id
    def self.from obj
      if obj['message']
        Update::Message.new obj['update_id'], obj['message']
      else
        nil
      end
    end
    def initialize type, id, entity
      @entity = entity
      @type = type
      @id = id
    end

    class Message < Update
      def initialize *args
        super 'message', *args
      end
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
      if resp['ok']
        unless resp['result'].empty?
          @offset = resp['result'].last['update_id'] + 1
        end
        resp['result'].map { |upd| Update.from upd }
      else
        raise resp
      end
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
      resp = send_http_request(http_method, uri, body, headers)
      resp.error! if panic_on_error and not resp.is_a? Net::HTTPSuccess
      return JSON.parse resp.read_body unless raw
      resp
    end
  end
end
