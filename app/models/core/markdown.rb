# Markdown written by users (server notes): CommonMark with tables,
# strikethrough and autolinks, rendered without raw HTML, then sanitized
# with a short list of tags. Images are dropped (no request to another
# site when a page is shown), links get rel="noopener noreferrer nofollow".
module Markdown
  OPTIONS = {
    render: { unsafe: false, hardbreaks: true },
    extension: { table: true, strikethrough: true, autolink: true, tagfilter: true, tasklist: false, header_ids: nil, footnotes: false },
    parse: { smart: false }
  }.freeze
  TAGS = %w[p br strong em del code pre blockquote ul ol li a h1 h2 h3 h4 h5 h6 hr table thead tbody tr th td].freeze
  ATTRIBUTES = %w[href].freeze
  LINK_SCHEMES = %w[http https mailto].freeze

  def self.html(text)
    rendered = Commonmarker.to_html(text.to_s, options: OPTIONS, plugins: { syntax_highlighter: nil })
    clean = Rails::HTML5::SafeListSanitizer.new.sanitize(rendered, tags: TAGS, attributes: ATTRIBUTES)
    fragment = Nokogiri::HTML5.fragment(clean)
    fragment.css("a").each do |link|
      href = link["href"].to_s
      if href.blank? || !LINK_SCHEMES.include?(URI.parse(href).scheme.to_s.downcase)
        link.replace(link.children)
      else
        link["rel"] = "noopener noreferrer nofollow"
        link["target"] = "_blank"
      end
    rescue URI::InvalidURIError
      link.replace(link.children)
    end
    fragment.to_html.html_safe # rubocop:disable Rails/OutputSafety -- sanitized just above
  end

  def self.text(text) = Nokogiri::HTML5.fragment(html(text)).text
end
