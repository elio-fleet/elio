require "test_helper"

class IconsHelperTest < ActionView::TestCase
  test "renders a decorative svg icon with default size" do
    render html: icon(:pencil_square)

    assert_select "svg.h-4.w-4[aria-hidden=true][viewBox='0 0 24 24'][stroke=currentColor]" do
      assert_select "path[d=?]", IconsHelper::ICONS[:pencil_square]
    end
  end

  test "accepts custom classes and attributes" do
    render html: icon(:arrow_path, class: "h-3 w-3 animate-spin", data: { test: "x" })

    assert_select "svg.animate-spin[data-test=x]"
    assert_select "svg.h-4", 0
  end

  test "a filled icon (the Docker whale) is drawn with fill, not stroke" do
    render html: icon(:docker, class: "h-3 w-3")
    assert_select "svg[fill=currentColor][class='h-3 w-3'][aria-hidden=true]:not([stroke]) path[d^='M2.2,9.76']"
  end

  test "raises on an unknown icon" do
    assert_raises(KeyError) { icon(:unknown) }
  end
end
