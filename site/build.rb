#!/usr/bin/env ruby
# Builds the website of Elio (GitHub Pages) into _site/: English at the root,
# French in fr/. Plain Ruby and ERB, no Rails: each page template holds both
# languages side by side (t(en: …, fr: …)). It reads the commands Elio runs
# from config/ssh_commands.yml, the version from lib/elio/version.rb and the
# screenshots from docs/screenshots. The CSS is compiled afterwards by bin/site.
require "erb"
require "fileutils"
require "yaml"
require_relative "../lib/elio/version"

ROOT = File.expand_path("..", __dir__)
SITE = File.join(ROOT, "site")
OUT = ENV.fetch("ELIO_SITE_OUT", File.join(ROOT, "_site"))
REPOSITORY = "https://github.com/elio-fleet/elio"
URL = "https://elio-fleet.github.io/elio"
LANGUAGES = %w[en fr].freeze
PAGES = %w[index features install security faq].freeze

# Heroicons paths of the application (app/helpers/icons_helper.rb), read as data.
ICONS_SOURCE = File.read(File.join(ROOT, "app/helpers/icons_helper.rb"))
# Logos drawn with fill (IconsHelper::FILLED_ICONS), the others with stroke.
FILLED_ICONS = ICONS_SOURCE[/FILLED_ICONS = \{(.*?)\}/m, 1].scan(/^\s+(\w+): "([^"]+)",?$/).to_h
ICONS = ICONS_SOURCE.scan(/^\s+(\w+): "([^"]+)",?$/).to_h.except(*FILLED_ICONS.keys)

COMMANDS = YAML.safe_load_file(File.join(ROOT, "config/ssh_commands.yml")).flat_map do |role, commands|
  commands.map do |name, spec|
    { key: "#{role}.#{name}", description: spec["description"], root: spec["run_as"] == "root", writes: spec["writes"] == true,
      variants: spec.keys - %w[description writes run_as timeout shell], script: spec["debian"] || spec["default"] }
  end
end

class Page
  include ERB::Util

  attr_reader :language, :name

  def initialize(language, name)
    @language = language
    @name = name
  end

  def t(en:, fr:) = language == "fr" ? fr : en

  # Relative path to the root of the site (GitHub Pages serves it under /elio/).
  def root = language == "fr" ? "../" : ""

  # Link to a page, in this language or the other one (French lives in fr/).
  def link(page, language: self.language)
    file = page == "index" ? "" : "#{page}.html"
    return file.empty? ? "./" : file if language == self.language

    language == "fr" ? "fr/#{file}" : "../#{file}"
  end

  def other_language = language == "fr" ? "en" : "fr"

  def asset(path) = "#{root}assets/#{path}"

  def screenshot(name, alt, eager: false)
    width, height = png_size(File.join(ROOT, "docs/screenshots/#{language}/#{name}.png"))
    %(<img src="#{asset("screenshots/#{language}/#{name}.#{SCREENSHOT_FORMAT}")}" alt="#{h(alt)}" width="#{width}" height="#{height}" class="screenshot" #{eager ? 'fetchpriority="high"' : 'loading="lazy"'} decoding="async">)
  end

  # Width and height of a PNG, read from its header (no image library needed).
  def png_size(path) = File.binread(path, 8, 16).unpack("NN")

  def icon(name, css = "h-5 w-5")
    if (filled = FILLED_ICONS[name.to_s])
      return %(<svg xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="0 0 24 24" class="#{css}" aria-hidden="true"><path d="#{filled}"/></svg>)
    end

    path = ICONS.fetch(name.to_s)
    %(<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="#{css}" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="#{path}"/></svg>)
  end

  def code(text, label: nil)
    %(<figure class="code">#{"<figcaption>#{h(label)}</figcaption>" if label}<pre><code>#{h(text.strip)}</code></pre></figure>)
  end

  def version = Elio::VERSION
  def repository = REPOSITORY
  def commands = COMMANDS

  def render(template)
    ERB.new(File.read(File.join(SITE, template)), trim_mode: "-").result(binding)
  end

  # Set by each page template: <% @title = …; @description = … %>.
  attr_reader :title, :description

  def html
    @content = render("pages/#{name}.html.erb")
    render("layout.html.erb")
  end

  attr_reader :content

  def canonical = "#{URL}/#{"fr/" if language == "fr"}#{name == "index" ? "" : "#{name}.html"}"
end

FileUtils.rm_rf(OUT)
LANGUAGES.each { |language| FileUtils.mkdir_p(File.join(OUT, "assets/screenshots", language)) }
FileUtils.mkdir_p(File.join(OUT, "fr"))

# Screenshots: WebP when cwebp is installed (much lighter), else the PNGs.
SCREENSHOT_FORMAT = ENV["ELIO_SITE_PNG"].nil? && system("command -v cwebp > /dev/null 2>&1") ? "webp" : "png"
Dir[File.join(ROOT, "docs/screenshots/*/*.png")].each do |source|
  target = File.join(OUT, "assets/screenshots", File.basename(File.dirname(source)), File.basename(source, ".png") + ".#{SCREENSHOT_FORMAT}")
  SCREENSHOT_FORMAT == "webp" ? system("cwebp", "-quiet", "-q", "82", source, "-o", target, exception: true) : FileUtils.cp(source, target)
end
FileUtils.cp(File.join(ROOT, "docs/brand/icon.svg"), File.join(OUT, "assets/icon.svg"))
FileUtils.cp(File.join(ROOT, "docs/brand/logo-light.svg"), File.join(OUT, "assets/logo-light.svg"))
FileUtils.cp(File.join(ROOT, "docs/brand/logo-dark.svg"), File.join(OUT, "assets/logo-dark.svg"))
FileUtils.cp(File.join(SITE, "assets/site.js"), File.join(OUT, "assets/site.js"))
system("cwebp", "-quiet", "-q", "85", "-resize", "1200", "0", File.join(ROOT, "docs/screenshots/en/fleet.png"), "-o", File.join(OUT, "assets/social.webp")) if SCREENSHOT_FORMAT == "webp"
FileUtils.cp(File.join(ROOT, "docs/screenshots/en/fleet.png"), File.join(OUT, "assets/social.png"))

LANGUAGES.product(PAGES).each do |language, name|
  page = Page.new(language, name)
  File.write(File.join(OUT, language == "fr" ? "fr" : "", "#{name == "index" ? "index" : name}.html"), page.html)
end

File.write(File.join(OUT, "sitemap.xml"), <<~XML)
  <?xml version="1.0" encoding="UTF-8"?>
  <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  #{LANGUAGES.product(PAGES).map { |language, name| "  <url><loc>#{Page.new(language, name).canonical}</loc></url>" }.join("\n")}
  </urlset>
XML
File.write(File.join(OUT, "robots.txt"), "User-agent: *\nAllow: /\nSitemap: #{URL}/sitemap.xml\n")
File.write(File.join(OUT, ".nojekyll"), "")
puts "Site built in #{OUT} (#{LANGUAGES.size * PAGES.size} pages, screenshots in #{SCREENSHOT_FORMAT})"
