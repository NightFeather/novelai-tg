require 'net/https'
require 'json'
require 'base64'
require_relative "./http_request.rb"
require_relative "./schema.rb"

class Cache
  def initialize
    @internal = {}
    @valid = {}
  end

  def [] key
    @internal[key]
  end

  def []= key, value
    @internal[key] = value
    @valid[key] = true
  end

  def check key
    @valid[key]
  end

  def expire key
    @valid[key] = false
  end
end

class ModelConfig
  include Schema::Mixin
  integer :height, range: 512..1024, default: 512
  integer :width, range: 512..1024, default: 768
  integer :samples, range: 1..4, default: 1
  integer :steps, range: 1..50, default: 28
  integer :scale, range: 2..100, default: 14
  integer :seed
  boolean :qualityToggle, default: true
  float :strength, min: 0, max: 1, default: nil
  float :noise, min: 0, max: 1, default: nil
  string :negative, default: ""
  enum :negative_preset, values: [ 0, 1, 2 ]
  enum :sampler, values: %w{k_euler_ancestral k_euler k_lms plms ddim}

  def to_s
    JSON.pretty_generate to_h
  end

  def to_json
    JSON.dump to_h
  end

  def from_hash h
    h.each_pair do |k,v|
      if fields.key? k.to_sym
        send "#{k}=", v
      end
    end
  end

  def to_request
    {
      height: @height,
      width: @width,
      n_samples: @samples,
      steps: @steps,
      scale: @scale,
      seed: @seed,
      qualityToggle: @qualityToggle,
      uc: @negative,
      ucPreset: @negative_preset,
      sampler: @sampler,
    }.compact
  end
end

class NovelAI
  Exception = Class.new Exception
  MODELS = %w{stable-diffusion nai-diffusion safe-diffusion nai-diffusion-furry}
  TIERS = %w{TABLET XXX OPUS}

  attr_accessor :prompt, :image
  attr_reader :model, :config

  def initialize token
    @token = token
    @cache = Cache.new
    @model = "nai-diffusion"
    @prompt = ""
    @image = nil
    @config = ModelConfig.new
  end

  def model= m
    @model = m if MODELS.include? m
  end

  def price
    r = http_request(
      :post,
      URI("https://backend-production-svc.novelai.net/ai/generate-image/request-price"),
      body: {
        request: { input: [@prompt], model: @model, parameters: @config.to_request },
        tier: 'OPUS'
      }
    )
    if r.is_a? Net::HTTPSuccess
      o = JSON.parse r.read_body
      if o['requestEligibleForUnlimitedGeneration']
        return 0
      else
        return o['costPerPrompt']*(o["numPrompts"] - o["freePrompts"])
      end
    else
      raise NovelAI::Exception.new "#{r.code} #{r.message.dump}"
    end
  end

  def generate
    r = http_request :post,
      URI("https://backend-production-svc.novelai.net/ai/generate-image"),
      body: { input: @prompt, model: @model, parameters: @config.to_request },
      credential: true
    if r.is_a? Net::HTTPSuccess
      if r.content_type == 'text/event-stream'
        r.body.split("\n").reduce([{}]) { |o, l|
          k,v = l.split(":", 2)
          if k.strip == 'id' and o.last.key? 'id' and o.last['id'] != v.strip.to_i
            o.append({ 'id' => v.strip.to_i })
          else
            o.last[k.strip] = v&.strip
          end
          o
        }
      else
        []
      end
    else
      raise NovelAI::Exception.new "Server error: #{r.code} #{r.message}"
    end
  end

  private
  def http_request http_method, endpoint, params: {}, body: {}, headers: {}, credential: false
    uri = endpoint
    unless endpoint.is_a? URI
      uri = URI"https://api.novelai.net"
      uri.path = endpoint
      uri.query = URI.encode_www_form params
    end
    h = headers.merge({"Content-Type": "application/json"}) 
    h = h.merge({"Authorization": "Bearer #{@token}"}) if credential
    send_http_request http_method, uri, JSON.dump(body), h
  rescue Net::ReadTimeout => e
    raise NovelAI::Exception.new "Server Timeout"
  end
end

