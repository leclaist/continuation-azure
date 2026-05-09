class HomeController < ApplicationController
  def index
    service = GoogleDriveService.new
    @years = service.files_by_year.keys.sort.reverse
    @visitor_count = VisitorCounter.increment!
    @word_count = service.total_word_count
  end
end
