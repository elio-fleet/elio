require "test_helper"

class CsvCellTest < ActiveSupport::TestCase
  test "a text a spreadsheet would run as a formula is quoted, the rest stays" do
    %w[=1+1 +1 -1 @SUM(A1)].each { |value| assert_equal "'#{value}", CsvCell.safe(value) }
    assert_equal "'\tx", CsvCell.safe("\tx")
    assert_equal "web-1", CsvCell.safe("web-1")
    assert_equal(-3, CsvCell.safe(-3), "a number is not text")
    assert_nil CsvCell.safe(nil)
    assert_equal "a b", CsvCell.safe(%w[a b])
  end
end
