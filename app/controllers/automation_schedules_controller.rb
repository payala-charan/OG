class AutomationSchedulesController < ApplicationController
  before_action :set_schedule, only: [:destroy]
  before_action :set_batch, only: [:show]

  def index
    @active_portal = params[:type] || 'utilization'
    @schedules = AutomationSchedule.where(schedule_type: @active_portal).order(created_at: :desc)
    @batches = AutomationBatch.includes(:automation_schedule).where(batch_type: @active_portal).order(created_at: :desc).limit(20)
    @schedule = AutomationSchedule.new(schedule_type: @active_portal)
  end

  def show
    # Show granular details of a specific batch run
    @items = @batch.automation_batch_items.order(created_at: :asc)
    
    # Calculate group-level metrics
    @metrics_by_group = @items.group_by(&:generic_name_group).map do |group, items|
      {
        group: group,
        total: items.size,
        completed: items.count { |i| i.status == 'completed' },
        failed: items.count { |i| i.status == 'failed' },
        pending: items.count { |i| !['completed', 'failed'].include?(i.status) }
      }
    end
  end

  def create
    time_val = params[:automation_schedule][:time_of_day]
    frequency_val = params[:automation_schedule][:frequency]
    schedule_type_val = params[:automation_schedule][:schedule_type] || 'utilization'

    begin
      parsed_time = Time.parse(time_val)
      
      base_date = Date.current
      base_date = base_date + 1.day if Time.current > Time.current.change(hour: parsed_time.hour, min: parsed_time.min)
      
      next_run = case frequency_val.downcase
                 when 'daily' then base_date
                 when 'weekly' then base_date.end_of_week
                 when 'monthly' then base_date.end_of_month
                 else base_date
      end
                
      next_run_at = next_run.change(hour: parsed_time.hour, min: parsed_time.min)

      @schedule = AutomationSchedule.new(
        frequency: frequency_val,
        time_of_day: time_val,
        next_run_at: next_run_at,
        active: true,
        schedule_type: schedule_type_val,
        user_id: current_user&.id || 10130
      )

      if @schedule.save
        redirect_to automation_schedules_path(type: schedule_type_val), notice: "Automation routine scheduled successfully."
      else
        redirect_to automation_schedules_path(type: schedule_type_val), alert: "Error scheduling routine."
      end
    rescue ArgumentError
      redirect_to automation_schedules_path(type: schedule_type_val), alert: "Invalid time format provided."
    end
  end

  def destroy
    schedule_type = @schedule.schedule_type
    @schedule.destroy
    redirect_to automation_schedules_path(type: schedule_type), notice: "Routine disabled and deleted."
  end

  private

  def set_schedule
    @schedule = AutomationSchedule.find(params[:id])
  end

  def set_batch
    @batch = AutomationBatch.find(params[:id])
  end
end
