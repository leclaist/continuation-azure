require "test_helper"

# End-to-end visitor flows through the real routes, views, and the real
# GoogleDriveService lookup logic (only the Drive API calls are faked — see
# drive_service_with). Controller tests check each page in isolation with a
# canned entry; these follow the links each page actually renders, so a
# broken path helper or a slug mismatch between the year list and the entry
# lookup fails here.
class VisitorFlowTest < ActionDispatch::IntegrationTest
  test "home → year → entry by following the rendered links" do
    entries = [ drive_entry("2008-11-14"), drive_entry("2008-03-02"), drive_entry("2009-01-20") ]
    svc = drive_service_with(entries, html: "<p>Drove out to the coast today.</p>")

    GoogleDriveService.stub(:new, svc) do
      get root_url
      assert_response :success
      assert_select "ul.year-list a", text: "2008"

      follow_link "ul.year-list a", text: "2008"
      assert_response :success
      assert_select "body[data-year='2008']"
      # Entries are listed oldest first.
      assert_select "ul.entry-list li:nth-child(1) a", text: "2008-03-02"
      assert_select "ul.entry-list li:nth-child(2) a", text: "2008-11-14"

      follow_link "ul.entry-list a", text: "2008-11-14"
      assert_response :success
      assert_select "h1", text: "2008-11-14"
      assert_select ".doc-content", text: /Drove out to the coast today\./

      follow_link "a.back-link"
      assert_equal year_path(2008), path
    end
  end

  test "an entry with a recording renders a player whose source actually streams" do
    entry = drive_entry("2008-11-14")
    audio = OpenStruct.new(id: "audio-1", mime_type: "audio/mpeg", size: 4)
    svc = drive_service_with([ entry ], audio_by_slug: { entry.slug => audio })
    svc.define_singleton_method(:stream_audio) { |_, range: nil, &block| block.call("abcd") }

    GoogleDriveService.stub(:new, svc) do
      get entry_url(2008, entry.slug)
      src = css_select(".audio-player").first&.[]("data-audio-player-src-value")
      assert src, "expected an audio player on the entry page"

      get src
      assert_response :success
      assert_equal "audio/mpeg", @response.media_type
      assert_equal "abcd", @response.body
    end
  end

  # Every year that has config (theme, ad, playlist) should render with that
  # config — a YAML typo or a partial that breaks for one year fails here
  # rather than in production.
  configured_years = (
    YearThemeHelper::THEMES.keys +
    YAML.load_file(Rails.root.join("config/banner_ads.yml")).keys +
    YAML.load_file(Rails.root.join("config/music_playlists.yml")).keys
  ).uniq.sort

  configured_years.each do |year|
    test "the #{year} year and entry pages render with that year's theme, ad, and playlist" do
      ads = YAML.load_file(Rails.root.join("config/banner_ads.yml"))
      playlists = YAML.load_file(Rails.root.join("config/music_playlists.yml"))
      entry = drive_entry("#{year}-06-15")

      GoogleDriveService.stub(:new, drive_service_with([ entry ])) do
        [ year_url(year), entry_url(year, entry.slug) ].each do |url|
          get url
          assert_response :success, "#{url} failed"
          assert_select "body[data-year='#{year}']"
          assert_includes @response.body, "--color-accent:  #{YearThemeHelper::THEMES.fetch(year, YearThemeHelper::DEFAULT_THEME)[:accent]}"

          if ads[year]
            assert_select ".banner-ad.banner-ad--#{year}", 1
            assert_select ".banner-ad__name", text: /\S/
          else
            assert_select ".banner-ad", 0
          end

          if playlists[year]
            assert_select ".music-player [data-yt-playlist='#{playlists[year]["playlist_id"]}']"
          else
            assert_select ".music-player", 0
          end
        end
      end
    end
  end

  test "config files only list valid years with the fields the views read" do
    YAML.load_file(Rails.root.join("config/banner_ads.yml")).each do |year, ads|
      assert_kind_of Integer, year
      Array(ads).each do |ad|
        assert_empty %w[business tagline cta url] - ad.keys, "#{year} ad #{ad.inspect} is missing fields"
      end
    end

    YAML.load_file(Rails.root.join("config/music_playlists.yml")).each do |year, playlist|
      assert_kind_of Integer, year
      assert playlist["playlist_id"].present?, "#{year} playlist has no playlist_id"
    end
  end

  test "old browsers are turned away but non-browser clients (curl, uptime checks) aren't" do
    GoogleDriveService.stub(:new, drive_service_with([ drive_entry("2008-11-14") ])) do
      get root_url, headers: { "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.149 Safari/537.36" }
      assert_response :not_acceptable

      get root_url, headers: { "User-Agent" => "curl/8.5.0" }
      assert_response :success
    end
  end

  private

  def follow_link(selector, text: nil)
    link = css_select(selector).find { |a| text.nil? || a.text.strip == text }
    assert link, "no #{selector} link#{" with text #{text.inspect}" if text}"
    get link["href"]
  end
end
