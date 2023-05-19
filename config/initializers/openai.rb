require "openai"

OpenAI.configure do |config|
  config.access_token = ENV.fetch("OPENAI_ACCESS_TOKEN", "OPENAI_TOKEN_IS_NOT_GIVEN")

  org_id = ENV.fetch("OPENAI_ORGANIZATION_ID", nil)
  config.organization_id = org_id if org_id

  config.request_timeout = ENV.fetch("OPENAI_REQUEST_TIMEOUT", 300).to_i
end
