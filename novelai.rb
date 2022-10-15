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
  float :strength, min: 0, max: 1
  float :noise, min: 0, max: 1
  string :negative, default: ""
  enum :negative_preset, values: [ 0, 1, 2 ]
  enum :sampler, values: %w{k_euler_ancestral k_euler k_lms plms ddim}

  def to_s
    JSON.dump self.class.fields
      .keys.reduce({}) { |o, k|
        o[k] = send k
        o
      }
  end

  def to_h
    {
      height: @height,
      width: @width,
      n_samples: @samples,
      steps: @steps,
      scale: @scale,
      seed: @seed,
      uc: @negative,
      ucPreset: @negative_preset,
      sampler: @sampler,
    }.compact
  end
end

class NovelAI
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
    @model = m if MODEL.includes? m
  end

  def price
    r = http_request(
      :post,
      "/ai/generate-image/request-price",
      body: {
        request: { input: [@prompt], model: @model, parameters: @config.to_h },
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
      r.error!
    end
  end

  def generate
    r = http_request :post, "/ai/generate-image", body: { input: @prompt, model: @model, parameters: @config.to_h }, credential: true
    if r.is_a? Net::HTTPSuccess and r.content_type == 'text/event-stream'
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
      r.error!
    end
  end

  private
  def http_request http_method, endpoint, params: {}, body: {}, headers: {}, credential: false
    uri = URI"https://api.novelai.net"
    uri.path = endpoint
    uri.query = URI.encode_www_form params
    h = headers.merge({"Content-Type": "application/json"}) 
    h = h.merge({"Authorization": "Bearer #{@token}"}) if credential
    send_http_request http_method, uri, JSON.dump(body), h
  end
end

