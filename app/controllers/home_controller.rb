class HomeController < ApplicationController
  def index
    @years = GoogleDriveService.new.files_by_year.keys.sort.reverse
    @visitor_count = VisitorCounter.increment!
  end
end
