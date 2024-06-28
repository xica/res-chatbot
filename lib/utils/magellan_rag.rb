require "json"

module Utils
  module MagellanRAG
    DEFAULT_ENDPOINT = "http://localhost:8000"

    module_function def endpoint
      ENV.fetch("MAGELLAN_RAG_ENDPOINT", DEFAULT_ENDPOINT)
    end

    module_function def generate_answer(query)
      uri = File.join(endpoint, "generate_answer")
      response = Faraday.get(uri, {"query": query})
      JSON.load(response.body)
    end

    module_function def retrieve_documents(query)
      uri = File.join(endpoint, "retrieve_documents")
      response = Faraday.get(uri, {"query": query})
      JSON.load(response.body)
    end

    Case = Struct.new(:description, :file_name, :file_url, :matching_part)

    module_function def parse_answer(text)
      text.split(/\n\n/).map do |kase|
        parse_case(kase)
      end
    end

    module_function def parse_case(kase_text)
      kase = Case.new("", nil, nil, "")
      lines = kase_text.lines
      i = 0
      while i < lines.length
        break if lines[i].start_with?("- ")
        kase.description << lines[i]
        i += 1
      end
      while i < lines.length
        case lines[i]
        when /\A-\s*ファイル名:\s*/
          kase.file_name = Regexp.last_match.post_match.strip
        when /\A-\s*ファイルの?URL:\s*/
          matched = Regexp.last_match.post_match
          if matched =~ /\[.+\]\((.+)\)/
            kase.file_url = Regexp.last_match[1].strip
          else
            kase.file_url = matched.strip
          end
        when /\A-\s*該当部分:\s*/
          kase.matching_part = Regexp.last_match.post_match.strip
        end
        i += 1
      end
      kase.description.strip!
      kase
    end
  end
end
