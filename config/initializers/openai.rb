require "openai"
require "openai_extension"

OpenAI.configure do |config|
  config.access_token = ENV.fetch("OPENAI_ACCESS_TOKEN", "OPENAI_TOKEN_IS_NOT_GIVEN")

  org_id = ENV.fetch("OPENAI_ORGANIZATION_ID", nil)
  config.organization_id = org_id if org_id

  config.request_timeout = ENV.fetch("OPENAI_REQUEST_TIMEOUT", 300).to_i

  config.api_type    = ENV.fetch("OPENAI_API_TYPE", :openai).to_sym
  config.uri_base    = ENV.fetch("OPENAI_URI_BASE", OpenAI::Configuration::DEFAULT_URI_BASE)
  config.api_version = ENV.fetch("OPENAI_API_VERSION", OpenAI::Configuration::DEFAULT_API_VERSION)
end
