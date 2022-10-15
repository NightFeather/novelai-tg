
module Schema
  module Validators
    class Base
      def initialize options
        @options = options.transform_keys(&:to_s)
      end
      def initial
        return @options['default'] if @options.key? 'default'
      end
      def sanitize value
        @options['sanitizer']&.call(value) or value
      end
      def validate value
        return true
      end
    end

    class Boolean < Base
      def sanitize v
        if v.is_a? String
          return true if v =~ /^(t(rue)?|y(es)?|1)$/i
          return false if v =~ /^(f(alse)?|no?|0)$/i
        end
        super v
      end
      def validate value
        return [true, false].include?(value)
      end
    end

    class Numeric < Base
      def initial
        return @options['default'] if @options.key? 'default'
        @options['min']
      end
      def validate value
        return false unless value.is_a? ::Numeric
        return false if @options['min'] and value < @options['min']
        return false if @options['max'] and value > @options['max']
        return true
      end
    end

    class Integer < Numeric
      def initial
        return @options['default'] if @options.key? 'default'
        @options['min'] or @options['range']&.first
      end
      def validate value
        super unless super
        return false unless value.is_a? ::Integer
        return false if @options['range'] and not @options['range'].include? value
        return true
      end
      def sanitize value
        value.respond_to? :to_i and value.to_i or super
      end
    end

    class Float < Numeric
      def sanitize value
        value.respond_to? :to_f and value.to_f or super
      end
    end

    class String < Base
      def initial
        return @options['default'] if @options.key? 'default'
        ""
      end
      def validate value
        return false if @options['pattern'] and value !~ @options['pattern']
        return true
      end
      def sanitize value
        value.respond_to? :to_s and value.to_s or super
      end
    end

    class Enum < Base
      def initial
        super or @options['values']&.first
      end
      def validate value
        return @options['values'].include? value
      end
    end
  end

  module Mixin
    def self.included cls
      cls.extend ClassMethods
    end

    def initialize
      self.class.fields.each_pair do |f, v|
        instance_variable_set "@#{f}", v.initial
      end
    end

    module ClassMethods
      def fields
        @fields ||= {}
      end

      def field t, name, *, **opts
        fields[name] = Validators.const_get(t.to_s.capitalize).new opts
        define_method(name) do
          instance_variable_get "@#{name}"
        end
        define_method("#{name}=") do |v|
          _v = self.class.fields[name].sanitize v
          instance_variable_set "@#{name}", _v if self.class.fields[name].validate _v
        end
      end

      %w{integer float string enum boolean}.each do |t|
        define_method(t) do |*args, **kwargs|
          field t, *args, **kwargs
        end
      end
    end
  end
end
