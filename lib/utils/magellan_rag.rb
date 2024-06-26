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
  end
end
