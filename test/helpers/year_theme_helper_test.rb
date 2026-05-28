require "test_helper"

class YearThemeHelperTest < ActiveSupport::TestCase
  include YearThemeHelper

  test "theme_for returns known theme for 2008" do
    theme = theme_for(2008)
    assert_equal "#FF1493", theme[:accent]
  end

  test "theme_for returns DEFAULT_THEME for unknown year" do
    assert_equal DEFAULT_THEME, theme_for(1999)
  end

  test "theme_for accepts string year" do
    assert_equal theme_for(2008), theme_for("2008")
  end

  test "theme_css_variables contains all five CSS custom properties" do
    css = theme_css_variables(2008)
    assert_match(/--color-bg:/, css)
    assert_match(/--color-surface:/, css)
    assert_match(/--color-text:/, css)
    assert_match(/--color-accent:/, css)
    assert_match(/--color-heading:/, css)
  end

  test "theme_name returns Pantone name for known year" do
    assert_equal "Turquoise", theme_name(2010)
  end

  test "theme_name returns nil for years without a named palette" do
    assert_nil theme_name(2008)
  end

  test "theme_name returns nil for unknown year" do
    assert_nil theme_name(1999)
  end
end
