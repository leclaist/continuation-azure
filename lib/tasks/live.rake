# Nightly live check against the real Google Drive folder and Anthropic API,
# run inside a deployed app (so it uses that environment's own credentials)
# by .github/workflows/nightly-live-check.yml. Bypasses Rails.cache so a
# revoked share or rotated key shows up here instead of an hour later on the
# site. Prints LIVE CHECK PASSED on success — the workflow greps for that
# rather than trusting `fly ssh console` to propagate the exit status.
namespace :live do
  desc "Check the live Drive folder and Anthropic API are reachable and sane"
  task check: :environment do
    errors = []
    # Runs one check, recording (not raising) a failure so every check runs.
    check = ->(label, &blk) do
      result = blk.call
      puts "ok   #{label}"
      result
    rescue => e
      errors << "#{label}: #{e.class}: #{e.message}"
      puts "FAIL #{label}: #{e.class}: #{e.message}"
      nil
    end

    drive = check.call("authenticate to Drive") { GoogleDriveService.new }

    if drive
      docs = check.call("list journal docs") do
        files = drive.send(:list_files)
        raise "folder has no journal docs — share revoked or wrong folder?" if files.empty?
        puts "     #{files.size} docs"
        files
      end || []

      entries = docs.filter_map { |f| drive.send(:build_entry, f) }

      # Undated docs (working notes etc.) are simply not shown — worth knowing, not failing over.
      undated = docs.reject { |f| GoogleDriveService.parse_date(f.name) }.map(&:name)
      puts "warn not shown on the site (no date in name): #{undated.inspect}" if undated.any?

      check.call("no doc is dated without a year") do
        # Date.parse fills in the current year when a name has none, so a
        # stray "March notes" silently becomes a 1st-of-March entry this year.
        yearless = docs.select { |f| GoogleDriveService.parse_date(f.name) && f.name !~ /\b(19|20)\d{2}\b/ }.map(&:name)
        raise "would show under the current year: #{yearless.inspect}" if yearless.any?
      end

      check.call("no two docs share a date (the second would be unreachable)") do
        dupes = entries.group_by { |e| [ e.year, e.slug ] }.select { |_, es| es.size > 1 }
        raise dupes.map { |(_, slug), es| "#{slug}: #{es.map(&:name).inspect}" }.join("; ") if dupes.any?
      end

      newest = entries.max_by(&:date)
      check.call("export newest entry (#{newest&.name})") do
        raise "no dated entries" unless newest
        text = Nokogiri::HTML(drive.content_html(newest.id, fresh: true)).text.strip
        raise "exported HTML has no text" if text.empty?
        puts "     #{text.split.size} words"
      end

      audio = check.call("list recordings") { drive.send(:list_audio_files) } || []
      check.call("every recording matches an entry") do
        slugs = entries.map(&:slug).to_set
        orphans = audio.map(&:name).reject { |n| slugs.include?(File.basename(n, ".*").downcase) }
        raise "no entry for #{orphans.inspect}" if orphans.any?
      end

      if (recording = audio.first)
        check.call("range-fetch a recording (#{recording.name})") do
          bytes = +""
          drive.stream_audio(recording.id, range: 0..1) { |chunk| bytes << chunk }
          raise "asked for 2 bytes, got #{bytes.bytesize}" unless bytes.bytesize == 2
        end
      end
    end

    if ENV["ANTHROPIC_API_KEY"].present?
      check.call("Anthropic key works and #{CommentGeneratorService::MODEL} still exists") do
        Anthropic::Client.new.models.retrieve(CommentGeneratorService::MODEL)
      end
    else
      puts "skip Anthropic (ANTHROPIC_API_KEY not set — comments are disabled)"
    end

    if errors.any?
      puts "\nLIVE CHECK FAILED (#{errors.size})"
      exit 1
    end
    puts "\nLIVE CHECK PASSED"
  end
end
