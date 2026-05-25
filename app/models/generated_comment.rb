class GeneratedComment < ApplicationRecord
  validates :file_id, presence: true, uniqueness: true

  def comments
    JSON.parse(comments_json || "[]")
  end

  def self.for_file(file_id)
    find_by(file_id: file_id)
  end

  def stale?(current_hash)
    content_hash != current_hash
  end
end
