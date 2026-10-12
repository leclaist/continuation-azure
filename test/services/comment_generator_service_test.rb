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

  private

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
