require "test_helper"

class EntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @entry = fake_entry(year: 2008, month: 11, day: 14)
  end

  test "GET /:year/:slug returns 200 for a valid entry" do
    svc = fake_drive_service(by_slug: @entry, html: "<p>hello</p>")
    GoogleDriveService.stub(:new, svc) do
      get entry_url(2008, @entry.slug)
      assert_response :success
    end
  end

  test "GET /:year/:slug returns 404 for unknown slug" do
    svc = fake_drive_service(by_slug: nil)
    GoogleDriveService.stub(:new, svc) do
      get entry_url(2008, "nonexistent-slug")
      assert_response :not_found
    end
  end

  test "GET /:year/:slug skips comment generation without ANTHROPIC_API_KEY" do
    svc = fake_drive_service(by_slug: @entry, html: "<p>hello</p>")
    GoogleDriveService.stub(:new, svc) do
      with_env("ANTHROPIC_API_KEY" => nil) do
        CommentGeneratorService.stub(:new, -> { raise "should not be called" }) do
          get entry_url(2008, @entry.slug)
          assert_response :success
        end
      end
    end
  end

  test "GET /:year/:slug generates comments with ANTHROPIC_API_KEY present" do
    svc = fake_drive_service(by_slug: @entry, html: "<p>hello</p>")
    fake_comments = [ { "username" => "xXemo14Xx", "body" => "omg so true!!" } ]
    fake_comment_svc = Object.new
    fake_comment_svc.define_singleton_method(:comments_for) { |**| fake_comments }

    GoogleDriveService.stub(:new, svc) do
      CommentGeneratorService.stub(:new, fake_comment_svc) do
        with_env("ANTHROPIC_API_KEY" => "sk-test") do
          get entry_url(2008, @entry.slug)
          assert_response :success
        end
      end
    end
  end

  test "GET /:year/:slug/audio returns 404 when no matching audio file exists" do
    svc = fake_drive_service(by_slug: @entry, html: "<p>hello</p>", audio: nil)
    GoogleDriveService.stub(:new, svc) do
      get entry_audio_url(2008, @entry.slug)
      assert_response :not_found
    end
  end

  test "GET /:year/:slug/audio streams audio bytes with the file's mime type when present" do
    audio_file = OpenStruct.new(id: "fake-audio-id", mime_type: "audio/mpeg")
    svc = fake_drive_service(by_slug: @entry, html: "<p>hello</p>", audio: audio_file)
    GoogleDriveService.stub(:new, svc) do
      get entry_audio_url(2008, @entry.slug)
      assert_response :success
      assert_equal "audio/mpeg", @response.media_type
      assert_equal "fake audio bytes", @response.body
    end
  end

  test "GET /:year/:slug renders no audio player markup when no audio file exists" do
    svc = fake_drive_service(by_slug: @entry, html: "<p>hello</p>", audio: nil)
    GoogleDriveService.stub(:new, svc) do
      get entry_url(2008, @entry.slug)
      assert_response :success
      assert_select ".audio-player", count: 0
    end
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
