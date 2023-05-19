class PermitAllChannelsToUseThread < ActiveRecord::Migration[7.0]
  def up
    Conversation.transaction do
      Conversation.find_each do |ch|
        ch.update!(thread_allowed: true)
      end
    end
  end

  def down
    Conversation.transaction do
      Conversation.find_each do |ch|
        ch.update!(thread_allowed: false)
      end
    end
  end
end
