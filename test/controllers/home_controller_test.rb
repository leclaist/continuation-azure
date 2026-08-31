require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "GET / returns 200" do
    svc = fake_drive_service(by_year: { 2008 => [ fake_entry ], 2009 => [ fake_entry(year: 2009) ] })
    GoogleDriveService.stub(:new, svc) do
      get root_url
      assert_response :success
    end
  end

  test "GET / lists years oldest to most recent" do
    svc = fake_drive_service(by_year: { 2009 => [ fake_entry(year: 2009) ], 2008 => [ fake_entry ] })
    GoogleDriveService.stub(:new, svc) do
      get root_url
      assert_select "ul.year-list li:nth-child(1) a[href='#{year_path(2008)}']"
      assert_select "ul.year-list li:nth-child(2) a[href='#{year_path(2009)}']"
    end
  end

  test "GET / increments visitor counter" do
    svc = fake_drive_service(by_year: {})
    GoogleDriveService.stub(:new, svc) do
      before = VisitorCounter.current
      get root_url
      assert_equal before + 1, VisitorCounter.current
    end
  end
end
