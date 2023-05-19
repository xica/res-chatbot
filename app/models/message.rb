class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :user

  has_one :query

  def thread_messages
    Message.where(slack_thread_ts: self.slack_thread_ts).order(slack_ts: :asc).to_a
  end

  def previous_message
    messages = thread_messages
    return nil if messages.length == 1

    messages.each_cons(2) do |a, b|
      return a if b.slack_ts == self.slack_ts
    end

    nil
  end
end
