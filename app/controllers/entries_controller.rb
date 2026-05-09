class EntriesController < ApplicationController
  def show
    service = GoogleDriveService.new
    @year = params[:year].to_i
    entry = service.file_by_slug(@year, params[:slug])

    return render plain: 'Entry not found', status: :not_found unless entry

    @title = entry.name
    @content = service.content_html(entry.id)
  end
end
