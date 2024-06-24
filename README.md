# Simple ChatGPT Slack Bot

## Environment variables

* `ADMIN_USER` and `ADMIN_PASSWORD` is used for Basic Auth of Sidekiq's management console
* `ALLOW_CHANNEL_IDS` for specifying channel IDs where users can communicate with the chatbot
* `MAGELLAN_RAG_CHANNEL_IDS` for specifying channel IDs where users can query about MAGELLAN's past reports
* `MAGELLAN_RAG_ENDPOINT` for specifying the endpoint of the Magellan RAG API in the `schema://host:port` format
* `SLACK_BOT_TOKEN` is for the Slack Bot's access token
* `SLACK_SIGNING_SECRET` is for signing secret to check the request coming from Slack
* `OPENAI_ACCESS_TOKEN` is for OpenAI API Access Token
* `OPENAI_ORGANIZATION_ID` is for OpenAI API Organization ID (optional)
* `REDIS_URL` is for URL of Redis server

## Required scopes

* `app_mentions:read`
* `channels:read`
* `chat:write`
* `reactions:write`
* `users:read`
* `users:read:email`

## Model Name

When you use this with Azure OpenAI Service, you need to include `gpt-35-turbo`
section in the model like `abc-gpt-35-turbo-001`. Chatbot detects the model
version and its unit price by checking the existence of `gpt-35-turbo`.

## License

MIT License

## Author

Kenta Murata
