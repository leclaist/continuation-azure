class HomeController < ApplicationController
  def index
    service = GoogleDriveService.new
    by_year = service.files_by_year
    @years = by_year.keys.sort.reverse
    @entry_counts = by_year.transform_values(&:count)
    @visitor_count = VisitorCounter.increment!
    @word_count = service.total_word_count
  end
end
