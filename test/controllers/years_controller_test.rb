require "test_helper"

class YearsControllerTest < ActionDispatch::IntegrationTest
  test "GET /:year returns 200 when entries exist" do
    entry = fake_entry(year: 2008)
    svc = fake_drive_service(for_year: [ entry ])
    GoogleDriveService.stub(:new, svc) do
      get year_url(2008)
      assert_response :success
    end
  end

  test "GET /:year returns 404 when no entries" do
    svc = fake_drive_service(for_year: [])
    GoogleDriveService.stub(:new, svc) do
      get year_url(2008)
      assert_response :not_found
    end
  end

  test "non-year path returns 404" do
    get "/notayear"
    assert_response :not_found
  end
end
