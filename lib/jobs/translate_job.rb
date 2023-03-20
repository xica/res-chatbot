require_relative "chat_gpt_job"

class TranslateJob < ChatGPTJob
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

    response = Utils.chat_completion(query)
    response_content = response.dig("choices", 0, "message", "content")

    source_language, translation = extract_answer(response_content)
    target_language = TARGET_LANGUAGES[lang]
    answer = <<~END_RESPONSE
      <@#{user}>
      Original (#{source_language}):
      #{quote(text)}

      #{target_language} Translation:
      #{quote(*translation)}
    END_RESPONSE

    Utils.post_message(channel: channel, text: answer)
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
