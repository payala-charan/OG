require 'net/http'
require 'fileutils'

class AutoRankingService
  def initialize(user_id:, team_id:, generic_name_group: nil, quarter: nil)
    @user_id = user_id
    @team_id = team_id || "209"
    @generic_name_group = generic_name_group
    @quarter = quarter
  end

  def call
    file_path = download_file
    uploaded_file = build_uploaded_file(file_path)
    trigger_validation(uploaded_file)
  end

  private

  # 🔹 Step 1: Call App1 API with query parameters
  def download_file
    url_string = build_api_url
    url = URI(url_string)
    response = Net::HTTP.get_response(url)

    raise "Download failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    folder_path = Rails.root.join("atm_files", "expanded_ranking")
    FileUtils.mkdir_p(folder_path)

    filename = extract_filename(response) || "expanded_ranking_#{Time.now.to_i}.xlsx"
    file_path = folder_path.join(filename)

    File.open(file_path, "wb") { |f| f.write(response.body) }

    file_path
  end

  # 🔹 Build API URL with query parameters
  def build_api_url
    url = "http://localhost:3000/api/export_expanded_rankings?user_id=#{@user_id}"
    url += "&group=#{ERB::Util.url_encode(@generic_name_group)}" if @generic_name_group.present?
    url += "&team_id=#{@team_id}" if @team_id.present?
    url += "&quarter=#{@quarter}" if @quarter.present?
    url
  end

  # 🔹 Step 2: Extract filename
  def extract_filename(response)
    disposition = response['content-disposition']
    return unless disposition

    match = disposition.match(/filename="(.+)"/)
    match[1] if match
  end

  # 🔹 Step 3: Convert to upload format
  def build_uploaded_file(file_path)
    ActionDispatch::Http::UploadedFile.new(
      tempfile: File.open(file_path),
      filename: File.basename(file_path),
      type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
  end

  # 🔥 Step 4: Trigger validation logic
  def trigger_validation(file)
    period_id =
      case @quarter.to_s
      when "5" then "5"
      when "4" then "5"
      when "1" then "2"
      when "2" then "3"
      else "4"
      end

    RankingProcessor.new(
      file: file,
      team_id: @team_id,
      period_id: period_id,
      user: User.find_by(id: @user_id),
      is_auto: true
    ).call
  end
end
