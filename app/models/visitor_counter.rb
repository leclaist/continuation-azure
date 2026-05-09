class VisitorCounter < ApplicationRecord
  def self.increment!
    counter = first_or_create!(count: 0)
    counter.increment!(:count)
    counter.count
  end

  def self.current
    first&.count || 0
  end
end
