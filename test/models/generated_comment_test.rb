require "test_helper"

class GeneratedCommentTest < ActiveSupport::TestCase
  test "comments parses stored JSON" do
    gc = GeneratedComment.new(comments_json: '[{"username":"x","body":"hi"}]')
    assert_equal [ { "username" => "x", "body" => "hi" } ], gc.comments
  end

  test "comments returns empty array when nil" do
    gc = GeneratedComment.new(comments_json: nil)
    assert_equal [], gc.comments
  end

  test "stale? returns false when hash matches" do
    gc = GeneratedComment.new(content_hash: "abc123")
    assert_not gc.stale?("abc123")
  end

  test "stale? returns true when hash differs" do
    gc = GeneratedComment.new(content_hash: "abc123")
    assert gc.stale?("different")
  end

  test "for_file returns matching record" do
    GeneratedComment.create!(file_id: "f1", year: 2008, comments_json: "[]", content_hash: "h1")
    assert_not_nil GeneratedComment.for_file("f1")
  end

  test "for_file returns nil for unknown file" do
    assert_nil GeneratedComment.for_file("nonexistent")
  end

  test "validates presence of file_id" do
    gc = GeneratedComment.new(year: 2008, comments_json: "[]", content_hash: "h")
    assert_not gc.valid?
    assert_includes gc.errors[:file_id], "can't be blank"
  end

  test "validates uniqueness of file_id" do
    GeneratedComment.create!(file_id: "f1", year: 2008, comments_json: "[]", content_hash: "h1")
    dup = GeneratedComment.new(file_id: "f1", year: 2008, comments_json: "[]", content_hash: "h2")
    assert_not dup.valid?
    assert_includes dup.errors[:file_id], "has already been taken"
  end
end
