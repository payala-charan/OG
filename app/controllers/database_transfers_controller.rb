# frozen_string_literal: true

class DatabaseTransfersController < ApplicationController
  def index
    load_recent_runs
    load_catalog(refresh: params[:refresh].present?)
    if params[:refresh].present? && !@connection_error
      redirect_to database_transfers_path, notice: "Table counts refreshed from #{@source_database}."
      return
    end

    render status: page_status
  end

  def analyze
    load_recent_runs
    load_catalog
    build_analysis unless @connection_error
    render :index, status: page_status
  end

  # Starts a transfer or a rehearsal of the plan the user reviewed.
  # The plan is rebuilt here from the table names alone; nothing else from
  # the form is trusted except the fingerprint it must match.
  def transfer
    load_recent_runs
    load_catalog
    build_analysis unless @connection_error
    return render(:index, status: page_status) unless @plan

    if (error = transfer_error)
      flash.now[:alert] = error
      @transfer_error = true
      return render(:index, status: :unprocessable_entity)
    end

    run = DatabaseTransferRun.create!(
      user: current_user,
      rehearsal: rehearsal?,
      source_database: @plan.source_database,
      target_database: @plan.target_database,
      selected_tables: @plan.selected_tables,
      planned_tables: @plan.table_names,
      plan_fingerprint: @plan.fingerprint,
      progress_message: "Waiting to start"
    )
    DatabaseTransfer::Dispatcher.start(run)
    redirect_to database_transfer_run_path(run),
                notice: rehearsal? ? "Rehearsal started. Nothing will be kept." : "Transfer started."
  end

  private

  def load_catalog(refresh: false)
    reset_catalog
    discovery = DatabaseTransfer::TableDiscovery.new
    @source_database = discovery.source_database
    @tables = discovery.tables_with_counts(refresh: refresh)
    @counts_by_name = @tables.to_h { |table| [ table[:name], table[:count] ] }
    known = @counts_by_name.keys
    requested = requested_table_names
    @selected_tables = requested.select { |name| known.include?(name) }.sort
    @ignored_tables = (requested - @selected_tables).sort
  rescue StandardError => error
    raise unless DatabaseTransfer::Source.read_error?(error)

    known_database = @source_database
    reset_catalog
    @connection_error = true
    @source_database = known_database.presence || unavailable_source_database
    flash.now[:alert] = "Could not read the FAT database. #{error.message}"
  end

  def build_analysis
    if @selected_tables.empty?
      @selection_error = true
      flash.now[:alert] = empty_selection_message
      return
    end

    known = @tables.map { |table| table[:name] }
    resolver = DatabaseTransfer::DependencyResolver.new
    @analysis = resolver.resolve(@selected_tables, known_tables: known)
    related_names = @analysis.referencing_tables.map(&:name)
    requested_related = requested_related_names
    @included_related = requested_related.select { |name| related_names.include?(name) }.sort
    @ignored_related = (requested_related - @included_related).sort
    @plan_analysis = if @included_related.empty?
      @analysis
    else
      resolver.resolve((@selected_tables + @included_related).uniq, known_tables: known)
    end
    @forced_related = related_names.select { |name| @plan_analysis.required?(name) }
    build_plan
    notice = analysis_notice
    flash.now[:notice] = notice if notice
  end

  def build_plan
    @plan = DatabaseTransfer::Planner.new.build(@plan_analysis, counts: @counts_by_name)
  rescue StandardError => error
    raise unless DatabaseTransfer::Source.read_error?(error)

    @plan = nil
    @plan_error = true
    flash.now[:alert] = "Could not build the transfer plan. #{error.message}"
  end

  def transfer_error
    unless @plan.transferable?
      return "This plan is blocked. Resolve the blocked tables listed below before transferring."
    end
    if params[:plan_fingerprint].to_s != @plan.fingerprint
      return "The FAT schema or the table list changed since you reviewed the plan. Review the updated plan and confirm again."
    end
    if !rehearsal? && params[:confirm_database].to_s.strip != @plan.target_database
      return "Type #{@plan.target_database} exactly to confirm the transfer."
    end
    if DatabaseTransferRun.active.exists?
      "Another transfer is already waiting or running. Wait for it to finish."
    end
  end

  def rehearsal?
    params[:rehearsal] == "1"
  end

  def load_recent_runs
    @recent_runs = DatabaseTransferRun.recent.includes(:user).limit(8)
  end

  def reset_catalog
    @tables = []
    @selected_tables = []
    @ignored_tables = []
    @included_related = []
    @forced_related = []
    @ignored_related = []
    @counts_by_name = {}
    @plan_analysis = nil
  end

  def requested_table_names
    name_list(:tables)
  end

  def requested_related_names
    name_list(:include_related)
  end

  def name_list(key)
    values = params[key]
    names = if values.is_a?(Array)
      values
    elsif values.is_a?(String)
      [ values ]
    else
      []
    end
    names.map { |name| name.to_s.strip }.compact_blank.uniq
  end

  def analysis_notice
    notes = []
    if @ignored_tables.any?
      notes << "Ignored names that are not tables in #{@source_database}: #{@ignored_tables.join(', ')}."
    end
    if @ignored_related.any?
      notes << "Ignored related tables that do not reference this selection: #{@ignored_related.join(', ')}."
    end
    notes.join(" ").presence
  end

  def empty_selection_message
    if @ignored_tables.any?
      "None of the chosen names are tables in #{@source_database}."
    else
      "Select at least one table before analyzing dependencies."
    end
  end

  def unavailable_source_database
    FatRecord.connection_db_config.database
  rescue StandardError
    "unavailable"
  end

  def page_status
    return :service_unavailable if @connection_error
    return :unprocessable_entity if @selection_error
    return :service_unavailable if @plan_error

    :ok
  end
end
