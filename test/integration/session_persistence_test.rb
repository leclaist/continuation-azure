require "test_helper"

class SessionPersistenceTest < ActionDispatch::IntegrationTest
  # The test environment disables forgery protection, so csrf_meta_tags never
  # writes anything into the session and a real cookie round-trip never
  # happens. Force it on here so this test actually exercises that.
  setup { ActionController::Base.allow_forgery_protection = true }
  teardown { ActionController::Base.allow_forgery_protection = false }

  test "a page renders successfully on a repeat visit with an existing session" do
    svc = fake_drive_service(by_year: { 2008 => [ fake_entry ] })
    GoogleDriveService.stub(:new, svc) do
      get root_url
      assert_response :success

      # The layout writes a CSRF token into the session on first render, so
      # this second request decrypts an existing session cookie instead of
      # starting a fresh one. A fresh, cookie-less request never exercises
      # that decrypt path — which is exactly how a json 3.x upgrade broke
      # every repeat visit while looking fine on first load.
      get root_url
      assert_response :success
    end
  end
end
