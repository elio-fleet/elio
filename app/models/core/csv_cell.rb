# A value written into a CSV export: a list joined with spaces, and a text
# that a spreadsheet would run as a formula (starts with = + - @, a tab or a
# carriage return) prefixed with a quote, so opening an export never runs
# what a server or a feed wrote into it.
#
#   CsvCell.safe("=HYPERLINK(…)") # => "'=HYPERLINK(…)"
module CsvCell
  FORMULA_START = /\A[=+\-@\t\r]/

  def self.safe(value)
    value = value.join(" ") if value.is_a?(Array)
    value.is_a?(String) && value.match?(FORMULA_START) ? "'#{value}" : value
  end
end
