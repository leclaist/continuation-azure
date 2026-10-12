require "test_helper"

# GoogleDriveService's Drive API calls are intentionally untested (see
# CLAUDE.md), but the logic that turns Drive file names into dates, years,
# and URL slugs is pure — and every URL on the site depends on it.
class GoogleDriveServiceTest < ActiveSupport::TestCase
  test "parse_date understands the date formats journal files are named with" do
    assert_equal Date.new(2008, 11, 14), GoogleDriveService.parse_date("2008-11-14")
    assert_equal Date.new(2008, 1, 3), GoogleDriveService.parse_date("Jan 3 2008")
    assert_equal Date.new(2008, 1, 3), GoogleDriveService.parse_date("January 3, 2008")
  end

  test "parse_date tolerates Drive's duplicate/copy naming" do
    assert_equal Date.new(2008, 1, 3), GoogleDriveService.parse_date("2008-01-03 (2)")
    assert_equal Date.new(2008, 11, 14), GoogleDriveService.parse_date("Copy of 2008-11-14")
  end

  test "parse_date returns nil for names with no date" do
    assert_nil GoogleDriveService.parse_date("Untitled document")
    assert_nil GoogleDriveService.parse_date("notes")
    assert_nil GoogleDriveService.parse_date("")
    assert_nil GoogleDriveService.parse_date(nil)
  end

  # Documents a Date.parse quirk rather than endorsing it: a stray doc named
  # with just a month becomes an entry on the 1st of that month in the
  # *current* year. The nightly live check flags any such file names.
  test "parse_date fills in the current year for a name with a month but no year" do
    assert_equal Date.new(Date.current.year, 3, 1), GoogleDriveService.parse_date("March notes")
  end

  test "to_slug is the lowercase month-day-year form used in entry URLs" do
    assert_equal "nov-14-2008", GoogleDriveService.to_slug(Date.new(2008, 11, 14))
    assert_equal "jan-03-2009", GoogleDriveService.to_slug(Date.new(2009, 1, 3))
  end

  test "files_by_year skips undated files and groups the rest by year" do
    svc = GoogleDriveService.allocate
    files = [ "2008-11-14", "Untitled document", "2009-01-20", "2008-03-02" ].map.with_index do |name, i|
      OpenStruct.new(id: "f#{i}", name: name)
    end
    svc.define_singleton_method(:list_files) { files }

    by_year = svc.files_by_year

    assert_equal [ 2008, 2009 ], by_year.keys.sort
    assert_equal %w[2008-11-14 2008-03-02], by_year[2008].map(&:name)
    assert_equal [ "mar-02-2008", "nov-14-2008" ], svc.files_for_year(2008).map(&:slug)
    assert_equal "f0", svc.file_by_slug(2008, "nov-14-2008").id
    assert_nil svc.file_by_slug(2008, "nov-15-2008")
  end

  test "audio files are matched to entries by slug, case-insensitively" do
    svc = GoogleDriveService.allocate
    files = [ OpenStruct.new(id: "a1", name: "Nov-14-2008.m4a", mime_type: "audio/x-m4a", size: "1234") ]
    svc.define_singleton_method(:list_audio_files) { files }

    audio = svc.audio_for("nov-14-2008")

    assert_equal "a1", audio.id
    assert_equal "audio/x-m4a", audio.mime_type
    assert_equal 1234, audio.size
    assert_equal audio, svc.audio_for("NOV-14-2008")
    assert_nil svc.audio_for("nov-15-2008")
  end
end
