require "test_helper"
require_relative "locale_files_test"

# The code and the English texts match: every key the code names exists, and
# every text is still read somewhere. A static scan of the string literals of
# app/, lib/ and config/ (no new gem):
# - keys written in full: "servers.index.title";
# - lazy keys of the views and controllers: t(".title") in servers/_row is
#   servers.row.title, in a controller <controller_path>.<action>.title;
# - keys of the JavaScript: t("clipboard.copied") is js.clipboard.copied;
# - keys built at run time: "activity.kinds.#{kind}.label" stands for every
#   key it can give (activity.kinds.<anything>.label).
class LocaleUsageTest < ActiveSupport::TestCase
  ROOT = Rails.root.to_s

  # Read by Rails, Devise or rails-i18n themselves, never named in the code.
  FRAMEWORK = %w[activerecord. activemodel. errors. devise. date. time. number. datetime. helpers. support. i18n. elio.language_name].freeze

  PLURAL_FORMS = LocaleFilesTest::PLURAL_KEYS

  # A literal is the key of a t() call: t("a"), t(cond ? "a" : "b").
  TRANSLATED = /(?<![\w.])t\((?:\s*|[^(),]*\?\s*|[^(),]*\?\s*["'][^"']*["']\s*:\s*)\z/

  # The string literals of a source (and of their interpolations), with
  # the text before them and their offset; an interpolation ("#{…}" or
  # "${…}") is a nil part: [[parts, before, offset]].
  def self.literals(source, found = [], base = nil)
    scanner = StringScanner.new(source)
    until scanner.eos?
      quote = scanner.scan_until(/(?<!\w)["'`]/)&.[](-1) or break
      start = scanner.pos
      offset = base || scanner.charpos
      before = source[[ scanner.charpos - 120, 0 ].max...scanner.charpos - 1]
      parts = [ +"" ]
      closed = false
      until scanner.eos?
        char = scanner.getch
        break closed = true if char == quote
        break if char == "\n" # not a string: an apostrophe in a comment

        if char == "\\"
          parts[-1] << scanner.getch.to_s
        elsif quote != "'" && (char == "#" || char == "$") && scanner.peek(1) == "{"
          scanner.getch
          code = interpolation(scanner)
          literals(code, found, offset)
          parts.push(nil, +"")
        else
          parts[-1] << char
        end
      end
      closed ? found << [ parts, before, offset ] : scanner.pos = start
    end
    found
  end

  # The code of an interpolation, up to its closing brace.
  def self.interpolation(scanner)
    code = +""
    depth = 1
    until scanner.eos?
      char = scanner.getch
      depth += 1 if char == "{"
      depth -= 1 if char == "}"
      break if depth.zero?

      code << char
    end
    code
  end

  # [exact keys, patterns of the keys built at run time, { key => asked by a
  # t() call }] named by the code.
  def self.used
    @used ||= begin
      exact = Set.new
      named = {}
      patterns = []
      Dir[File.join(ROOT, "{app,lib,config}", "**", "*.{rb,erb,js,yml}")].each do |path|
        next if path.start_with?(Elio::Locales::DIRECTORY)

        source = File.read(path)
        source = source.scan(/<%=?(.*?)-?%>/m).join("\n") if path.end_with?(".erb") # the Ruby of a template
        source = source.gsub(%r{^\s*(//|#(?!\{)).*$}, "") # examples in comments
        own_t = source.match?(/def (self\.)?t\(/) # a t() of its own, under a scope of the texts
        scopes = lazy_scopes(path, source)
        literals(source).each do |parts, before, offset|
          translated = !own_t && before.match?(TRANSLATED)
          text = parts.first.to_s
          if text.start_with?(".") && translated
            scope = scopes.call(offset) or next
            parts = [ "#{scope}#{text}", *parts.drop(1) ]
          elsif path.end_with?(".js")
            parts = [ "js.#{text}", *parts.drop(1) ]
          end
          # A key starts with its scope: "#{base}.title" names no key we can tell.
          next unless parts.first.match?(parts.size > 1 ? /\A[a-z][a-z0-9_]*\./ : /\A[a-z]/) && (translated || parts.first.include?("."))

          if parts.size > 1
            patterns << /\A#{parts.map { _1 ? Regexp.escape(_1) : ".+" }.join}\z/
          elsif parts.first.match?(/\A[a-z0-9_]+(\.[a-z0-9_]+)*\z/)
            exact << parts.first
            named[parts.first] ||= translated if translated || !path.end_with?(".js")
          end
        end
      end
      [ exact, patterns, named ]
    end
  end

  # A proc giving the lazy scope at an offset of the file: a view's is its
  # path ("servers/_row" → "servers.row"), a controller's its
  # controller_path and the action the offset is in.
  def self.lazy_scopes(path, source)
    relative = path.delete_prefix(ROOT + "/")
    if relative.start_with?("app/views/")
      scope = relative.delete_prefix("app/views/").sub(/\..*\z/, "").sub(%r{/_([^/]+)\z}, '/\1').tr("/", ".")
      ->(_) { scope }
    elsif relative.start_with?("app/controllers/") && (name = controller_name(source))
      scope = name.constantize.controller_path.tr("/", ".")
      ->(offset) { (action = source[0...offset].scan(/^\s*def (\w+)/).flatten.last) && "#{scope}.#{action}" }
    else
      ->(_) { nil }
    end
  end

  def self.controller_name(source)
    names = source.scan(/^\s*(?:module|class) ([A-Z]\w*(?:::\w+)*)/).flatten
    index = names.index { |name| name.end_with?("Controller") }
    names.first(index + 1).join("::") if index
  end

  def self.english_keys = @english_keys ||= LocaleFilesTest.texts(:en).keys

  test "every key named by the code exists in English" do
    keys = self.class.english_keys.to_set
    scopes = keys.map { _1.split(".").first }.to_set
    _, _, named = self.class.used
    missing = named.filter_map do |key, translated|
      # A literal outside t() may be anything else ("config.active_job", "user.email").
      next if !translated && (key.count(".") < 2 || !scopes.include?(key.split(".").first))
      # A plural form, or the start of keys (a scope, a prefix matched by the code).
      next if key.start_with?(*FRAMEWORK) || keys.include?(key.sub(/\.(#{PLURAL_FORMS.join("|")})\z/, "")) || keys.any? { _1.start_with?(key) }

      key
    end
    assert_empty missing.sort, "named by the code but missing in config/locales/en"
  end

  test "every English text is used by the code" do
    exact, patterns, = self.class.used
    unused = self.class.english_keys.reject do |key|
      key.start_with?(*FRAMEWORK) || exact.include?(key) || PLURAL_FORMS.any? { exact.include?("#{key}.#{_1}") } ||
        exact.any? { key.start_with?("#{_1}.") } || # a scope kept in a variable: scope = "keys.access_extension"
        patterns.any? { _1.match?(key) }
    end
    assert_empty unused.sort, "in config/locales but read nowhere: remove them (from every language)"
  end

  test "the scan reads lazy keys, ternaries, interpolations and keys inside them" do
    literals = self.class.literals(%q{t(ok ? ".a" : ".b") + "x #{t("words.c")}" + t("cron.#{key}.d") + it's})
    assert_equal [ [ ".a" ], [ ".b" ], [ "words.c" ], [ "x ", nil, "" ], [ "cron.", nil, ".d" ] ], literals.map(&:first)
  end
end
