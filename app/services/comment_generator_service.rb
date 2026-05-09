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
    cached = GeneratedComment.for_file(file_id)
    return cached.comments if cached

    comments = generate(year: year, content_html: content_html)
    GeneratedComment.create!(
      file_id: file_id,
      year: year,
      comments_json: comments.to_json
    )
    comments
  end

  private

  def generate(year:, content_html:)
    voice = YEAR_VOICE[year] || DEFAULT_VOICE
    plain_text = Nokogiri::HTML(content_html).text.strip.truncate(1500)

    prompt = <<~PROMPT
      You are generating fake blog comments for a personal journal entry from #{year}.
      The comments should be written in the style of: #{voice[:style]}

      Write exactly #{voice[:count]} comments from different fictional people reacting to this journal entry.
      Each comment should feel authentic to the era and react specifically to something in the entry content.
      Keep each comment short (1-3 sentences). Use era-appropriate usernames.

      Return ONLY a JSON array with no other text. Each object has: "username" and "body".

      Journal entry text:
      #{plain_text}
    PROMPT

    response = @client.messages.create(
      model: :"claude-haiku-4-5-20251001",
      max_tokens: 800,
      messages: [{ role: "user", content: prompt }]
    )

    text = response.content.find { |b| b.type == :text }&.text || "[]"
    JSON.parse(text)
  rescue JSON::ParserError, Anthropic::Error => e
    Rails.logger.error("CommentGeneratorService error: #{e.message}")
    []
  end
end
