module OpenAIExtension
  module ConfigurationExt
    attr_reader :api_type

    def api_type=(value)
      case value
      when :openai, "openai", :azure, "azure"
        @api_type = value
      else
        raise ArgumentError, "Invalid API Type: #{value}"
      end
    end

    def initialize
      super
      @api_type = :openai
    end
  end
  OpenAI::Configuration.prepend ConfigurationExt

  module HTTPExt
    def uri(path:)
      case OpenAI.configuration.api_type
      when :openai, "openai"
        super
      when :azure, "azure"
        OpenAI.configuration.uri_base + path + "?api_version=#{OpenAI.configuration.api_version}"
      end
    end
  end
  OpenAI::HTTP.prepend HTTPExt
end
