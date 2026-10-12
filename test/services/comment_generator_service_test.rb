require "test_helper"

# CommentGeneratorService#generate calls the real Anthropic API, which we
# intentionally never do in tests (see CLAUDE.md) — it's expensive,
# non-deterministic, and slow. What we *can* test deterministically is that
# the service sends the model the right thing to be relevant about: these
# tests stub Anthropic::Client.new (same pattern as GoogleDriveService.stub
# elsewhere) and assert on the prompt it builds, not on any LLM output.
class CommentGeneratorServiceTest < ActiveSupport::TestCase
  test "prompt includes the entry's own content" do
    html = "<p>Drove out to the coast today and watched the sunset with Jamie.</p>"

    prompt = captured_prompt(content_html: html, file_id: "entry-content")

    assert_includes prompt, "Drove out to the coast today and watched the sunset with Jamie."
  end

  test "prompt uses the year-specific voice when one exists" do
    prompt = captured_prompt(year: 2008, file_id: "entry-2008")

    assert_includes prompt, "generating fake blog comments for a personal journal entry from 2008"
    assert_includes prompt, CommentGeneratorService::YEAR_VOICE[2008][:style]
  end

  test "prompt falls back to the default voice for a year with no specific voice" do
    prompt = captured_prompt(year: 2009, file_id: "entry-2009")

    assert_includes prompt, CommentGeneratorService::DEFAULT_VOICE[:style]
  end

  test "prompt includes the existing commenter roster so replies stay in character" do
    Commenter.create!(username: "xXdarkrose14Xx", personality: "dramatic, overshares", memory_summary: "still mad about the breakup")

    prompt = captured_prompt(file_id: "entry-roster")

    assert_includes prompt, "xXdarkrose14Xx"
    assert_includes prompt, "still mad about the breakup"
  end

  test "a cached entry whose content hasn't changed is served without calling the API" do
    html = "<p>same as before</p>"
    GeneratedComment.create!(file_id: "cached", year: 2008, content_hash: Digest::SHA256.hexdigest(html),
                             comments_json: [ { "username" => "old", "body" => "cached!" } ].to_json)

    comments, calls = run_comments_for(file_id: "cached", content_html: html)

    assert_equal 0, calls
    assert_equal "cached!", comments.first["body"]
  end

  test "an entry whose content changed is regenerated in place, not duplicated" do
    GeneratedComment.create!(file_id: "edited", year: 2008, content_hash: "stale-hash",
                             comments_json: [ { "username" => "old", "body" => "stale" } ].to_json)

    comments, calls = run_comments_for(file_id: "edited", content_html: "<p>new text</p>",
                                       reply: { comments: [ { username: "new", body: "fresh" } ], commenters: [] })

    assert_equal 1, calls
    assert_equal "fresh", comments.first["body"]
    assert_equal 1, GeneratedComment.where(file_id: "edited").count
    record = GeneratedComment.for_file("edited")
    assert_equal Digest::SHA256.hexdigest("<p>new text</p>"), record.content_hash
    assert_equal "fresh", record.comments.first["body"]
  end

  test "a new entry's comments are cached so the next visit doesn't call the API again" do
    reply = { comments: [ { username: "a", body: "b" } ], commenters: [] }
    _, first_calls = run_comments_for(file_id: "brand-new", reply: reply)
    _, second_calls = run_comments_for(file_id: "brand-new", reply: reply)

    assert_equal [ 1, 0 ], [ first_calls, second_calls ]
  end

  test "commenter memory updates but an established personality is kept" do
    Commenter.create!(username: "xXdarkrose14Xx", personality: "dramatic, overshares", memory_summary: "still mad about the breakup")

    run_comments_for(file_id: "memory", reply: {
      comments: [ { username: "xXdarkrose14Xx", body: "ok fine" } ],
      commenters: [
        { username: "xXdarkrose14Xx", personality: "suddenly calm and zen", memory: "finally over the breakup" },
        { username: "skaterdude42", personality: "chill, sarcastic", memory: "new here, already annoyed" }
      ]
    })

    rose = Commenter.find_by!(username: "xXdarkrose14Xx")
    assert_equal "dramatic, overshares", rose.personality
    assert_equal "finally over the breakup", rose.memory_summary

    skater = Commenter.find_by!(username: "skaterdude42")
    assert_equal "chill, sarcastic", skater.personality
    assert_equal "new here, already annoyed", skater.memory_summary
  end

  test "a reply wrapped in a ```json fence is still parsed" do
    comments, = run_comments_for(file_id: "fenced", reply_text: "```json\n{\"comments\":[{\"username\":\"a\",\"body\":\"b\"}]}\n```")

    assert_equal "b", comments.first["body"]
  end

  [
    [ "malformed JSON", "omg not json" ],
    [ "a JSON array instead of an object", "[1, 2, 3]" ],
    [ "an empty object", "{}" ]
  ].each do |label, reply_text|
    test "#{label} from the model yields no comments and caches nothing, so the next visit retries" do
      comments, = run_comments_for(file_id: "bad-#{label.parameterize}", reply_text: reply_text)

      assert_equal [], comments
      assert_nil GeneratedComment.for_file("bad-#{label.parameterize}")
    end
  end

  test "an Anthropic API error yields no comments instead of raising" do
    comments, = run_comments_for(file_id: "api-error", raise_error: Class.new(Anthropic::Errors::Error))

    assert_equal [], comments
    assert_nil GeneratedComment.for_file("api-error")
  end

  private

  # Stubs Anthropic::Client.new with a fake that replies with `reply` (or the
  # raw `reply_text`), runs comments_for, and returns [comments, api_calls].
  def run_comments_for(file_id:, year: 2008, content_html: "<p>hello</p>", reply: { comments: [], commenters: [] }, reply_text: nil, raise_error: nil)
    calls = 0
    text = reply_text || reply.to_json
    messages = Object.new
    messages.define_singleton_method(:create) do |**|
      calls += 1
      raise raise_error, "boom" if raise_error
      OpenStruct.new(content: [ OpenStruct.new(type: :text, text: text) ])
    end
    fake_client = Object.new
    fake_client.define_singleton_method(:messages) { messages }

    comments = Anthropic::Client.stub(:new, fake_client) do
      CommentGeneratorService.new.comments_for(file_id: file_id, year: year, content_html: content_html)
    end

    [ comments, calls ]
  end

  # Stubs Anthropic::Client.new, runs comments_for, and returns the exact
  # prompt string the service would have sent.
  def captured_prompt(file_id:, year: 2008, content_html: "<p>hello</p>")
    prompt = nil
    fake_response = OpenStruct.new(content: [ OpenStruct.new(type: :text, text: '{"comments":[],"commenters":[]}') ])
    messages = Object.new
    messages.define_singleton_method(:create) do |**kwargs|
      prompt = kwargs[:messages].first[:content]
      fake_response
    end
    fake_client = Object.new
    fake_client.define_singleton_method(:messages) { messages }

    Anthropic::Client.stub(:new, fake_client) do
      CommentGeneratorService.new.comments_for(file_id: file_id, year: year, content_html: content_html)
    end

    prompt
  end
end
