# frozen_string_literal: true

class DatabaseTransferRunsController < ApplicationController
  def index
    @runs = DatabaseTransferRun.recent.includes(:user).limit(50)
  end

  def show
    @run = DatabaseTransferRun.find(params[:id])
  end

  def rollback
    @run = DatabaseTransferRun.find(params[:id])
    unless params[:confirm_database].to_s.strip == @run.target_database
      redirect_to database_transfer_run_path(@run, anchor: "rollback"),
                  alert: "Type #{@run.target_database} exactly to roll back these tables."
      return
    end

    DatabaseTransfer::Rollback.new(@run).call
    redirect_to database_transfer_run_path(@run),
                notice: "Rolled back #{@run.planned_tables.size} table(s). They were dropped from #{@run.target_database}."
  rescue DatabaseTransfer::Rollback::Blocked => error
    redirect_to database_transfer_run_path(@run), alert: error.message
  end
end
