# Simple ChatGPT Slack Bot

## Environment variables

* `ADMIN_USER` and `ADMIN_PASSWORD` is used for Basic Auth of Sidekiq's management console
* `ALLOW_CHANNEL_IDS` for specifying channel IDs where users can communicate with the chatbot
* `SLACK_BOT_TOKEN` is for the Slack Bot's access token
* `SLACK_SIGNING_SECRET` is for signing secret to check the request coming from Slack
* `OPENAI_ACCESS_TOKEN` is for OpenAI API Access Token
* `OPENAI_ORGANIZATION_ID` is for OpenAI API Organization ID (optional)
* `REDIS_URL` is for URL of Redis server

## License

MIT License

## Author

Kenta Murata
