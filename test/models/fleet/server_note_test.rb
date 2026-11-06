require "test_helper"

class ServerNoteTest < ActiveSupport::TestCase
  def note(body, user: users(:viewer)) = ServerNote.new(server: servers(:web), user: user, body: body)

  test "a body is required, trimmed, and limited" do
    assert_not note("   ").valid?
    assert_equal "x", note("  x \n").tap(&:validate).body
    assert_not note("a" * (ServerNote::MAX_LENGTH + 1)).valid?
    assert note("a" * ServerNote::MAX_LENGTH).valid?
  end

  test "Markdown: formatting, lists, code, tables, autolinks" do
    html = note("# Role\n\n**Web** front, `nginx`\n\n- one\n- two\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nDocs: https://example.com/doc\n\n~~old~~").html
    assert_includes html, "<h1>Role</h1>"
    assert_includes html, "<strong>Web</strong>"
    assert_includes html, "<code>nginx</code>"
    assert_includes html, "<li>one</li>"
    assert_includes html, "<td>2</td>"
    assert_includes html, %(<a href="https://example.com/doc" rel="noopener noreferrer nofollow" target="_blank">https://example.com/doc</a>)
    assert_includes html, "<del>old</del>"
    assert html.html_safe?
  end

  test "no raw HTML, no script, no event handler, no image, no dangerous link" do
    html = note(<<~MD).html
      <script>alert(1)</script>
      <img src=x onerror=alert(2)>
      <a href="javascript:alert(3)">x</a> <b onclick="alert(4)">b</b>
      [js](javascript:alert(5)) [data](data:text/html,<script>alert(6)</script>) [vb](vbscript:x)
      ![tracker](https://evil.example/pixel.png)
      <iframe src="https://evil.example"></iframe> <style>body{display:none}</style>

      Text <b onclick="alert(7)">bold</b> [js](javascript:alert(8)) ![tracker](https://evil.example/pixel.png) [mail](mailto:ops@example.com)
    MD
    %w[<script <img <iframe <style onerror onclick javascript: data: vbscript: evil.example].each do |bad|
      assert_not_includes html, bad, bad
    end
    assert_includes html, %(<a href="mailto:ops@example.com" rel="noopener noreferrer nofollow" target="_blank">mail</a>)
    assert_includes html, "bold"
    assert_includes html, "js"
  end

  test "code blocks keep their content as text" do
    assert_includes note("```\n<b>x</b>\n```").html, "&lt;b&gt;x&lt;/b&gt;"
  end

  test "excerpt: plain text on one line" do
    assert_equal "Role Web front, nginx", note("# Role\n\n**Web** front, `nginx`").excerpt
    assert_equal 50, note("a " * 100).excerpt(50).size
  end

  test "the author edits and deletes; an admin deletes any note" do
    mine = note("x", user: users(:viewer))
    assert mine.editable_by?(users(:viewer))
    assert mine.deletable_by?(users(:viewer))
    assert_not mine.editable_by?(users(:operator))
    assert_not mine.deletable_by?(users(:operator))
    assert_not mine.editable_by?(users(:one)), "an admin does not rewrite someone else's note"
    assert mine.deletable_by?(users(:one))
    assert_not note("x", user: nil).editable_by?(nil)
  end
end
