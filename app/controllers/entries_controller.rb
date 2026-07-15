class EntriesController < ApplicationController
  include ActionController::Live

  def show
    service = GoogleDriveService.new
    @year = params[:year].to_i
    entry = service.file_by_slug(@year, params[:slug])

    return render plain: "Entry not found", status: :not_found unless entry

    @title = entry.name
    @content = service.content_html(entry.id)

    if ENV["ANTHROPIC_API_KEY"].present?
      @comments = CommentGeneratorService.new.comments_for(
        file_id: entry.id,
        year: @year,
        content_html: @content
      )
    else
      @comments = []
    end
  end

  def audio
    service = GoogleDriveService.new
    file = service.audio_for(params[:slug])

    return head :not_found unless file

    response.headers["Content-Type"] = file.mime_type
    response.headers["Accept-Ranges"] = "bytes"
    response.headers["Last-Modified"] = Time.now.httpdate # avoid Rack::ETag buffering the stream

    service.stream_audio(file.id) { |chunk| response.stream.write(chunk) }
  ensure
    response.stream.close
  end
end
