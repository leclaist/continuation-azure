require "google/apis/drive_v3"
require "googleauth"
require "nokogiri"

class GoogleDriveService
  FOLDER_ID = ENV["GOOGLE_DRIVE_FOLDER_ID"]
  SCOPE = Google::Apis::DriveV3::AUTH_DRIVE_READONLY
  AUDIO_MIME_TYPES = %w[audio/mpeg audio/mp4 audio/x-m4a].freeze

  def initialize
    @drive = Google::Apis::DriveV3::DriveService.new
    @drive.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(ENV["GOOGLE_SERVICE_ACCOUNT_JSON"]),
      scope: SCOPE
    )
  end

  # { 2008 => [Entry, ...], 2009 => [...] }
  def files_by_year
    Rails.cache.fetch("drive/files_by_year", expires_in: 1.hour) do
      list_files
        .filter_map { |f| build_entry(f) }
        .group_by(&:year)
    end
  end

  def files_for_year(year)
    (files_by_year[year.to_i] || []).sort_by(&:date)
  end

  def file_by_slug(year, slug)
    files_for_year(year).find { |e| e.slug == slug }
  end

  # Returns just the <body> HTML of the exported doc
  def content_html(file_id)
    Rails.cache.fetch("drive/file/#{file_id}", expires_in: 1.hour) do
      io = StringIO.new
      @drive.export_file(file_id, "text/html", download_dest: io)
      extract_body(io.string)
    end
  end

  # { "mar-12-2026" => AudioFile(id:, mime_type:), ... }
  def audio_by_slug
    Rails.cache.fetch("drive/audio_by_slug", expires_in: 1.hour) do
      list_audio_files
        .index_by { |f| File.basename(f.name, ".*").downcase }
        .transform_values { |f| build_audio_file(f) }
    end
  end

  def audio_for(slug)
    audio_by_slug[slug.downcase]
  end

  # Streams a Drive file's bytes to the given block as they arrive over the
  # wire, rather than buffering the whole file in memory.
  def stream_audio(file_id, &block)
    @drive.get_file(file_id, download_dest: ChunkWriter.new(&block))
  end

  def total_word_count
    Rails.cache.fetch("drive/total_word_count", expires_in: 6.hours) do
      files_by_year.values.flatten.sum do |entry|
        html = content_html(entry.id)
        Nokogiri::HTML(html).text.scan(/\S+/).size
      end
    end
  end

  def self.parse_date(name)
    Date.parse(name)
  rescue ArgumentError, TypeError
    nil
  end

  def self.to_slug(date)
    date.strftime("%b-%d-%Y").downcase
  end

  private

  Entry = Struct.new(:id, :name, :date, :year, :slug, keyword_init: true)
  AudioFile = Struct.new(:id, :mime_type, keyword_init: true)

  class ChunkWriter
    def initialize(&block)
      @block = block
    end

    def write(chunk)
      @block.call(chunk)
    end
  end

  def build_entry(file)
    date = self.class.parse_date(file.name)
    return nil unless date

    Entry.new(
      id: file.id,
      name: file.name,
      date: date,
      year: date.year,
      slug: self.class.to_slug(date)
    )
  end

  def list_files
    result = @drive.list_files(
      q: "'#{FOLDER_ID}' in parents and trashed = false",
      fields: "files(id, name)",
      page_size: 1000
    )
    result.files || []
  end

  def build_audio_file(file)
    AudioFile.new(id: file.id, mime_type: file.mime_type)
  end

  def list_audio_files
    mime_clause = AUDIO_MIME_TYPES.map { |type| "mimeType = '#{type}'" }.join(" or ")
    result = @drive.list_files(
      q: "'#{FOLDER_ID}' in parents and trashed = false and (#{mime_clause})",
      fields: "files(id, name, mimeType)",
      page_size: 1000
    )
    result.files || []
  end

  def extract_body(html)
    Nokogiri::HTML(html).at("body")&.inner_html || html
  end
end
