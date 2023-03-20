module SlackBot
  module_function def format_chat_gpt_response(text)
    {
      text: text,
      blocks: [
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: text
          }
        },
        {
          type: "actions",
          elements: [
            {
              type: "button",
              text: {
                type: "plain_text",
                emoji: true,
                text: "Good"
              },
              style: "primary",
              value: "good"
            },
            {
              type: "button",
              text: {
                type: "plain_text",
                emoji: true,
                text: "Bad"
              },
              style: "danger",
              value: "bad"
            }
          ]
        }
      ]
    }
  end
end
