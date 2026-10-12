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

    # Safari won't play (or seek) <audio> unless byte-range requests get a 206.
    range = requested_range(file.size)
    if range == :unsatisfiable
      response.headers["Content-Range"] = "bytes */#{file.size}"
      return head :range_not_satisfiable
    elsif range
      response.status = :partial_content
      response.headers["Content-Range"] = "bytes #{range.first}-#{range.last}/#{file.size}"
      response.headers["Content-Length"] = range.size.to_s
    end

    service.stream_audio(file.id, range: range) { |chunk| response.stream.write(chunk) }
  ensure
    response.stream.close
  end

  private

  # Parses a single-range `Range: bytes=...` header into an inclusive Integer
  # Range, or :unsatisfiable. Returns nil (serve the whole file) when there's
  # no header, it's multi-range/malformed, or the file size is unknown.
  def requested_range(size)
    match = request.headers["Range"].to_s.match(/\Abytes=(\d*)-(\d*)\z/)
    return nil unless match && size && size.positive?

    first, last = match[1], match[2]
    return nil if first.empty? && last.empty?

    if first.empty? # suffix range: the last N bytes
      return :unsatisfiable if last.to_i.zero?
      first = [ size - last.to_i, 0 ].max
      last = size - 1
    else
      first = first.to_i
      last = last.empty? ? size - 1 : [ last.to_i, size - 1 ].min
    end

    return :unsatisfiable if first >= size || first > last
    first..last
  end
end
