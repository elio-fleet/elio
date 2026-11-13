class PublicKeysController < ApplicationController
  PER_PAGE = 50

  require_permission :operate, only: %i[new create edit update destroy]

  before_action :set_public_key, only: %i[show edit update destroy]

  # Optional filter: ?kind=person|server.
  # ?kind=outside: the keys seen on the servers that are in no keyring key.
  def index
    @insights = KeyInsights.new
    if params[:kind] == "outside"
      @kind = "outside"
      @pager = paginate(@insights.outside_keys, per_page: PER_PAGE)
      @outside_keys = @pager.records
      @public_key_count = PublicKey.count
      return render :outside
    end

    @kind = params[:kind].presence_in(PublicKey::KINDS)
    public_keys = PublicKey.order(:name)
    public_keys = public_keys.of_kind(@kind) if @kind
    @pager = paginate(public_keys, per_page: PER_PAGE)
    @public_keys = @pager.records
  end

  def show
  end

  # Can be prefilled (e.g. from an unknown key of a server) with `content`,
  # `name`, `kind` and a local `return_to` path.
  def new
    @public_key = PublicKey.new(name: params[:name], content: params[:content], kind: params[:kind].presence_in(PublicKey::KINDS) || "person")
    @return_to = safe_return_to
  end

  def create
    @public_key = PublicKey.new(public_key_params)

    @return_to = safe_return_to

    if @public_key.save
      Activity.record!(:public_key_created, public_key: @public_key, fingerprint: @public_key.fingerprint)
      redirect_to @return_to || public_key_path(@public_key), notice: t("public_keys_controller.created", public_key_name: @public_key.name)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @public_key.update(public_key_params)
      redirect_to public_key_path(@public_key), notice: t("public_keys_controller.updated", public_key_name: @public_key.name)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @public_key.destroy!
    Activity.record!(:public_key_deleted, public_key_name: @public_key.name, fingerprint: @public_key.fingerprint)
    redirect_to public_keys_path, notice: t("public_keys_controller.deleted", public_key_name: @public_key.name), status: :see_other
  end

  private

  # Only local paths, to avoid redirecting to another site.
  def safe_return_to
    path = params[:return_to].to_s
    path if path.start_with?("/") && !path.start_with?("//") && !path.include?("\\")
  end

  def set_public_key
    @public_key = PublicKey.find(params[:id])
  end

  # The owner ("my key") is chosen by an administrator; users claim their own keys on their account page.
  def public_key_params
    params.expect(public_key: [ :name, :kind, :content, :description, *(:user_id if can?(:administer)) ])
  end
end
