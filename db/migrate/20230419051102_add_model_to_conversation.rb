class AddModelToConversation < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :model, :string, null: true
  end
end
