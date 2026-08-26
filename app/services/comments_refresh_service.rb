class CommentsRefreshService
  def call
    GeneratedComment.delete_all
    Commenter.delete_all

    drive = GoogleDriveService.new
    entries = drive.files_by_year.values.flatten.sort_by(&:date)

    entries.each do |entry|
      content = drive.content_html(entry.id)
      CommentGeneratorService.new.comments_for(file_id: entry.id, year: entry.year, content_html: content)
    end

    { entries_processed: entries.size, commenters: Commenter.count }
  end
end
