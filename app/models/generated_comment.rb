class GeneratedComment < ApplicationRecord
  validates :file_id, presence: true, uniqueness: true

  def comments
    JSON.parse(comments_json || "[]")
  end

  def self.for_file(file_id)
    find_by(file_id: file_id)
  end
end
