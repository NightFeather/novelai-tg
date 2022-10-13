require 'net/https'
require 'json'

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
      resp = http_request :post_form, 'getUpdates', offset: @offset
      if resp['ok']
        unless resp['result'].empty?
          @offset = resp['result'].last['update_id'] + 1
        end
        resp['result'].map { |upd| Update.from upd }
      else
        resp
      end
    end
  
    def send_message chat_id, text, *, reply_to: nil
      http_request :post_form, 'sendMessage', chat_id: chat_id, text: text, reply_to_message_id: reply_to
    end
  
    def send_photo chat_id, photo, *, caption: nil, reply_to: nil
      http_request :post_multipart, 'sendPhoto', chat_id: chat_id.to_s, photo: photo, caption: caption, reply_to_message_id: reply_to&.to_s
    end
  
    def send_file chat_id, file, *, caption: nil, reply_to: nil
      http_request :post_multipart, 'sendDocument', chat_id: chat_id.to_s, document: file, caption: caption, reply_to_message_id: reply_to&.to_s
    end
  
    private
    def http_request http_method, tg_method, *args, **kwargs
      uri = URI"https://api.telegram.org/bot#{@token}/#{tg_method}"
      if http_method == :post_multipart
        req = Net::HTTP::Post.new uri
        req.set_form kwargs.compact.transform_keys(&:to_s)
        req['Content-Type'] = 'multipart/form-data'
        JSON.parse Net::HTTP.start(req.uri.host, req.uri.port, use_ssl: true) { |http| http.request req }.read_body
      else
        JSON.parse Net::HTTP.send(http_method, uri, *args, **kwargs).read_body
      end
    end
  end
end
