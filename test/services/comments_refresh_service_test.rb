require "test_helper"

class CommentsRefreshServiceTest < ActiveSupport::TestCase
  test "wipes comments and commenters, then regenerates every entry oldest to newest" do
    GeneratedComment.create!(file_id: "old", year: 2008, content_hash: "x", comments_json: "[]")
    Commenter.create!(username: "forgotten", personality: "gone")

    # Deliberately out of order, across years — continuity depends on the
    # commenters' memory building up in the order the entries were written.
    entries = [ drive_entry("2009-01-20"), drive_entry("2008-11-14"), drive_entry("2008-03-02") ]
    drive = drive_service_with(entries)
    drive.define_singleton_method(:content_html) { |id| "<p>#{id}</p>" }

    calls = []
    generator = Object.new
    generator.define_singleton_method(:comments_for) do |file_id:, year:, content_html:|
      calls << [ file_id, year, content_html ]
      Commenter.find_or_create_by!(username: "regular")
      []
    end

    result = GoogleDriveService.stub(:new, drive) do
      CommentGeneratorService.stub(:new, generator) { CommentsRefreshService.new.call }
    end

    assert_equal [ "2008-03-02", "2008-11-14", "2009-01-20" ].map { |n| drive_entry(n).id }, calls.map(&:first)
    assert_equal [ 2008, 2008, 2009 ], calls.map(&:second)
    assert_equal "<p>#{drive_entry("2008-03-02").id}</p>", calls.first.third
    assert_nil GeneratedComment.for_file("old")
    assert_nil Commenter.find_by(username: "forgotten")
    assert_equal({ entries_processed: 3, commenters: 1 }, result)
  end
end
