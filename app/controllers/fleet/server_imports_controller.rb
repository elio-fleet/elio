# Imports servers from a CSV file, an ~/.ssh/config extract or the servers
# the extensions know (OVHcloud, Coolify): `preview` parses and shows what
# would happen, the rows in error can be corrected there and checked again,
# `create` checks the same rows again and creates the valid ones (nothing is
# kept on the server between the steps).
class ServerImportsController < ApplicationController
  require_permission :operate

  ROW_FIELDS = %w[line name host port username groups].freeze

  before_action :load_candidates, only: %i[new preview]

  def new
    @format = "csv"
    @default_username = "root"
  end

  def preview
    read_params
    @rows = parse_rows
    render :new
  rescue Servers::Import::Error => e
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end

  def create
    read_params
    servers = Servers::Import.import!(parse_rows)
    return redirect_to(new_server_import_path, alert: t("server_imports_controller.nothing")) if servers.empty?

    Activity.record!(:servers_imported, count: servers.size, format: Servers::Import::FORMATS.fetch(@format), names: servers.first(10).map(&:name))
    if params[:collect_inventory] == "1"
      servers.each { |server| Inventory::FirstCollectJob.perform_later(server) }
      redirect_to servers_path, notice: t("server_imports_controller.imported_and_collecting", count: servers.size)
    else
      redirect_to servers_path, notice: t("server_imports_controller.imported", count: servers.size)
    end
  rescue Servers::Import::Error => e
    redirect_to new_server_import_path, alert: e.message
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    redirect_to new_server_import_path, alert: t("server_imports_controller.cancelled", message: e.message)
  end

  private

  def load_candidates
    @candidates = Servers::ExtensionCandidates.call
  end

  def read_params
    @format = Servers::Import::FORMATS.key?(params[:import_format]) ? params[:import_format] : "csv"
    @default_username = params[:default_username].to_s.strip.presence || "root"
    @text = if params[:source] == "extensions"
      @format = "csv"
      Servers::ExtensionCandidates.csv(@candidates || Servers::ExtensionCandidates.call)
    elsif params[:file].respond_to?(:read)
      params[:file].read(Servers::Import::MAX_SIZE + 1)
    else
      params[:content].to_s
    end
    @includes = @format == "ssh_config" ? Servers::Import.ssh_config_includes(@text).uniq : []
  end

  # The rows of the preview when it is sent back (corrected, or confirmed),
  # else the text.
  def parse_rows
    rows = params.permit(rows: ROW_FIELDS)[:rows]&.to_h&.values&.sort_by { |row| row["line"].to_i }
    return Servers::Import.from_rows(rows, default_username: @default_username) if rows

    Servers::Import.parse(@text, format: @format, default_username: @default_username)
  end
end
