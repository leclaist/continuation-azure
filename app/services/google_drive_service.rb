require 'google/apis/drive_v3'
require 'googleauth'
require 'nokogiri'

class GoogleDriveService
  FOLDER_ID = ENV['GOOGLE_DRIVE_FOLDER_ID']
  SCOPE = Google::Apis::DriveV3::AUTH_DRIVE_READONLY

  def initialize
    @drive = Google::Apis::DriveV3::DriveService.new
    @drive.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(ENV['GOOGLE_SERVICE_ACCOUNT_JSON']),
      scope: SCOPE
    )
  end

  # { 2008 => [Entry, ...], 2009 => [...] }
  def files_by_year
    Rails.cache.fetch('drive/files_by_year', expires_in: 1.hour) do
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
      @drive.export_file(file_id, 'text/html', download_dest: io)
      extract_body(io.string)
    end
  end

  def self.parse_date(name)
    Date.parse(name)
  rescue ArgumentError, TypeError
    nil
  end

  def self.to_slug(date)
    date.strftime('%b-%d-%Y').downcase
  end

  private

  Entry = Struct.new(:id, :name, :date, :year, :slug, keyword_init: true)

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
      fields: 'files(id, name)',
      page_size: 1000
    )
    result.files || []
  end

  def extract_body(html)
    Nokogiri::HTML(html).at('body')&.inner_html || html
  end
end
