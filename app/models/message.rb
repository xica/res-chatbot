class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :user

  has_one :query
end
