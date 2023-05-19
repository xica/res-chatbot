class ChangeConversationsThreadAllowedDefault < ActiveRecord::Migration[7.0]
  def up
    change_column_default(:conversations, :thread_allowed, true)
  end

  def down
    change_column_default(:conversations, :thread_allowed, false)
  end
end
