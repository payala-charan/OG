class BiosimilarPricesController < ApplicationController
  include Pagy::Backend

  COMBINED_GROUPS = ["HYALURONATE SODIUM", "LEUPROLIDE ACETATE"]
 
  def index
   filters_active = params[:generic_name].present? || params[:accounting_period_id].present?
 
   biosimilar_prices = BiosimilarPrice.where(team_id: current_user.team_id).order(updated_at: :desc)
 
   if filters_active
     biosimilar_prices = biosimilar_prices.where(generic_name: params[:generic_name]) if params[:generic_name].present?
     biosimilar_prices = biosimilar_prices.where(accounting_period_id: params[:accounting_period_id]) if params[:accounting_period_id].present?
     @pagy, @biosimilar_prices = pagy(biosimilar_prices, items: 50)
   else
     @pagy, @biosimilar_prices = pagy(BiosimilarPrice.none, items: 50)
   end
 
   @generic_names = BiosimilarPrice.where(team_id: current_user.team_id).distinct.pluck(:generic_name).compact.sort
   @accounting_periods = AccountingPeriod.order(:id).pluck(:name, :id)
  end
 
  def edit
   @biosimilar_price = find_authorized_record
   @biosimilar_price.team_id = current_user.team_id
   @accounting_periods = AccountingPeriod.order(:id).pluck(:name, :id)
   @reimbursements = Reimbursement.order(:id).pluck(:name, :id) if defined?(Reimbursement)
  end
 
  def update
   @biosimilar_price = find_authorized_record
 
   if @biosimilar_price.update(biosimilar_price_params.merge(team_id: current_user.team_id))
     flash[:success] = 'Biosimilar price updated successfully'
     redirect_to biosimilar_prices_path
   else
     flash[:error] = 'Failed to update biosimilar price: ' + @biosimilar_price.errors.full_messages.join(', ')
     @accounting_periods = AccountingPeriod.order(:id).pluck(:name, :id)
     @reimbursements = Reimbursement.order(:id).pluck(:name, :id) if defined?(Reimbursement)
     render :edit
   end
  end
 
  def biosimilar_price_bulk_upload
   BiosimilarPrice.process_file(biosmiliar_price_upload_file)
   flash[:success] = 'Biosimilar Price File successfully uploaded'
   redirect_back(fallback_location: root_path)
  end
 
  def biosmiliar_price_upload_file
   BiosimilarPrice.open_spreadsheet(params[:biosimilar_price][:file])
  end
 
  def generate_biosimilar_prices
    # Display the upload form page
    @accounting_periods = AccountingPeriod.order(:id).pluck(:name, :id)
  end
 
  def process_biosimilar_generation
   begin
    file = params[:generation_file][:file]
    quarter_id = params[:quarter]
 
    if file.blank?
     flash[:error] = 'Please select a file to upload'
     redirect_to generate_biosimilar_prices_path and return
    end
 
    if quarter_id.blank?
     flash[:error] = 'Please select a quarter'
     redirect_to generate_biosimilar_prices_path and return
    end
 
    accounting_period = AccountingPeriod.find(quarter_id)
 
    include_blended_costs = params[:include_blended_costs].to_s == '1'
 
    # Open the uploaded file
    spreadsheet = BiosimilarPrice.open_spreadsheet(file)
 
    # Process the file and generate complete biosimilar data
    xlsx_data = generate_complete_biosimilar_sheet(
      spreadsheet,
      accounting_period,
      include_blended_costs: include_blended_costs
    )
 
  # Use custom filename if provided, otherwise use default
    final_filename = if params[:custom_filename].present?
             custom_name = params[:custom_filename].strip
             custom_name.end_with?('.xlsx') ? custom_name : "#{custom_name}.xlsx"
            else
             "Complete_Biosimilar_Prices_#{Time.now.strftime('%Y-%m-%d')}.xlsx"
            end
 
    send_data xlsx_data.read,
         type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
         filename: final_filename,
         disposition: 'attachment'
 
   rescue ActiveRecord::RecordNotFound
    flash[:error] = 'Invalid quarter selected'
    redirect_to generate_biosimilar_prices_path 
 
   rescue => e
    flash[:error] = "Error processing file: #{e.message}"
    redirect_to generate_biosimilar_prices_path
   end
  end
 
  private
 
  def find_authorized_record
   BiosimilarPrice.find_by!(id: params[:id], team_id: current_user.team_id)
  rescue ActiveRecord::RecordNotFound
   flash[:error] = 'Record not found or you do not have permission to edit it.'
   redirect_to biosimilar_prices_path and throw :abort
  end
 
 
   def generate_complete_biosimilar_sheet(spreadsheet, accounting_period, include_blended_costs: false)
     require 'axlsx'
 
     package = Axlsx::Package.new
     workbook = package.workbook
 
     header_style = workbook.styles.add_style(
       bg_color: '4472C4',
       fg_color: 'FFFFFF',
       b: true,
       alignment: { horizontal: :center }
     )
 
    data_style = workbook.styles.add_style
    light_red_style = workbook.styles.add_style(bg_color: "FFCCCC")
 
     blended_headers = [
       'BLENDED 340B COST',
       'BLENDED 340B MARGIN',
       'BLENDED PERCENT MARGIN',
       'BLENDED GPO COST',
       'BLENDED GPO MARGIN',
       'BLENDED GPO PERCENT MARGIN'
     ]
 
     workbook.add_worksheet(name: 'Biosimilar Prices') do |sheet|
       headers = [
         'GENERIC NAME',
         'NDC CODE',
         'ALTERNATE NDC CODE',
         'OTHER NDC CODES',
         'INSURANCES',
         'HCPCS CODE',
         'BILLING UNIT',
         'REIMBURSEMENT PER BILLING UNIT',
         'BILLING UNIT PER PACKAGE SIZE',
         'CMS REIMBURSEMENT PER PACKAGE',
         'COST THREE FORTY B',
         'COST PER UNIT THREE FORTY B',
         *(
           include_blended_costs ? [blended_headers[0]] : []
         ),
         'CMS MARGIN 340B COST',
         'CMS MARGIN PER UNIT THREE FORTY B COST',
         *(
           include_blended_costs ? [blended_headers[1]] : []
         ),
         'CMS PERCENT MARGIN',
         *(
           include_blended_costs ? [blended_headers[2]] : []
         ),
         'GPO COST',
         *(
           include_blended_costs ? [blended_headers[3]] : []
         ),
         'CMS MARGIN GPO COST',
         *(
           include_blended_costs ? [blended_headers[4]] : []
         ),
         'GPO PERCENT MARGIN',
         *(
           include_blended_costs ? [blended_headers[5]] : []
         ),
         'STATUS'
       ]
 
       sheet.add_row headers, style: header_style
 
       spreadsheet.each_with_index do |row, index|
         next if index.zero?
         generic_name = ActionView::Base.full_sanitizer.sanitize(row[0].to_s).strip
         ndc_raw      = row[1].to_s.strip
         hcpcs_code   = row[2].to_s.strip
         uploaded_billing_unit = row[3].to_s.strip
         insurances   = nil
 
         ndc_values = ndc_raw.split(',').map { |v| v.strip.sub(/\.0$/, '') }.reject(&:blank?)
 
         final_ndc_code           = ndc_values[0]
         final_alternate_ndc_code = ndc_values[1]
         final_other_ndc_codes    = ndc_values.size > 2 ? ndc_values[2..] : []
         final_other_ndc_codes ||= []
 
         next if final_ndc_code.blank? && hcpcs_code.blank?
 
         generic_name_group = nil
         extracted_brand_name = nil
         biosimilar_status = nil
         util_ndcs_for_catalog = nil

         biosim_data = BiosimilarPrice
                         .where(
                           team_id: current_user.team_id,
                           accounting_period_id: accounting_period.id-1,
                           generic_name: generic_name
                         )
                         .pluck(:generic_name_group, :extracted_brand_name, :status)
                         .first
 
         # -----------------------------
         # EXISTING NDC MERGE LOGIC
         # -----------------------------
         if biosim_data.present?
           generic_name_group, extracted_brand_name, biosimilar_status = biosim_data
 
           util_ndcs = UtilizationReport
                         .where(
                           team_id: current_user.team_id,
                           accounting_period_id: accounting_period.id,
                           generic_name_group: generic_name_group.to_s.capitalize,
                           extracted_brand_name: extracted_brand_name
                         )
                         .joins(:ndc_code_record)
                         .pluck(:ndc_code)
                         .uniq

           util_ndcs_for_catalog = util_ndcs

           existing_ndcs = [
             final_ndc_code,
             final_alternate_ndc_code,
             *final_other_ndc_codes
           ].compact
 
           missing_ndcs = util_ndcs - existing_ndcs
 
           missing_ndcs.each do |ndc|
             if final_alternate_ndc_code.blank?
               final_alternate_ndc_code = ndc
             else
               final_other_ndc_codes << ndc unless final_other_ndc_codes.include?(ndc)
             end
           end
         end
 
         final_other_ndc_codes_str =
           final_other_ndc_codes.present? ? final_other_ndc_codes.join(', ') : nil
 
        
         reimbursement_data =
           pull_reimbursement(
             final_ndc_code,
             final_alternate_ndc_code,
             hcpcs_code,
             accounting_period.id,
             uploaded_billing_unit
           )

         costs = {}
         cost_source = nil
         cost_resolved_ndc = nil

         [final_ndc_code, final_alternate_ndc_code, *final_other_ndc_codes].compact.each do |ndc|
           costs = calculate_costs(
             reimbursement_data[:billing_unit_per_package_size],
             reimbursement_data[:cms_reimbursement_per_package],
             ndc,
             accounting_period.id,
             current_user.team_id
           )

           if costs[:cost_three_forty_b].present? || costs[:gpo_cost].present?
             cost_source = (ndc == final_ndc_code ? :primary : :fallback)
             cost_resolved_ndc = ndc
             break
           end
         end
 
         
         blended_cost_340b = 0
         blended_margin_340b = 0
         blended_percent_340b = 0
         blended_gpo_cost = 0
         blended_margin_gpo = 0
         blended_percent_gpo = 0
 
        if include_blended_costs && biosim_data.present?
          biosimilar_records = BiosimilarPrice.where(
            team_id: current_user.team_id,
            accounting_period_id: accounting_period.id-1,
            generic_name_group: generic_name_group
          )
          brand_records = biosimilar_records.where(extracted_brand_name: extracted_brand_name)

          all_extracted_strengths =
            brand_records
              .where(generic_name_group: generic_name_group.to_s.upcase)
              .pluck(:extracted_strength)
              .uniq

          numerator_strengths =
            all_extracted_strengths
              .compact
              .map { |s| s.split('/').first.to_s.strip.upcase }
              .reject(&:blank?)
              .uniq
          use_base_blended =
            numerator_strengths.size == 1 ||
            BiosimilarPrice::COMBINED_GROUPS.include?(generic_name_group)

          if use_base_blended
            blended_cost_340b   = export_numeric(costs[:cost_three_forty_b]).to_f
            blended_margin_340b = export_numeric(costs[:cms_margin_three_forty_b_cost]).to_f
            blended_gpo_cost    = export_numeric(costs[:gpo_cost]).to_f
            blended_margin_gpo  = export_numeric(costs[:cms_margin_gpo_cost]).to_f
          else
            all_utilization_reports = UtilizationReport
              .joins(:ndc_code_record)
              .where(
                team_id: current_user.team_id,
                accounting_period_id: accounting_period.id,
                generic_name_group: generic_name_group.to_s.capitalize,
                charge_class: ['Outpatient', "Emergency"],
                category: nil
              )

            total_units = all_utilization_reports.sum(:total_units).to_f
            if total_units > 0
              numerator_strengths.each do |strength|
                strength_scope =
                  brand_records
                    .where("extracted_strength LIKE ?", "#{strength}%")
                    .where(extracted_brand_name: extracted_brand_name)

                representative_record = strength_scope.order(updated_at: :desc).first
                next if representative_record.blank?

                biosimilar_ndc_codes =
                  biosimilar_records
                    .where("extracted_strength LIKE ?", "#{strength}%")
                    .pluck(:ndc_code, :alternate_ndc_code, :other_ndc_codes)
                    .flat_map { |codes| codes.compact }
                    .flat_map { |code| code.to_s.split(',').map { |v| v.strip.sub(/\.0$/, '') } }
                    .reject(&:blank?)
                    .uniq
                next if biosimilar_ndc_codes.blank?

                package_units = all_utilization_reports
                  .where(ndc_code_record: { ndc_code: biosimilar_ndc_codes })
                  .sum(:total_units).to_f
                next if package_units.zero?

                ratio = package_units / total_units

                blended_cost_340b   += representative_record.cost_three_forty_b.to_f * ratio
                blended_margin_340b += representative_record.cms_margin_three_forty_b_cost.to_f * ratio
                blended_gpo_cost    += representative_record.gpo_cost.to_f * ratio
                blended_margin_gpo  += representative_record.cms_margin_gpo_cost.to_f * ratio
              end
            end
          end

          blended_percent_340b =
            blended_cost_340b > 0 ? (blended_margin_340b / blended_cost_340b * 100) : 0

          blended_percent_gpo =
            blended_gpo_cost > 0 ? (blended_margin_gpo / blended_gpo_cost * 100) : 0
        end
         former_yellow =
           cost_resolved_ndc.present? &&
           !util_ndcs_for_catalog.nil? &&
           !ndc_code_in_utilization_ndc_list?(cost_resolved_ndc, util_ndcs_for_catalog)

         row_styles =
           if former_yellow || cost_source == :primary
             Array.new(headers.size, nil)
           else
             Array.new(headers.size, light_red_style)
           end
 
         row_values = [
           generic_name,
           final_ndc_code,
           final_alternate_ndc_code,
           final_other_ndc_codes_str,
           insurances,
           hcpcs_code,
           export_numeric(reimbursement_data[:billing_unit]),
           export_numeric(reimbursement_data[:reimbursement_per_billing_unit]),
           export_numeric(reimbursement_data[:billing_unit_per_package_size]),
           export_numeric(reimbursement_data[:cms_reimbursement_per_package]),
           export_numeric(costs[:cost_three_forty_b]),
           export_numeric(costs[:cost_per_unit_three_forty_b])
         ]
         if include_blended_costs
           row_values << export_numeric(blended_cost_340b)
         end
         row_values << export_numeric(costs[:cms_margin_three_forty_b_cost])
         row_values << export_numeric(costs[:cms_margin_per_unit_three_forty_b_cost])
         row_values << export_numeric(blended_margin_340b) if include_blended_costs
         row_values << export_percent_label(costs[:cms_percent_margin])
         row_values << export_percent_label(blended_percent_340b) if include_blended_costs
         row_values << export_numeric(costs[:gpo_cost])
         row_values << export_numeric(blended_gpo_cost) if include_blended_costs
         row_values << export_numeric(costs[:cms_margin_gpo_cost])
         row_values << export_numeric(blended_margin_gpo) if include_blended_costs
         row_values << export_percent_label(costs[:gpo_percent_margin])
         row_values << export_percent_label(blended_percent_gpo) if include_blended_costs
         row_values << biosimilar_status
 
         sheet.add_row row_values, style: row_styles
       end
 
       sheet.column_widths(*Array.new(headers.size, 20))
     end
 
     package.to_stream
   end
 
   def fetch_catalog_price_for_ndc_by_category(ndc_code, quarter_id, team_id, category)
     return nil if ndc_code.blank? || quarter_id.blank? || team_id.blank? || category.blank?
 
     date_range = quarter_target_month_range(quarter_id)
     return nil unless date_range
 
     base_scope = PricingCatalog.where(
       team_id: team_id,
       ndc_code: ndc_code,
       category: category
     )
     return nil if base_scope.none?

     price = catalog_price_from_table_in_date_range(base_scope, date_range)
     return price unless price.nil?
 
     price = catalog_price_from_paper_trail_versions_only(base_scope, date_range)
     return price unless price.nil?
 
     catalog_price_from_table_at_max_effective_date(base_scope)
   end
 
   def catalog_price_from_table_in_date_range(base_scope, date_range)
     matching_ids =
       base_scope.to_a.filter_map do |row|
         row.id if catalog_effective_start_overlaps_target_quarter?(row.effective_start_date, date_range)
       end
     return nil if matching_ids.empty?
 
     minimum_catalog_price_at_latest_effective_date(base_scope.where(id: matching_ids))
   end
 
   def catalog_price_from_table_at_max_effective_date(base_scope)
     max_date = base_scope.maximum(:effective_start_date)
     return nil unless max_date
 
     rows = base_scope.where(effective_start_date: max_date)
     minimum_catalog_price_at_latest_effective_date(rows)
   end
 
   def minimum_catalog_price_at_latest_effective_date(rows)
     return nil if rows.none?
 
     latest_date = rows.maximum(:effective_start_date)
     return nil unless latest_date
 
     at_latest = rows.where(effective_start_date: latest_date)
     record = at_latest.order(:current_catalog_price, :id).first
     return nil unless record
 
     catalog_price_divided_by_pkg_qty(record)
   end
 
   def catalog_price_divided_by_pkg_qty(pricing_catalog_row)
     return nil unless pricing_catalog_row
 
     price = pricing_catalog_row.current_catalog_price
     return nil if price.nil?
 
     pkg = pricing_catalog_row.pack_quantity_d.to_f
     return nil if pkg.zero?
 
     price.to_f / pkg
   end
 
   def catalog_price_from_paper_trail_versions_only(base_scope, date_range)
     catalog_ids = base_scope.pluck(:id)
     return nil if catalog_ids.empty?
 
     versions = PaperTrail::Version.where(item_type: 'PricingCatalog', item_id: catalog_ids)
     pairs = []
     versions.find_each do |version|
       pairs.concat(extract_price_date_pairs_from_pricing_catalog_version(version, date_range))
     end
     return nil if pairs.empty?
 
     latest_date = pairs.map(&:first).compact.max
     return nil unless latest_date
 
     pairs.select { |d, _| d == latest_date }.map(&:last).compact.min
   end
 
   def extract_price_date_pairs_from_pricing_catalog_version(version, date_range)
     ch = version.object_changes.presence || version.try(:object_changes_jsonb)
     return [] if ch.blank?
 
     ch = ch.with_indifferent_access
     es = ch[:effective_start_date]
     cp = ch[:current_catalog_price]
     return [] unless es.is_a?(Array) && es.size >= 2
 
     old_es = parse_pricing_catalog_date_value(es[0])
     new_es = parse_pricing_catalog_date_value(es[1])
     old_price = cp.is_a?(Array) && cp.size >= 2 ? cp[0] : nil
     new_price = cp.is_a?(Array) && cp.size >= 2 ? cp[1] : nil
 
     out = []
     if old_es && catalog_effective_start_overlaps_target_quarter?(old_es, date_range) && !old_price.nil?
       d = parse_pricing_catalog_date_value(old_es)
       out << [d, old_price.to_f] if d
     end
     if new_es && catalog_effective_start_overlaps_target_quarter?(new_es, date_range) && !new_price.nil?
       d = parse_pricing_catalog_date_value(new_es)
       out << [d, new_price.to_f] if d
     end
     out
   end
 
   def catalog_effective_start_overlaps_target_quarter?(effective_start, date_range)
     return false if effective_start.blank? || date_range.blank?

     d = parse_pricing_catalog_date_value(effective_start)
     return false unless d

     dr_b = date_range.begin.respond_to?(:to_date) ? date_range.begin.to_date : date_range.begin
     dr_e = date_range.end.respond_to?(:to_date) ? date_range.end.to_date : date_range.end
     d >= dr_b && d <= dr_e
   rescue StandardError
     false
   end

   def parse_pricing_catalog_date_value(value)
     return nil if value.blank?
     return value if value.is_a?(Date)
     return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)

     Date.parse(value.to_s)
   rescue ArgumentError, TypeError
     nil
   end
 
   def quarter_target_month_range(quarter_id)
     accounting_period = AccountingPeriod.find_by(id: quarter_id)
     return nil unless accounting_period&.name
 
     match = accounting_period.name.match(/Quarter\s+(\d+)\s+(\d{4})/i)
     return nil unless match
 
     current_q = match[1].to_i
     current_year = match[2].to_i
 
     next_q = current_q == 4 ? 1 : current_q + 1
     next_year = current_q == 4 ? current_year + 1 : current_year
 
     case next_q
     when 1
       Date.new(next_year, 1, 1)..Date.new(next_year, 3, 31)
     when 2
       Date.new(next_year, 4, 1)..Date.new(next_year, 6, 30)
     when 3
       Date.new(next_year, 7, 1)..Date.new(next_year, 9, 30)
     when 4
       Date.new(next_year, 10, 1)..Date.new(next_year, 12, 31)
     end
   end
 
 def pull_reimbursement(ndc, alternate_ndc, hcpcs_code, reimbursement_id, uploaded_billing_unit = nil)
   return empty_reimbursement if reimbursement_id.blank?
 
   ndcs_to_try = []
 
   [ndc, alternate_ndc].each do |code|
     next if code.blank?
 
     raw     = code.to_s.strip
     cleaned = raw.sub(/^0+/, '')
 
     ndcs_to_try << raw
     ndcs_to_try << cleaned
   end
 
   ndcs_to_try.uniq!
   crosswalk = ndcs_to_try.lazy.map do |ndc|
     AspCrosswalk.find_by(reimbursement_id: reimbursement_id, ndc_two: ndc)
   end.find(&:present?)
   return empty_reimbursement if crosswalk.blank?
 
   cms_price =
     CmsAspPricing.find_by(
       reimbursement_id: reimbursement_id,
       hcpcs_code: crosswalk.code
     )
 
   return empty_reimbursement if cms_price.blank?
 
   billing_unit = uploaded_billing_unit.present? ? uploaded_billing_unit.to_f : nil
   pkg_size     = crosswalk.bill_units_pkg.to_f
   payment      = cms_price.payment_limit.to_f
 
   {
     billing_unit: billing_unit,
     reimbursement_per_billing_unit: payment,
     billing_unit_per_package_size: pkg_size,
     cms_reimbursement_per_package: payment * pkg_size
   }
  end
 
  def empty_reimbursement
   {
     billing_unit: nil,
     reimbursement_per_billing_unit: nil,
     billing_unit_per_package_size: nil,
     cms_reimbursement_per_package: nil
   }
  end
 
  def ndc_code_in_utilization_ndc_list?(ndc_code, utilization_ndc_codes)
    return false if ndc_code.blank? || utilization_ndc_codes.blank?

    norm = ndc_code.to_s.strip.sub(/^0+/, "").sub(/\.0$/, "")
    utilization_ndc_codes.any? do |u|
      norm == u.to_s.strip.sub(/^0+/, "").sub(/\.0$/, "")
    end
  end

  def calculate_costs(billing_unit_per_package_size, reimbursement_amount, ndc_code, quarter_id, team_id)
   return {} if billing_unit_per_package_size.to_f.zero? || reimbursement_amount.blank?

   cost_340b = fetch_catalog_price_for_ndc_by_category(ndc_code, quarter_id, team_id, '340B')
   gpo_cost  = fetch_catalog_price_for_ndc_by_category(ndc_code, quarter_id, team_id, 'GPO')
 
   cost_per_unit_three_forty_b = cost_340b && billing_unit_per_package_size.to_f.nonzero? ? cost_340b / billing_unit_per_package_size : nil
   cms_margin_three_forty_b_cost = cost_340b ? reimbursement_amount - cost_340b : nil
   reimbursement_per_unit = billing_unit_per_package_size.to_f.nonzero? ? (reimbursement_amount / billing_unit_per_package_size.to_f) : nil
   cms_margin_per_unit_three_forty_b_cost = cost_per_unit_three_forty_b && reimbursement_per_unit ? reimbursement_per_unit - cost_per_unit_three_forty_b : nil
   cms_percent_margin = cost_340b ? ((reimbursement_amount - cost_340b) / cost_340b) * 100 : nil
 
   cms_margin_gpo_cost = gpo_cost ? reimbursement_amount - gpo_cost : nil
   gpo_percent_margin = gpo_cost ? ((reimbursement_amount - gpo_cost) / gpo_cost) * 100 : nil
 
   {
     cost_three_forty_b: cost_340b,
     cost_per_unit_three_forty_b: cost_per_unit_three_forty_b,
     cms_margin_three_forty_b_cost: cms_margin_three_forty_b_cost,
     cms_margin_per_unit_three_forty_b_cost: cms_margin_per_unit_three_forty_b_cost,
     cms_percent_margin: cms_percent_margin,
     gpo_cost: gpo_cost,
     cms_margin_gpo_cost: cms_margin_gpo_cost,
     gpo_percent_margin: gpo_percent_margin
   }
  end
 
  def export_numeric(value)
   return nil if value.nil?
 
   value.to_f.round(2)
  end
 
  def export_percent_label(value)
   return nil if value.nil?
 
   format('%.2f%%', value.to_f.round(2))
  end
 
  def biosimilar_price_params
   params.require(:biosimilar_price).permit(
     :generic_name, :generic_name_group, :extracted_brand_name, :extracted_strength,
     :ndc_code, :alternate_ndc_code, :other_ndc_codes, :insurances,
     :hcpcs_code, :billing_unit, :reimbursement_per_billing_unit,
     :billing_unit_per_package_size, :cms_reimbursement_per_package,
     :cost_three_forty_b, :cost_per_unit_three_forty_b,
     :blended_cost_three_forty_b, :cms_margin_three_forty_b_cost,
     :blended_cms_margin_three_forty_b_cost, :cms_percent_margin,
     :blended_cms_percent_margin, :gpo_cost, :blended_gpo_cost,
     :cms_margin_gpo_cost, :blended_cms_margin_gpo_cost,
     :gpo_percent_margin, :blended_gpo_percent_margin,
     :reimbursement_id, :accounting_period_id, :status, :match, :team_id
   )
  end
end