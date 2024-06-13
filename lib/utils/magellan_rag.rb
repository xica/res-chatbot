require "json"

module Utils
  module MagellanRAG
    DEFAULT_ENDPOINT = "http://localhost:8000"

    module_function def endpoint
      ENV.fetch("REPORT_RAG_API", DEFAULT_ENDPOINT)
    end

    module_function def generate_answer(query)
      uri = File.join(endpoint, "generate_answer")
      response = Faraday.get(uri, {"query": query})
      JSON.load(response.body)
    end
  end
end
