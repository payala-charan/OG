class Api::AutoRankingsController < ApplicationController
  def validate
    user_id = params[:user_id] || (current_user&.id rescue 10130) || 10130
    generic_name_group = params[:generic_name_group]
    team_id = params[:team_id] || "209"
    quarter = params[:quarter]

    validate_parameters(generic_name_group, team_id, quarter)

    result = AutoRankingService.new(
      user_id: user_id,
      team_id: team_id,
      generic_name_group: generic_name_group,
      quarter: quarter
    ).call

    if result[:success]
      render json: { 
        message: "✅ Auto ranking validation completed successfully",
        params: {
          user_id: user_id,
          generic_name_group: generic_name_group,
          team_id: team_id,
          quarter: quarter
        }
      }
    else
      render json: { error: result[:error] }, status: 400
    end

  rescue ArgumentError => e
    render json: { error: e.message }, status: 400
  rescue => e
    render json: { error: e.message }, status: 500
  end

  private

  def validate_parameters(generic_name_group, team_id, quarter)
    valid_groups = ["Bendamustine", "Bevacizumab", "Filgrastim", "Infliximab", 
                   "Pegfilgrastim", "Rituximab", "Trastuzumab", "Tocilizumab", 
                   "Leuprolide Acetate", "Denosumab"]
    
    valid_teams = ["198", "209"]
    valid_quarters = ["1", "2", "3", "4", "5"]

    raise ArgumentError, "Invalid generic_name_group" unless valid_groups.include?(generic_name_group)
    raise ArgumentError, "Invalid team_id" unless valid_teams.include?(team_id.to_s)
    raise ArgumentError, "Invalid quarter" unless valid_quarters.include?(quarter.to_s)
  end
end
