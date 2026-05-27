require "anthropic"
require "nokogiri"

class CommentGeneratorService
  YEAR_VOICE = {
    2008 => {
      style: "MySpace-era internet culture (2008). Use AIM-style usernames like xXdarkrose14Xx or skaterdude42. "\
             "Abbreviations like omg, lol, brb, ttyl, omfg, rofl, ily. Heavy use of emoticons like :) :( ;) xD <3 "\
             "Dramatic emo/scene language. Random capitalization for emphasis like 'that is SO true'. "\
             "Ending sentences with multiple punctuation like 'omg!!!' or '???'. References to MySpace, AIM, Hot Topic.",
      count: 4
    }
  }.freeze

  DEFAULT_VOICE = {
    style: "generic early-2000s blog commenter. Friendly but a bit stilted, like early internet forum culture.",
    count: 3
  }.freeze

  def initialize
    @client = Anthropic::Client.new
  end

  def comments_for(file_id:, year:, content_html:)
    hash = Digest::SHA256.hexdigest(content_html)
    cached = GeneratedComment.for_file(file_id)

    return cached.comments if cached && !cached.stale?(hash)

    comments = generate(year: year, content_html: content_html)
    return comments if comments.empty?

    if cached
      cached.update!(comments_json: comments.to_json, content_hash: hash)
    else
      GeneratedComment.create!(file_id: file_id, year: year, comments_json: comments.to_json, content_hash: hash)
    end
    comments
  end

  private

  def generate(year:, content_html:)
    voice = YEAR_VOICE[year] || DEFAULT_VOICE
    plain_text = Nokogiri::HTML(content_html).text.strip.truncate(5000)

    prompt = <<~PROMPT
      You are generating fake blog comments for a personal journal entry from #{year}.
      The comments should be written in the style of: #{voice[:style]}

      Write exactly #{voice[:count]} top-level comments from different fictional people reacting to this journal entry.
      Read the entire entry before writing. Each comment must reference a specific detail, moment, or feeling
      from the entry — not just the opening. Spread references across the whole entry, not just the beginning.
      Keep each comment short (1-3 sentences). Use era-appropriate usernames.

      Some comments (not all) should have replies from other people. Replies should feel like a real comment section
      devolving into argument — people disagreeing with each other, taking sides, getting defensive, going off topic.
      Each reply thread should have 2-4 replies. Replies argue with the comment above them or with each other.
      Keep replies short and increasingly unhinged as the thread goes on.

      Return ONLY a JSON array with no other text.
      Each object has: "username", "body", and optionally "replies" (an array of {"username", "body"} objects).

      Journal entry text:
      #{plain_text}
    PROMPT

    response = @client.messages.create(
      model: :"claude-haiku-4-5-20251001",
      max_tokens: 1500,
      messages: [ { role: "user", content: prompt } ]
    )

    text = response.content.find { |b| b.type == :text }&.text || "[]"
    text = text.gsub(/\A```(?:json)?\s*|\s*```\z/, "").strip
    JSON.parse(text)
  rescue JSON::ParserError => e
    Rails.logger.error("CommentGeneratorService error: #{e.message}")
    []
  rescue Anthropic::Error => e
    Rails.logger.error("CommentGeneratorService error: #{e.message}")
    []
  end
end
