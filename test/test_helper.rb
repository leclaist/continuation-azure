ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "ostruct"

# Minitest 6 removed Object#stub. Re-implement it for test use.
class Object
  def stub(method_name, return_value, &block)
    original = method(method_name)
    singleton_class.define_method(method_name) do |*args, **kwargs, &blk|
      return_value.respond_to?(:call) ? return_value.call(*args, **kwargs, &blk) : return_value
    end
    yield
  ensure
    singleton_class.define_method(method_name, original)
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all
  end
end

# Fake Drive entry — mirrors GoogleDriveService::Entry struct without requiring auth.
def fake_entry(year: 2008, month: 11, day: 14)
  date = Date.new(year, month, day)
  OpenStruct.new(
    id:   "fake-file-#{year}-#{month}-#{day}",
    name: date.to_s,
    date: date,
    year: year,
    slug: date.strftime("%b-%d-%Y").downcase
  )
end

# Minimal Drive service double. Override keyword args to customise return values.
def fake_drive_service(by_year: {}, word_count: 0, for_year: [], by_slug: nil, html: "<p>test</p>")
  svc = Object.new
  svc.define_singleton_method(:files_by_year)  { by_year }
  svc.define_singleton_method(:total_word_count) { word_count }
  svc.define_singleton_method(:files_for_year) { |_| for_year }
  svc.define_singleton_method(:file_by_slug)   { |_, _| by_slug }
  svc.define_singleton_method(:content_html)   { |_| html }
  svc
end
