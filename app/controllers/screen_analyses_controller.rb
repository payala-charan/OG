class ScreenAnalysesController < ApplicationController
  before_action :set_screen_analysis, only: [:destroy]

  def index
  end

  def new
    @screen_analysis = ScreenAnalysis.new
    @team_id = params[:team_id] || "198"
  end

  def show
    @team_id = params[:id]
    @team_name = @team_id.to_s == "198" ? "Riverside" : "St Charles"
    @screen_analyses = ScreenAnalysis.where(team_id: @team_id).recent
  end

  def create
    @screen_analysis = ScreenAnalysis.new(screen_analysis_params)
    team_id = @screen_analysis.team_id || "198"

    if @screen_analysis.save
      flash[:notice] = "Screen analysis added successfully."
      redirect_to screen_analysis_path(team_id)
    else
      @team_id = team_id
      flash.now[:alert] = "Please fill all required fields and upload an image."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    team_id = @screen_analysis.team_id || "198"
    @screen_analysis.destroy
    flash[:notice] = "Screen analysis deleted successfully."
    redirect_to screen_analysis_path(team_id)
  end

  private

  def set_screen_analysis
    @screen_analysis = ScreenAnalysis.find(params[:id])
  end

  def screen_analysis_params
    params.require(:screen_analysis).permit(:title, :summary, :image, :team_id)
  end
end
