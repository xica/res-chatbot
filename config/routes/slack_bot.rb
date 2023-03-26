require "slack_bot/app"

mount SlackBot::Application, at: "/slack"
