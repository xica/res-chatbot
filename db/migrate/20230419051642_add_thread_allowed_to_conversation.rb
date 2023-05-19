class AddThreadAllowedToConversation < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :thread_allowed, :boolean, null: false, default: false
  end
end
