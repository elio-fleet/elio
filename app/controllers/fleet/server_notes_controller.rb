# Notes of a server (its Notes tab, see ServersController#show): every role
# writes them; their author edits or deletes them, an admin deletes any.
class ServerNotesController < ApplicationController
  before_action :set_server
  before_action :set_note, only: %i[edit update destroy]
  before_action -> { raise NotAuthorized unless @note.editable_by?(current_user) }, only: %i[edit update]
  before_action -> { raise NotAuthorized unless @note.deletable_by?(current_user) }, only: :destroy

  def create
    note = @server.notes.new(body: params.expect(server_note: [ :body ])[:body], user: current_user)
    if note.save
      Activity.record!(:server_note_added, server: @server, excerpt: note.excerpt)
      redirect_to notes_path, notice: t("server_notes_controller.added"), status: :see_other
    else
      redirect_to notes_path, alert: note.errors.full_messages.to_sentence, status: :see_other
    end
  end

  # In the note's frame (edited in place).
  def edit
  end

  def update
    if @note.update(body: params.expect(server_note: [ :body ])[:body])
      redirect_to notes_path(page: params[:page].presence), notice: t("server_notes_controller.updated"), status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @note.destroy!
    redirect_to notes_path, notice: t("server_notes_controller.deleted"), status: :see_other
  end

  # The Markdown of the form as it will be shown (in the preview frame).
  def preview
    @html = Markdown.html(params.dig(:server_note, :body).to_s.first(ServerNote::MAX_LENGTH))
    render layout: false
  end

  private

  def set_server
    @server = Server.find(params[:server_id])
  end

  def set_note
    @note = @server.notes.find(params[:id])
  end

  def notes_path(**params) = server_path(@server, tab: "journal", **params.compact)
end
