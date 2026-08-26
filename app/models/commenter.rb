class Commenter < ApplicationRecord
  validates :username, presence: true, uniqueness: true
end
