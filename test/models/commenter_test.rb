require "test_helper"

class CommenterTest < ActiveSupport::TestCase
  test "validates presence of username" do
    commenter = Commenter.new(personality: "skeptical")
    assert_not commenter.valid?
    assert_includes commenter.errors[:username], "can't be blank"
  end

  test "validates uniqueness of username" do
    Commenter.create!(username: "xXdarkrose14Xx", personality: "dramatic")
    dup = Commenter.new(username: "xXdarkrose14Xx", personality: "different")
    assert_not dup.valid?
    assert_includes dup.errors[:username], "has already been taken"
  end
end
