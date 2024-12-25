require "slack_bot/utils"

class SlackResponseJob < ApplicationJob
  DEFAULT_REACTION_SYMBOL = "hourglass_flowing_sand".freeze
  REACTION_SYMBOL = ENV.fetch("SLACK_REACTION_SYMBOL", DEFAULT_REACTION_SYMBOL)
  ERROR_REACTION_SYMBOL = "bangbang".freeze

  private def start_response(message, name=REACTION_SYMBOL)
    client = Slack::Web::Client.new
    client.reactions_add(channel: message.conversation.slack_id, timestamp: message.slack_ts, name:)
  rescue
    nil
  end

  private def finish_response(message, name=REACTION_SYMBOL)
    client = Slack::Web::Client.new
    client.reactions_remove(channel: message.conversation.slack_id, timestamp: message.slack_ts, name:)
  rescue
    nil
  end

  private def error_response(message, name=ERROR_REACTION_SYMBOL)
    client = Slack::Web::Client.new
    client.reactions_add(channel: message.conversation.slack_id, timestamp: message.slack_ts, name:)
  rescue
    nil
  end

  private def rewrite_markdown_link(s)
    s.gsub(/\[(.+?)\]\((.+?)\)/) { "<#{$2}|#{$1}>" }
  end
end
