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

  test "POST /admin/refresh_comments with correct token returns 200 and stats" do
    fake_service = Object.new
    fake_service.define_singleton_method(:call) { { entries_processed: 2, commenters: 3 } }

    with_env("ANTHROPIC_API_KEY" => "sk-test") do
      CommentsRefreshService.stub(:new, -> { fake_service }) do
        post admin_refresh_comments_url, headers: { "X-Admin-Token" => VALID_TOKEN }
      end
    end

    assert_response :success
    assert_equal({ "entries_processed" => 2, "commenters" => 3 }, response.parsed_body)
  end

  test "POST /admin/refresh_comments with wrong token returns 401" do
    post admin_refresh_comments_url, headers: { "X-Admin-Token" => "wrong-token" }
    assert_response :unauthorized
  end

  test "POST /admin/refresh_comments returns 422 when ANTHROPIC_API_KEY is not configured" do
    with_env("ANTHROPIC_API_KEY" => nil) do
      post admin_refresh_comments_url, headers: { "X-Admin-Token" => VALID_TOKEN }
    end

    assert_response :unprocessable_content
  end

  private

  def with_env(vars)
    old = vars.to_h { |k, _| [ k, ENV[k.to_s] ] }
    vars.each { |k, v| v.nil? ? ENV.delete(k.to_s) : ENV[k.to_s] = v }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k.to_s) : ENV[k.to_s] = v }
  end
end
