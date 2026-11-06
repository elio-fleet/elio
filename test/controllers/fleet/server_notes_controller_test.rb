require "test_helper"

class ServerNotesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def add(body, user: users(:viewer)) = servers(:web).notes.create!(body: body, user: user)

  test "requires authentication" do
    post server_notes_path(servers(:web)), params: { server_note: { body: "x" } }
    assert_redirected_to new_user_session_path
  end

  test "every role adds a note, logged as an activity" do
    sign_in users(:viewer)
    assert_difference -> { servers(:web).notes.count } => 1, -> { Activity.of_kind(:server_note_added).count } => 1 do
      post server_notes_path(servers(:web)), params: { server_note: { body: "Front **nginx**, see https://wiki.example/web" } }
    end
    assert_redirected_to server_path(servers(:web), tab: "notes")
    note = servers(:web).notes.sole
    assert_equal users(:viewer), note.user
    activity = Activity.of_kind(:server_note_added).sole
    assert_equal users(:viewer), activity.user
    assert_equal "Note sur « Web » par viewer@example.com : Front nginx, see https://wiki.example/web", activity.summary
    assert_equal :info, activity.severity
  end

  test "an empty note is refused" do
    sign_in users(:viewer)
    assert_no_difference -> { ServerNote.count } do
      post server_notes_path(servers(:web)), params: { server_note: { body: "  " } }
    end
    assert_redirected_to server_path(servers(:web), tab: "notes")
    assert flash[:alert].present?
  end

  test "the Notes tab: newest first, rendered, actions by owner and admin, paginated" do
    old = add("Old **note**", user: users(:operator))
    travel 1.minute
    mine = add("<script>alert(1)</script> mine")
    sign_in users(:viewer)

    get server_path(servers(:web), tab: "notes")
    assert_select "nav.server-tabs .server-tabs-bar a[data-tab=notes][aria-current=page]", text: /Notes\s*2/
    assert_select "#server-notes form.note-form[action=?] textarea[name='server_note[body]']", server_notes_path(servers(:web))
    assert_select "article.server-note", 2
    assert_select "turbo-frame##{ActionView::RecordIdentifier.dom_id(mine)} article.server-note" do
      assert_select ".note-author", "viewer@example.com"
      assert_select "a.edit-note[href=?]", edit_server_note_path(servers(:web), mine)
      assert_select "form button.delete-note"
      assert_select ".note-body script", 0
    end
    assert_select "turbo-frame##{ActionView::RecordIdentifier.dom_id(old)}" do
      assert_select ".note-body strong", "note"
      assert_select "a.edit-note", 0
      assert_select "button.delete-note", 0
    end
    assert_select "ul.server-notes > li:first-child turbo-frame##{ActionView::RecordIdentifier.dom_id(mine)}"

    sign_in users(:one)
    get server_path(servers(:web), tab: "notes")
    assert_select "button.delete-note", 2, "an admin deletes any note"
    assert_select "a.edit-note", 0
  end

  test "the author edits a note in place" do
    note = add("Before")
    sign_in users(:viewer)
    get edit_server_note_path(servers(:web), note), headers: { "Turbo-Frame" => ActionView::RecordIdentifier.dom_id(note) }
    assert_select "turbo-frame##{ActionView::RecordIdentifier.dom_id(note)} form.note-form[action=?] textarea", server_note_path(servers(:web), note), text: "Before"

    patch server_note_path(servers(:web), note), params: { server_note: { body: "After" } }
    assert_redirected_to server_path(servers(:web), tab: "notes")
    assert_equal "After", note.reload.body

    patch server_note_path(servers(:web), note), params: { server_note: { body: "" } }
    assert_response :unprocessable_content
    assert_equal "After", note.reload.body
  end

  test "someone else cannot edit or delete a note, an admin can delete it" do
    note = add("Viewer's")
    sign_in users(:operator)
    get edit_server_note_path(servers(:web), note)
    assert_response :forbidden
    patch server_note_path(servers(:web), note), params: { server_note: { body: "Hacked" } }
    assert_response :forbidden
    delete server_note_path(servers(:web), note)
    assert_response :forbidden
    assert_equal "Viewer's", note.reload.body

    sign_in users(:one)
    patch server_note_path(servers(:web), note), params: { server_note: { body: "Hacked" } }
    assert_response :forbidden
    delete server_note_path(servers(:web), note)
    assert_redirected_to server_path(servers(:web), tab: "notes")
    assert_not ServerNote.exists?(note.id)
  end

  test "a note of another server is not found" do
    note = servers(:db).notes.create!(body: "db", user: users(:viewer))
    sign_in users(:viewer)
    delete server_note_path(servers(:web), note)
    assert_response :not_found
  end

  test "preview renders the Markdown, sanitized, in the frame asked" do
    sign_in users(:viewer)
    post preview_server_notes_path(servers(:web)), params: { server_note: { body: "**b** <img src=x onerror=alert(1)>" } }, headers: { "Turbo-Frame" => "note-preview-12" }
    assert_response :success
    assert_select "turbo-frame#note-preview-12 .note-preview strong", "b"
    assert_select "img", 0

    post preview_server_notes_path(servers(:web)), params: { server_note: { body: "" } }, headers: { "Turbo-Frame" => "x\" onload=\"alert(1)" }
    assert_select "turbo-frame#note-preview-new", text: /Rien à afficher/
  end

  test "deleting a server deletes its notes" do
    add("x")
    assert_difference -> { ServerNote.count }, -1 do
      servers(:web).destroy!
    end
  end
end
