require "test_helper"
require "capybara/cuprite"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # test_helper.rb forks parallel workers for the rest of the suite; forking
  # around a spawned browser subprocess is unreliable, so system tests run serially.
  parallelize(workers: 1)

  # Rails' driven_by(:cuprite) re-registers the Capybara driver itself on every
  # test (action_dispatch/system_testing/driver.rb#register_cuprite) — options
  # must go through here, not a separate Capybara.register_driver call, or
  # they're silently dropped.
  driven_by :cuprite, screen_size: [ 1200, 800 ], options: {
    process_timeout: 20,
    # A cold first request in dev (no eager loading, no asset precompile)
    # can take longer than Ferrum's 5s default CDP command timeout.
    timeout: 20,
    browser_path: ENV["CUPRITE_CHROME_PATH"],
    # Headless Chrome runs as root in the dev container, which refuses the
    # sandbox unless it's explicitly disabled. /dev/shm is also capped at the
    # Docker default of 64MB, which crashes Chrome's shared-memory setup —
    # disable-dev-shm-usage makes it fall back to disk-backed temp files.
    browser_options: { "no-sandbox" => nil, "disable-gpu" => nil, "disable-dev-shm-usage" => nil }
  }

  # Capybara's 2s default wait can be too tight for a click that has to round-trip
  # through actually decoding and starting audio playback, especially on a cold
  # CI runner.
  Capybara.default_max_wait_time = 5
end
