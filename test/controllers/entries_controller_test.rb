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

  test "GET /:year/:slug still renders, without comments, when the Anthropic API errors" do
    svc = fake_drive_service(by_slug: @entry, html: "<p>hello</p>")
    messages = Object.new
    messages.define_singleton_method(:create) { |**| raise Class.new(Anthropic::Errors::Error), "overloaded" }
    client = Object.new
    client.define_singleton_method(:messages) { messages }

    GoogleDriveService.stub(:new, svc) do
      Anthropic::Client.stub(:new, client) do
        with_env("ANTHROPIC_API_KEY" => "sk-test") do
          get entry_url(2008, @entry.slug)
          assert_response :success
          assert_select ".comments-section", count: 0
        end
      end
    end
  end

  test "a non-year path segment doesn't route to an entry (or touch Drive)" do
    GoogleDriveService.stub(:new, -> { raise "should not be called" }) do
      get "/notayear/some-slug"
      assert_response :not_found
    end
  end

  test "GET /:year/:slug/audio serves the whole file with 200 when no Range is requested" do
    get_audio(bytes: "0123456789")
    assert_response :success
    assert_equal "0123456789", @response.body
    assert_equal "bytes", @response.headers["Accept-Ranges"]
  end

  test "GET /:year/:slug/audio serves 206 with just the requested bytes for a Range request" do
    get_audio(bytes: "0123456789", range: "bytes=2-5")
    assert_response :partial_content
    assert_equal "2345", @response.body
    assert_equal "bytes 2-5/10", @response.headers["Content-Range"]
    assert_equal "4", @response.headers["Content-Length"]
  end

  test "GET /:year/:slug/audio handles Safari's opening bytes=0-1 probe" do
    get_audio(bytes: "0123456789", range: "bytes=0-1")
    assert_response :partial_content
    assert_equal "01", @response.body
    assert_equal "bytes 0-1/10", @response.headers["Content-Range"]
  end

  test "GET /:year/:slug/audio supports open-ended and suffix ranges" do
    get_audio(bytes: "0123456789", range: "bytes=7-")
    assert_equal "789", @response.body
    assert_equal "bytes 7-9/10", @response.headers["Content-Range"]

    get_audio(bytes: "0123456789", range: "bytes=-3")
    assert_equal "789", @response.body
    assert_equal "bytes 7-9/10", @response.headers["Content-Range"]
  end

  test "GET /:year/:slug/audio clamps a range that runs past the end of the file" do
    get_audio(bytes: "0123456789", range: "bytes=8-100")
    assert_response :partial_content
    assert_equal "89", @response.body
    assert_equal "bytes 8-9/10", @response.headers["Content-Range"]
  end

  test "GET /:year/:slug/audio returns 416 for a range starting past the end of the file" do
    get_audio(bytes: "0123456789", range: "bytes=10-20")
    assert_response :range_not_satisfiable
    assert_equal "bytes */10", @response.headers["Content-Range"]
  end

  test "GET /:year/:slug/audio ignores a Range it can't honor and serves the whole file" do
    get_audio(bytes: "0123456789", range: "bytes=0-1,4-5")
    assert_response :success
    assert_equal "0123456789", @response.body

    get_audio(bytes: "0123456789", range: "bytes=2-5", size: nil)
    assert_response :success
    assert_equal "0123456789", @response.body
  end

  private

  def get_audio(bytes:, range: nil, size: bytes.bytesize)
    audio_file = OpenStruct.new(id: "fake-audio-id", mime_type: "audio/mpeg", size: size)
    svc = fake_drive_service(by_slug: @entry, audio: audio_file, audio_bytes: bytes)
    GoogleDriveService.stub(:new, svc) do
      get entry_audio_url(2008, @entry.slug), headers: range ? { "Range" => range } : {}
    end
  end

  def with_env(vars)
    old = vars.to_h { |k, _| [ k, ENV[k.to_s] ] }
    vars.each { |k, v| v.nil? ? ENV.delete(k.to_s) : ENV[k.to_s] = v }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k.to_s) : ENV[k.to_s] = v }
  end
end
