class SlackRagJob < SlackResponseJob
  private def format_simple_rag_response(answer, user:)
    answer = rewrite_markdown_link(answer)
    text = "<@#{user.slack_id}> 回答は次のとおりです。\n\n#{answer}"
    response = SlackBot.format_chat_gpt_response(text)
    feedback_block = response[:blocks].pop
    response[:blocks] << { "type": "divider" }
    response[:blocks] << feedback_block
    response
  end

  private def format_rag_response(answer, user:)
    answer_blocks = format_answer_blocks(answer, user)
    text = "#{answer_blocks[0][:text][:text]}\n\n#{answer}"
    response = SlackBot.format_chat_gpt_response(text)
    response[:blocks][0,1] = answer_blocks
    response
  end

  private def format_answer_blocks(answer, user)
    kases = Utils::MagellanRAG.parse_answer(answer)
    blocks = [
      {
        "type": "section",
        "text": {
          "type": "mrkdwn",
          "text": "<@#{user.slack_id}> 次の#{kases.length}件の文書が質問に該当する可能性があります。"
        }
      }
    ]
    kases.each do |kase|
      blocks << format_kase(kase)
      blocks << {"type": "divider"}
    end
    blocks
  end

  private def format_kase(kase)
    {
      "type": "rich_text",
      "elements": [
        {
          "type": "rich_text_section",
          "elements": [
            "type": "text",
            "text": kase.description
          ]
        },
        {
          "type": "rich_text_list",
          "style": "bullet",
          "indent": 0,
          "elements": [
            {
              "type": "rich_text_section",
              "elements": [
                {
                  "type": "text",
                  "text": "ファイル: "
                },
                {
                  "type": "link",
                  "url": kase.file_url,
                  "text": kase.file_name
                }
              ]
            },
            {
              "type": "rich_text_section",
              "elements": [
                {
                  "type": "text",
                  "text": "該当部分: #{kase.matching_part}"
                }
              ]
            }
          ]
        }
      ],
    }
  end
end
