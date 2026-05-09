module YearThemeHelper
  # Palettes keyed by year, based on Pantone's Color of the Year.
  # Each theme: bg, surface, text, accent, heading
  THEMES = {
    2008 => { name: nil,                         bg: "#0A0A0F", surface: "#13131A", text: "#E0D0E8", accent: "#FF1493", heading: "#FF69B4" },
    2009 => { name: nil,                         bg: "#03020D", surface: "#0A0720", text: "#D8C8FF", accent: "#A855F7", heading: "#F0ABFF" },
    2010 => { name: "Turquoise",              bg: "#F0FAFA", surface: "#FFFFFF", text: "#0D2E2E", accent: "#2A9D8F", heading: "#1A6B65" },
    2011 => { name: "Honeysuckle",            bg: "#FFF5F7", surface: "#FFFFFF", text: "#3A001A", accent: "#D94F70", heading: "#A0304E" },
    2012 => { name: "Tangerine Tango",        bg: "#FFF8F5", surface: "#FFFFFF", text: "#3A1000", accent: "#DD4132", heading: "#A02A1F" },
    2013 => { name: "Emerald",                bg: "#F0FAF5", surface: "#FFFFFF", text: "#002E1A", accent: "#009473", heading: "#006B52" },
    2014 => { name: "Radiant Orchid",         bg: "#FAF0FA", surface: "#FFFFFF", text: "#2E0035", accent: "#B163A3", heading: "#7A3D70" },
    2015 => { name: "Marsala",                bg: "#FAF0EF", surface: "#FFFFFF", text: "#2E1010", accent: "#955251", heading: "#6A3535" },
    2016 => { name: "Rose Quartz & Serenity", bg: "#FEF8F8", surface: "#FFFFFF", text: "#2A2040", accent: "#7B9EC7", heading: "#C07A78" },
    2017 => { name: "Greenery",               bg: "#F5FAF0", surface: "#FFFFFF", text: "#1A2E0A", accent: "#88B04B", heading: "#5A7D28" },
    2018 => { name: "Ultra Violet",           bg: "#F8F5FF", surface: "#FFFFFF", text: "#1E0A3A", accent: "#5F4B8B", heading: "#3D2870" },
    2019 => { name: "Living Coral",           bg: "#FFF8F5", surface: "#FFFFFF", text: "#3A1000", accent: "#E8634A", heading: "#C0442A" },
    2020 => { name: "Classic Blue",           bg: "#F0F5FA", surface: "#FFFFFF", text: "#0A1E3A", accent: "#0F4C81", heading: "#0A3561" },
    2021 => { name: "Illuminating",           bg: "#FAFAF8", surface: "#FFFFFF", text: "#2A2A28", accent: "#C8A800", heading: "#7A7A77" },
    2022 => { name: "Very Peri",              bg: "#F5F5FF", surface: "#FFFFFF", text: "#1A1A3A", accent: "#6667AB", heading: "#4040A0" },
    2023 => { name: "Viva Magenta",           bg: "#FAF0F3", surface: "#FFFFFF", text: "#3A001A", accent: "#BB2649", heading: "#8A1A35" },
    2024 => { name: "Peach Fuzz",             bg: "#FFF8F5", surface: "#FFFFFF", text: "#3A2010", accent: "#C87840", heading: "#A05828" },
    2025 => { name: "Mocha Mousse",           bg: "#FAF5F0", surface: "#FFFFFF", text: "#2A1E10", accent: "#A47864", heading: "#7A5545" }
  }.freeze

  DEFAULT_THEME = { bg: "#FAFAF8", surface: "#FFFFFF", text: "#1A1A1A", accent: "#555555", heading: "#111111" }.freeze

  def theme_for(year)
    THEMES.fetch(year.to_i, DEFAULT_THEME)
  end

  def theme_css_variables(year)
    t = theme_for(year)
    <<~CSS
      :root {
        --color-bg:      #{t[:bg]};
        --color-surface: #{t[:surface]};
        --color-text:    #{t[:text]};
        --color-accent:  #{t[:accent]};
        --color-heading: #{t[:heading]};
      }
    CSS
  end

  def theme_name(year)
    THEMES.dig(year.to_i, :name)
  end
end
