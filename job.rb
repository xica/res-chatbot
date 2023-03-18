require "sidekiq"
require "slack-ruby-client"

require_relative "chat-gpt"

redis_config = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379") }

Sidekiq.configure_server do |config|
  config.redis = redis_config
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
end

Slack.configure do |config|
  config.token = ENV["SLACK_BOT_TOKEN"]
end

class ChatGPTJob
  include Sidekiq::Job

  def perform(params)
    channel = params["channel"]
    user = params["user"]
    message = params["message"]

    answer = ChatGPT.chat_completion(message)

    response = "<@#{user}> #{answer}"

    slack_client = Slack::Web::Client.new
    slack_client.chat_postMessage(channel: channel, text: response)
  end
end

class TranslateJob
  include Sidekiq::Job

  TARGET_LANGUAGES = {
    "en" => "English",
    "ja" => "Japanese"
  }.freeze

  def self.lang_available?(lang)
    TARGET_LANGUAGES.key?(lang)
  end

  def self.format_query(lang, text)
    target_language = TARGET_LANGUAGES[lang]
    return nil unless target_language

    <<~END_QUERY
      Please detect the language of a given sentences and translate it to #{target_language}.
      And put the original language name to {ORIGINAL_LANGUAGE} and the translated sentence to {TRANSLATION} in the following format.

      [LANG]
      {ORIGINAL_LANGUAGE}

      [Translation]
      {TRANSLATION}

      The given sentences is below:

      #{text}
    END_QUERY
  end

  def perform(params)
    channel, user, text, lang = params.values_at("channel", "user", "text", "lang")

    query = TranslateJob.format_query(lang, text)
    return unless query

    answer = ChatGPT.chat_completion(query)

    source_language, translation = extract_answer(answer)
    target_language = TARGET_LANGUAGES[lang]
    response = <<~END_RESPONSE
      <@#{user}>
      Original (#{source_language}):
      #{quote(text)}

      #{target_language} Translation:
      #{quote(*translation)}
    END_RESPONSE

    slack_client = Slack::Web::Client.new
    slack_client.chat_postMessage(channel: channel, text: response)
  end

  private

  def extract_answer(answer)
    mode = nil
    source_language = nil
    translation = []
    answer.each_line(chomp: true) do |line|
      if /\A\[(LANG|Translation)\]\z/.match(line.strip)
        break unless mode.nil?
        mode = $1
      elsif mode == "LANG"
        source_language = line
        mode = nil
      elsif mode == "Translation"
        translation << line
      end
    end
    return source_language, translation
  end

  def quote(*lines)
    lines.flat_map { |text|
      text.each_line.map {|l| "> #{l.chomp}" }
    }.join("\n")
  end
end
