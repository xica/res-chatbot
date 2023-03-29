require "openssl"

module SlackBot
  PROMPT_PRICE_USD = {
    "gpt-3.5-turbo-0301" => 0.002r / 1000,
    "gpt-4-0314" => 0.03r / 1000,
    "gpt-4-32k-0314" => 0.06r / 1000,

    "gpt-3.5-turbo" => "gpt-3.5-turbo-0301",
    "gpt-4" => "gpt-4-0314",
    "gpt-4-32k" => "gpt-4-32k-0314",
  }.freeze

  COMPLETION_PRICE_USD = {
    "gpt-3.5-turbo-0301" => 0.002r / 1000,
    "gpt-4-0314" => 0.06r / 1000,
    "gpt-4-32k-0314" => 0.12r / 1000,

    "gpt-3.5-turbo" => "gpt-3.5-turbo-0301",
    "gpt-4" => "gpt-4-0314",
    "gpt-4-32k" => "gpt-4-32k-0314",
  }.freeze

  module_function def prompt_unit_price(model)
    unit_price = PROMPT_PRICE_USD[model]
    case unit_price
    when String
      PROMPT_PRICE_USD[unit_price]
    else
      unit_price
    end
  end

  module_function def completion_unit_price(model)
    unit_price = COMPLETION_PRICE_USD[model]
    case unit_price
    when String
      COMPLETION_PRICE_USD[unit_price]
    else
      unit_price
    end
  end

  USDJPY = 140.0r

  module_function def format_chat_gpt_response(text, prompt_tokens: nil, completion_tokens: nil, model: nil)
    response = {
      text: text,
      blocks: [
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: text
          }
        }
      ]
    }

    if prompt_tokens && completion_tokens && model
      prompt_amount_jpy = prompt_tokens * prompt_unit_price(model) * USDJPY
      completion_amount_jpy = completion_tokens * completion_unit_price(model) * USDJPY

      response[:blocks] << {
        type: "context",
        elements: [
          {
            "type": "mrkdwn",
            "text": "API Usage: total %d tokens \u{2248} \u{a5}%0.2f (prompt + completion = %d + %d tokens \u{2248} \u{a5}%0.2f + \u{a5}%0.2f)" % [
              prompt_tokens + completion_tokens,
              (prompt_amount_jpy + completion_amount_jpy).round(2),
              prompt_tokens,
              completion_tokens,
              prompt_amount_jpy.round(2),
              completion_amount_jpy.round(2)
            ]
          }
        ]
      }
    end

    response[:blocks] << {
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

    response
  end
end
