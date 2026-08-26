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
    plain_text = Nokogiri::HTML(content_html).text.strip.truncate(100_000)
    roster = Commenter.order(:created_at)

    prompt = <<~PROMPT
      You are generating fake blog comments for a personal journal entry from #{year}.
      The comments should be written in the style of: #{voice[:style]}

      #{roster_section(roster)}

      Write exactly #{voice[:count]} top-level comments from fictional people reacting to this journal entry.
      Prefer reusing the existing commenters above over inventing new ones — have them speak from their established
      personality and reference their own memory of what's happened so far, forming opinions and relationships that
      carry across entries rather than just reacting to this one. Only introduce a brand new commenter if the
      roster above is empty or thin. Read the entire entry before writing. Each comment must reference a specific
      detail, moment, or feeling from the entry — not just the opening. Spread references across the whole entry,
      not just the beginning. Keep each comment short (1-3 sentences). Use era-appropriate usernames.

      Some comments (not all) should have replies from other people. Replies should feel like a real comment section
      devolving into argument — people disagreeing with each other, taking sides, getting defensive, going off topic.
      Each reply thread should have 2-4 replies. Replies argue with the comment above them or with each other.
      Keep replies short and increasingly unhinged as the thread goes on.

      Return ONLY a JSON object with no other text, shaped like:
      {
        "comments": [ { "username", "body", and optionally "replies" (an array of {"username", "body"} objects) } ],
        "commenters": [ { "username", "personality" (a short stable trait/voice description), "memory" (a 1-2
          sentence updated summary of this commenter's arc after this entry) } for every username used above,
          new or existing ]
      }

      Journal entry text:
      #{plain_text}
    PROMPT

    response = @client.messages.create(
      model: :"claude-haiku-4-5-20251001",
      max_tokens: 3000,
      messages: [ { role: "user", content: prompt } ]
    )

    text = response.content.find { |b| b.type == :text }&.text || "{}"
    text = text.gsub(/\A```(?:json)?\s*|\s*```\z/, "").strip
    data = JSON.parse(text)
    apply_commenter_updates(data["commenters"] || [])
    data["comments"] || []
  rescue JSON::ParserError => e
    Rails.logger.error("CommentGeneratorService error: #{e.message}")
    []
  rescue Anthropic::Error => e
    Rails.logger.error("CommentGeneratorService error: #{e.message}")
    []
  end

  def roster_section(roster)
    return "There are no existing commenters yet — introduce a small cast." if roster.empty?

    lines = roster.map do |c|
      "- #{c.username}: #{c.personality}#{" (so far: #{c.memory_summary})" if c.memory_summary.present?}"
    end
    "Existing commenters:\n#{lines.join("\n")}"
  end

  def apply_commenter_updates(commenter_updates)
    commenter_updates.each do |update|
      username = update["username"]
      next if username.blank?

      commenter = Commenter.find_or_initialize_by(username: username)
      commenter.personality = update["personality"] if commenter.new_record?
      commenter.memory_summary = update["memory"]
      commenter.save!
    end
  end
end
