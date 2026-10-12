require "application_system_test_case"

class AudioPlayerTest < ApplicationSystemTestCase
  setup do
    @entry = fake_entry(year: 2008, month: 11, day: 14)
  end

  test "clicking the toggle button plays, then pauses, the recording" do
    audio_file = OpenStruct.new(id: "fake-audio-id", mime_type: "audio/wav")
    svc = fake_drive_service(
      by_slug: @entry,
      html: "<p>hello</p>",
      audio: audio_file,
      audio_bytes: silent_wav_bytes
    )

    GoogleDriveService.stub(:new, svc) do
      visit entry_path(year: 2008, slug: @entry.slug)

      toggle = find(".audio-player__toggle")
      assert_equal "Play recording", toggle["aria-label"]
      assert_selector ".audio-player__icon", text: "▶"

      toggle.click
      wait_for_audio_state(playing: true)

      assert_selector ".audio-player__toggle[aria-label='Pause recording']"
      assert_selector ".audio-player__icon", text: "⏸"

      toggle.click
      wait_for_audio_state(playing: false)

      assert_selector ".audio-player__toggle[aria-label='Play recording']"
      assert_selector ".audio-player__icon", text: "▶"
    end
  end

  private

  # Waits for the Stimulus controller's actual <audio> element to reach the
  # given playing/paused state, rather than polling the DOM text Capybara's
  # normal assert_selector would. The controller builds `new Audio(...)`
  # detached from the DOM, so it's reached via the Stimulus registry, not a
  # CSS selector. On timeout this surfaces the audio element's real state
  # (readyState, networkState, error) instead of a bare "no matches" failure,
  # since a plain DOM-polling wait gave no signal about *why* it was still
  # waiting when this flaked in CI (see git history on this file).
  def wait_for_audio_state(playing:, timeout: 15)
    result = page.driver.browser.page.evaluate_async(<<~JS, timeout)
      const done = arguments[0]
      const wantPlaying = #{playing}
      const el = document.querySelector('[data-controller="audio-player"]')
      const controller = window.Stimulus.getControllerForElementAndIdentifier(el, "audio-player")
      const deadline = Date.now() + #{timeout * 1000 - 500}

      const check = () => {
        const audio = controller && controller.audio
        const isPlaying = !!audio && !audio.paused && !audio.ended && audio.currentTime > 0

        if (isPlaying === wantPlaying) {
          done({ ok: true })
        } else if (Date.now() > deadline) {
          done({
            ok: false,
            hasController: !!controller,
            hasAudio: !!audio,
            paused: audio && audio.paused,
            currentTime: audio && audio.currentTime,
            readyState: audio && audio.readyState,
            networkState: audio && audio.networkState,
            errorCode: audio && audio.error && audio.error.code,
            errorMessage: audio && audio.error && audio.error.message
          })
        } else {
          setTimeout(check, 50)
        }
      }
      check()
    JS

    assert result["ok"], "audio did not reach playing=#{playing} within #{timeout}s: #{result.inspect}"
  end

  # A minimal, genuinely decodable WAV file (silence) — the controller builds
  # a real <audio> element around the streamed bytes, so playback only
  # actually starts (firing the "play" event the controller listens for) if
  # the bytes are valid audio, not just an arbitrary string.
  def silent_wav_bytes(duration_seconds: 0.2, sample_rate: 8000)
    sample_count = (duration_seconds * sample_rate).to_i
    data = ("\x00\x00" * sample_count).b
    byte_rate = sample_rate * 2

    header = +"RIFF"
    header << [ 36 + data.bytesize ].pack("V")
    header << "WAVEfmt "
    header << [ 16 ].pack("V")       # fmt chunk size
    header << [ 1, 1 ].pack("vv")    # PCM, mono
    header << [ sample_rate ].pack("V")
    header << [ byte_rate ].pack("V")
    header << [ 2, 16 ].pack("vv")   # block align, bits per sample
    header << "data"
    header << [ data.bytesize ].pack("V")

    (header + data).b
  end
end
