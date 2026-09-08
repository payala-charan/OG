class ProductRankingsController < ApplicationController
  def index
    # Step 1: Base query
    @product_rankings = ProductRanking.all

    # Step 2: Apply filters
    @product_rankings = @product_rankings.where(generic_name_group: params[:generic_name_group]) if params[:generic_name_group].present?
    @product_rankings = @product_rankings.where(team_id: params[:team_id]) if params[:team_id].present?
    @product_rankings = @product_rankings.where(accounting_period_id: params[:accounting_period_id]) if params[:accounting_period_id].present?
    @product_rankings = @product_rankings.where(payor: params[:payor]) if params[:payor].present?

    # Step 3: Compute dynamic options for each dropdown
    @available_generic_names = option_scope(:generic_name_group).distinct.pluck(:generic_name_group).compact.sort
    @available_teams = option_scope(:team_id).distinct.pluck(:team_id).compact.sort
    @available_periods = option_scope(:accounting_period_id).distinct.pluck(:accounting_period_id).compact.sort
    @available_payors = option_scope(:payor).distinct.pluck(:payor).compact.sort

    @product_rankings = @product_rankings.order(created_at: :desc)
  end

  private

  def option_scope(exclude_param)
    scope = ProductRanking.all
    scope = scope.where(generic_name_group: params[:generic_name_group]) if params[:generic_name_group].present? && exclude_param != :generic_name_group
    scope = scope.where(team_id: params[:team_id]) if params[:team_id].present? && exclude_param != :team_id
    scope = scope.where(accounting_period_id: params[:accounting_period_id]) if params[:accounting_period_id].present? && exclude_param != :accounting_period_id
    scope = scope.where(payor: params[:payor]) if params[:payor].present? && exclude_param != :payor
    scope
  end
end
