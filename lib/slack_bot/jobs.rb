require "openai_config.rb"
require "sidekiq_config.rb"
require "slack_config.rb"

require "jobs/chat_gpt_job.rb"
require "jobs/translate_job.rb"
