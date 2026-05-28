require "test_helper"

class Admin::MaintenanceControllerTest < ActionDispatch::IntegrationTest
  VALID_TOKEN = "test-admin-token-abc123"

  setup do
    @original_token = ENV["ADMIN_TOKEN"]
    ENV["ADMIN_TOKEN"] = VALID_TOKEN
    GeneratedComment.delete_all
  end

  teardown do
    ENV["ADMIN_TOKEN"] = @original_token
  end

  test "POST /admin/clear_comments with correct token returns 200 and deleted count" do
    GeneratedComment.create!(file_id: "f1", year: 2008, comments_json: "[]", content_hash: "abc")
    GeneratedComment.create!(file_id: "f2", year: 2008, comments_json: "[]", content_hash: "def")

    post admin_clear_comments_url, headers: { "X-Admin-Token" => VALID_TOKEN }

    assert_response :success
    assert_equal({ "deleted" => 2 }, response.parsed_body)
    assert_equal 0, GeneratedComment.count
  end

  test "POST /admin/clear_comments with wrong token returns 401" do
    post admin_clear_comments_url, headers: { "X-Admin-Token" => "wrong-token" }
    assert_response :unauthorized
  end

  test "POST /admin/clear_comments with no token returns 401" do
    post admin_clear_comments_url
    assert_response :unauthorized
  end

  test "POST /admin/clear_comments returns 401 when ADMIN_TOKEN is not configured" do
    ENV.delete("ADMIN_TOKEN")
    post admin_clear_comments_url, headers: { "X-Admin-Token" => VALID_TOKEN }
    assert_response :unauthorized
  end
end
