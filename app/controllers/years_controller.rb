class YearsController < ApplicationController
  def show
    @year = params[:year].to_i
    @entries = GoogleDriveService.new.files_for_year(@year)

    render plain: 'Year not found', status: :not_found if @entries.empty?
  end
end
