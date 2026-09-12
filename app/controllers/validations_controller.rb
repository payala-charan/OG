class ValidationsController < ApplicationController
  require 'roo'

  def index
    #records = ValidationRecord.all
    records = ValidationRecord.where(user_id: current_user.id)
    if records.any?
      @validated_data = records.map(&:data)
      first_row = @validated_data.first
      @extracted_headers = first_row.keys
    else
      @validated_data = []
      @extracted_headers = []
    end
  end

  def upload
      if params[:file].present?
        conversion_criteria = params[:conversion_criteria].blank? ? "highest_margin" : params[:conversion_criteria]
        file = params[:file]
        spreadsheet = Roo::Spreadsheet.open(file.path)
        headers = spreadsheet.row(1).map(&:to_s).map(&:strip)
        team_id = %w[198 209].include?(params[:team_id].to_s.strip) ? params[:team_id].to_s.strip : "209"

        required_columns = [
          "ORDER_NAME", "NDC CODE", "CHARGE CLASS", "FINANCIAL CLASS",
          "PRIMARY PAYOR NAME","BENEFIT PLAN NAME", "GROUP", "BRAND NAME", "QUARTER", "PRODUCT COST PER UNIT",
          "TOTAL UNITS", "TOTAL PRODUCT COST", "TOTAL INSURANCE PAYMENT",
          "TOTAL MARGIN", "PERCENT MARGIN", "CONVERSION PRODUCT",
          "CONVERSION PERCENTAGE", "CONVERSION PRODUCT COST PER UNIT",
          "CONVERSION TOTAL PRODUCT COST", "CONVERSION PRODUCT TOTAL INSURANCE PAYMENT",
          "CONVERSION PRODUCT TOTAL MARGIN", "CONVERSION PRODUCT PERCENT MARGIN",
          "BLENDED CONVERSION TOTAL PRODUCT COST", "BLENDED CONVERSION TOTAL MARGIN",
          "BLENDED CONVERSION PERCENT MARGIN", "BLENDED CONVERSION COST DIFFERENCE",
          "BLENDED CONVERSION MARGIN DIFFERENCE", "BLENDED CONVERSION PERCENT MARGIN DIFFERENCE"
        ]

        required_indices = required_columns.map { |col| headers.index(col) }

        # Insert PAYOR INSURANCES ONLY INTO DISPLAY HEADERS, NOT INTO required_columns
        display_headers = required_columns.dup
        primary_index = display_headers.index("PRIMARY PAYOR NAME")
        #primary_index = display_headers.index("BENEFIT PLAN NAME")
        display_headers.insert(primary_index + 1, "PAYOR INSURANCES")
        primary_index_cp = display_headers.index("CONVERSION PRODUCT")
        display_headers.insert(primary_index_cp + 1, "ALTERNATIVES")

        @extracted_headers = display_headers

        @validated_data = []
        ValidationRecord.where(user_id: current_user.id).delete_all
        (2..(spreadsheet.last_row-1)).each do |i|
          
          row = spreadsheet.row(i)
          extracted = Hash[required_columns.zip(required_indices.map { |idx| row[idx] })]
          # Helper lambdas
          clean = ->(val) { val.to_s.gsub(/[\$,()%]/, '').strip.to_f rescue 0.0 }
          text = ->(val) { val.to_s.strip }
          # Extract values
          # ndc_code = text.call(extracted["NDC CODE"])
          raw_ndc = extracted["NDC CODE"]
          ndc_code = if raw_ndc.is_a?(Float) || raw_ndc.to_s.match?(/\A\d+\.0\z/)
                      raw_ndc.to_i.to_s
                    else
                      raw_ndc.to_s.strip
                    end
          ndc_code = ndc_code.rjust(11, '0') if ndc_code.length < 11
        primary_payor_name = text.call(extracted["PRIMARY PAYOR NAME"])
        
        benefit_plan_name = text.call(extracted["BENEFIT PLAN NAME"])
        quarter =text.call(extracted["QUARTER"])
        group = text.call(extracted["GROUP"])
        brand_name = text.call(extracted["BRAND NAME"])
        order_name = text.call(extracted["ORDER_NAME"])
        financial_class = text.call(extracted["FINANCIAL CLASS"])
        charge_class = text.call(extracted["CHARGE CLASS"])
        total_units = clean.call(extracted["TOTAL UNITS"])

        conversion_percentage = clean.call(extracted["CONVERSION PERCENTAGE"]).to_i
        ppu = clean.call(extracted["PRODUCT COST PER UNIT"])
        total_product_cost = clean.call(extracted["TOTAL PRODUCT COST"])
        total_ins_payment = clean.call(extracted["TOTAL INSURANCE PAYMENT"])
        total_margin = clean.call(extracted["TOTAL MARGIN"])
        percent_margin = clean.call(extracted["PERCENT MARGIN"])

        conv_cost_per_unit = clean.call(extracted["CONVERSION PRODUCT COST PER UNIT"])
        conv_total_cost = clean.call(extracted["CONVERSION TOTAL PRODUCT COST"])
        conv_total_ins = clean.call(extracted["CONVERSION PRODUCT TOTAL INSURANCE PAYMENT"])
        conv_total_margin = clean.call(extracted["CONVERSION PRODUCT TOTAL MARGIN"])
        conv_percent_margin = clean.call(extracted["CONVERSION PRODUCT PERCENT MARGIN"])

        # ----------------------------------------
        # STEP 1: Normal Calculations
        # ----------------------------------------
        calc_total_product_cost = total_units * ppu
        calc_total_margin = total_ins_payment - total_product_cost
        calc_percent_margin = ((calc_total_margin / total_product_cost) * 100).round(1) rescue 0

        calc_conv_total_cost = total_units * conv_cost_per_unit
        calc_conv_total_margin = conv_total_ins - conv_total_cost
        calc_conv_percent_margin = ((calc_conv_total_margin.round(2) / calc_conv_total_cost.round(2)) * 100).round(1) rescue 0

        # calc_blended_total_cost = calc_conv_total_cost
        # calc_blended_total_margin = calc_conv_total_margin
        # --- Blended Total Cost Calculation ---
        if conversion_percentage != 100
          per = conversion_percentage.to_f / 100
          calculated_cost = (per * calc_conv_total_cost.to_f) + ((1 - per) * calc_total_product_cost.to_f)
          calc_blended_total_cost = calculated_cost
        else
          calc_blended_total_cost = calc_conv_total_cost.to_f
        end

        # --- Blended Total Margin Calculation ---
        if conversion_percentage != 100
          per = conversion_percentage.to_f / 100
          calculated_margin = (per * calc_conv_total_margin.to_f) + ((1 - per) * calc_total_margin.to_f)
          calc_blended_total_margin = calculated_margin
        else
          calc_blended_total_margin = calc_conv_total_margin.to_f
        end

        if conversion_percentage != 100
          calc_blended_percent_margin = ((calc_blended_total_margin/calc_blended_total_cost)*100).round(1)
        else
          calc_blended_percent_margin = calc_conv_percent_margin
        end

        calc_blended_cost_diff = calc_blended_total_cost - total_product_cost
        calc_blended_margin_diff = calc_blended_total_margin - total_margin
        calc_blended_percent_margin_diff = calc_blended_percent_margin - percent_margin

        # ----------------------------------------
        # STEP 2: TOTAL INSURANCE PAYMENT validation
        # ---------------------------------------
        #quarter = quarter.to_s.strip
        # quarter_number = quarter[/Quarter\s+(\d)\s+20\d{2}/, 1].to_i
        # if quarter_number == 4
        #   accounting_period_id = 5
        # elsif quarter_number == 1
        #   accounting_period_id = 6
        # elsif quarter_number == 2
        #   accounting_period_id = 3
        # else
        #   accounting_period_id = 4
        # end
        # debugger
        quarter_number = quarter[/Quarter\s+(\d)\s+(20\d{2})/, 1]&.to_i
        year = quarter[/Quarter\s+(\d)\s+(20\d{2})/, 2]&.to_i
        raise "Invalid format" unless quarter_number && year

        base_year = 2024
        base_quarter = 4

        accounting_period_id = ((year - base_year) * 4) + (quarter_number - base_quarter) + 1
        match = NewBiosimilarPrice.where(team_id: team_id,accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:match).first rescue "" 
        match = NewBiosimilarPrice.where(team_id: team_id,accounting_period_id: accounting_period_id, alternate_ndc_code: ndc_code).pluck(:match).first rescue "" if match.blank?
        match = NewBiosimilarPrice.where(team_id: team_id,accounting_period_id: accounting_period_id).where("other_ndc_codes LIKE ?", "%#{ndc_code}%").pluck(:match).first rescue "" if match.blank?
        if charge_class.to_s.strip.casecmp("Inpatient").zero?
          calc_total_ins_payment = 0
          calc_conv_total_ins_payment = 0
          # billing_unit_per_package_size = Og.where(accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:billing_unit_per_package_size).first.to_f rescue 0.0
          billing_unit_per_package_size = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:billing_unit_per_package_size).first.to_f rescue 0.0
          billing_unit_per_package_size = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, alternate_ndc_code: ndc_code).pluck(:billing_unit_per_package_size).first.to_f rescue 0.0 if billing_unit_per_package_size.zero?
          # match = Og.where(accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:match).first.to_f rescue 0.0
          # match = NewBiosimilarPrice.where(team_id: team_id,accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:match).first.to_f rescue 0.0
          # match = NewBiosimilarPrice.where(team_id: team_id,accounting_period_id: accounting_period_id, alternate_ndc_code: ndc_code).pluck(:match).first.to_f rescue 0.0 if match.zero?
        else
          # reimbursement_per_billing_unit = Og.where(accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:reimbursement_per_billing_unit).first.to_f rescue 0.0
          # billing_unit_per_package_size = Og.where(accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:billing_unit_per_package_size).first.to_f rescue 0.0
          # cms_reimbursement_per_package = Og.where(accounting_period_id: accounting_period_id, cost_three_forty_b: conv_cost_per_unit).pluck(:cms_reimbursement_per_package).first.to_f rescue 0.0
          # debugger
          reimbursement_per_billing_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:reimbursement_per_billing_unit).first.to_f rescue 0.0
          reimbursement_per_billing_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, alternate_ndc_code: ndc_code).pluck(:reimbursement_per_billing_unit).first.to_f rescue 0.0 if reimbursement_per_billing_unit.zero?
          reimbursement_per_billing_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id).where("other_ndc_codes LIKE ?", "%#{ndc_code}%").pluck(:reimbursement_per_billing_unit).first.to_f rescue 0.0 if reimbursement_per_billing_unit.zero?
          billing_unit_per_package_size = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:billing_unit_per_package_size).first.to_f rescue 0.0
          billing_unit_per_package_size = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, alternate_ndc_code: ndc_code).pluck(:billing_unit_per_package_size).first.to_f rescue 0.0 if billing_unit_per_package_size.zero?
          billing_unit_per_package_size = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id).where("other_ndc_codes LIKE ?", "%#{ndc_code}%").pluck(:billing_unit_per_package_size).first.to_f rescue 0.0 if billing_unit_per_package_size.zero?
          cms_reimbursement_per_package = NewBiosimilarPrice.where(team_id: team_id, generic_name_group: group, accounting_period_id: accounting_period_id, cost_three_forty_b: conv_cost_per_unit).pluck(:cms_reimbursement_per_package).first.to_f rescue 0.0
          cms_reimbursement_per_package = NewBiosimilarPrice.where(team_id: team_id, generic_name_group: group, accounting_period_id: accounting_period_id).where("ROUND(cost_three_forty_b::numeric, 2) = ?", conv_cost_per_unit.round(2)).pluck(:cms_reimbursement_per_package).first.to_f rescue 0.0 if cms_reimbursement_per_package.zero?
          # Determine payment factor
          benefit_plan_down = benefit_plan_name.downcase
          primary_down = primary_payor_name.downcase
          if (primary_down.include?('medicare') || primary_down.include?('medicaid')) ||(benefit_plan_down.include?('medicare') || benefit_plan_down.include?('medicaid'))
            payment_factor = 1.0  
          else
            # known_payors = ["aetna", "cigna", "united", "anthem", "sentara"]
            # known_payors = ["pacificsource medicare advantage","pacificsource navigator smart group","bcbs preferred provider","bcbs schs","providence health plan pebb oebb","bcbs federal employee","providence health medicare","aetna 14079","united healthcare","providence health plan","uhc choice plus","eastern oregon cco ohp","moda affinity","cigna ppo","pscs bridge healthier oregon","pacificsource employees navigator","moda oebb pebb","umr uhc","bcbs valueppo","health plan options uhc","pacificsource navigator smart individual","united healthcare medicare advtg","providence health plan individual","national association of letter carriers","geha uhc","aetna medicare","bcbs med adv 1st or pref choice","cigna","moda synergy","moda connexus ccn ohsu","harrison trust cigna","regence group administrators","generic aetna","surest uhc","aarp medicare advantage plan 2","gravie administrative svs"]
            known_payors = InsuranceFactor.pluck(:benefit_plan_name).compact.uniq.map(&:downcase)
            # matched_payor = known_payors.find { |p| benefit_plan_down.include?(p) }
            matched_payor = known_payors.find { |p| p == benefit_plan_down } || known_payors.find { |p| benefit_plan_down.include?(p) }
            # payment_factor = PaymentFactor.where(payor: matched_payor).pluck(:factor).first.to_f rescue 1.0
            payment_factor = InsuranceFactor.where(benefit_plan_name: matched_payor.upcase, team_id: team_id).pluck(:insurance_factor).first.to_f rescue 1.0
            payment_factor = 1.0 if payment_factor.zero?
          end
          calc_total_ins_payment = total_units * reimbursement_per_billing_unit * billing_unit_per_package_size * payment_factor
          calc_conv_total_ins_payment = total_units * cms_reimbursement_per_package * payment_factor
        end
        # Insurances list fetching based on payor preference
        # Known payors list
        # known_payors = ["aetna", "cigna", "united", "anthem", "humana"]
        # debugger
        known_payors = InsuranceFactor.pluck(:benefit_plan_name).compact.uniq.map(&:downcase)
        benefit_plan_down = benefit_plan_name.downcase
        # matched_payor = known_payors.find { |p| benefit_plan_down.include?(p) }
        # matched_payor = known_payors.select { |p| benefit_plan_down.include?(p) }.max_by(&:length)
        matched_payor = known_payors.find { |p| p == benefit_plan_down } || known_payors.find { |p| benefit_plan_down.include?(p) }
        final_payor = matched_payor.present? ? matched_payor : "Medipro"
        # Fetch insurances list from PayorPreference
        # debugger
        ins_raw = PayorPreference.where(
          generic_name_group: group.upcase,
          accounting_period_id: accounting_period_id,
          payor: final_payor
        ).pluck(:insurances).first
        # Parse JSON list or fallback to []
        insurance_list = ins_raw.present? ? JSON.parse(ins_raw) : []

        
        #product cost per unit and conversion product calculation
        # package_size = Og.where(accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:billing_unit_per_package_size)
        package_size = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:billing_unit_per_package_size)
        package_size = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, alternate_ndc_code: ndc_code).pluck(:billing_unit_per_package_size) rescue 0.0 if package_size.blank? || package_size.first.to_f.zero?
        package_size = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id).where("other_ndc_codes LIKE ?", "%#{ndc_code}%").pluck(:billing_unit_per_package_size).first.to_f rescue 0.0 if package_size.blank? || package_size.first.to_f.zero?
        # all_payors = ["aetna", "cigna", "humana", "united", "anthem"]
        all_payors = InsuranceFactor.pluck(:benefit_plan_name).compact.uniq.map(&:downcase)
        insurances_list = []
        if charge_class.to_s.strip.casecmp("Inpatient").zero?
          # db_cost_per_unit = Og.where(accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:gpo_cost).first.to_f rescue 0.0
          # insurances_list =  Og.where(accounting_period_id: accounting_period_id, generic_name_group: group.upcase).pluck(:brand).uniq
          db_cost_per_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:gpo_cost).first.to_f rescue 0.0
          db_cost_per_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, alternate_ndc_code: ndc_code).pluck(:gpo_cost).first.to_f rescue 0.0 if db_cost_per_unit.zero?
          # db_cost_per_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, other_ndc_codes: ndc_code).pluck(:gpo_cost).first.to_f rescue 0.0 if db_cost_per_unit.zero?
          db_cost_per_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id).where("other_ndc_codes LIKE ?", "%#{ndc_code}%").pluck(:gpo_cost).first.to_f rescue 0.0 if db_cost_per_unit.zero?
            insurances_list =  NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, generic_name_group: group.upcase).pluck(:extracted_brand_name).uniq
        else
          # db_cost_per_unit = Og.where(accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:cost_three_forty_b).first.to_f rescue 0.0
          db_cost_per_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:cost_three_forty_b).first.to_f rescue 0.0
          db_cost_per_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, alternate_ndc_code: ndc_code).pluck(:cost_three_forty_b).first.to_f rescue 0.0 if db_cost_per_unit.zero?
          # db_cost_per_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, other_ndc_codes: ndc_code).pluck(:cost_three_forty_b).first.to_f rescue 0.0 if db_cost_per_unit.zero?
          db_cost_per_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id).where("other_ndc_codes LIKE ?", "%#{ndc_code}%").pluck(:cost_three_forty_b).first.to_f rescue 0.0 if db_cost_per_unit.zero?
          #correct_insurance  = all_payors.find { |p| primary_down.include?(p) }
          correct_insurance = if benefit_plan_down.empty?
            all_payors
          else
            # all_payors.find { |p| benefit_plan_down.include?(p) }
            all_payors.find { |p| p == benefit_plan_down } || all_payors.find { |p| benefit_plan_down.include?(p) }
          end
          # if benefit_plan_down.include?('medicaid') || benefit_plan_down.include?('medicare ') || all_payors.none? { |p| benefit_plan_down.include?(p) } 
          #   # insurances_list = Og.where(accounting_period_id: accounting_period_id, generic_name_group: group.upcase).pluck(:brand).uniq
          #   insurances_list = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, generic_name_group: group.upcase).pluck(:extracted_brand_name).uniq
          # else
          if benefit_plan_down.empty?
            payor_id = nil
          else
            payor_id = Payor.where(generic_name: group.downcase, name: correct_insurance).pluck(:id).first rescue nil
          end
          if payor_id == nil
            insurances_list = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, generic_name_group: group.upcase).pluck(:extracted_brand_name).uniq
          else
            insurances_list = Insurance.where(payor_id: payor_id).pluck(:name)
          end
          # end
          #insurances_list.map!(&:downcase)
          insurances_list = insurances_list.compact.map(&:downcase)
          # Ensure brand is in list
          brand_down = brand_name.downcase
          original_brand_available = insurances_list.include?(brand_down)
          insurances_list << brand_down unless insurances_list.include?(brand_down)
        end
        # debugger
        if (group.upcase == "PEGFILGRASTIM" && (insurances_list.include?("UDENYCA") || insurances_list.include?("udenyca")))
          insurances_list << "udenyca onbody"
        end
        if (group.upcase == "PEGFILGRASTIM" && (insurances_list.include?("NEULASTA") || insurances_list.include?("neulasta")))
          insurances_list << "neulasta onpro kit"
        end
 
        #checking the conversion criteria for the prefered product
        if conversion_criteria != "preferred_product"
          no_conversion_product = false
          # Build CMS cost hash dynamically based on charge/financial class
          cms_cost_hash = {}
          insurances_list.compact.each do |insurance|
            # query = charge_class != "Inpatient" ? Og.where(accounting_period_id: accounting_period_id, brand: insurance.capitalize, billing_unit_per_package_size: package_size) : Og.where(accounting_period_id: accounting_period_id, brand: insurance, billing_unit_per_package_size: package_size)
            query = charge_class != "Inpatient" ? NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: insurance.upcase, billing_unit_per_package_size: package_size, match: match) : NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: insurance.upcase, billing_unit_per_package_size: package_size, match: match)
            if charge_class.to_s.strip.casecmp("Inpatient").zero?
              value = query.pluck(:gpo_cost).first.to_f rescue 0.0
            elsif financial_class.to_s.strip.casecmp("Self-Pay").zero?
              if conversion_criteria == "low_cost" || conversion_criteria == "highest_margin"
                value = query.pluck(:cost_three_forty_b).first.to_f rescue 0.0
              elsif conversion_criteria == "percent_margin"
                value = query.pluck(:cms_percent_margin).first.to_f rescue 0.0
              end
            else
              if conversion_criteria == "highest_margin"
                #value = query.pluck(:cms_margin_three_forty_b_cost).first.to_f rescue 0.0
                value = query.pluck(:blended_cms_margin_three_forty_b_cost).first.to_f rescue 0.0
              elsif conversion_criteria == "low_cost"
                value = query.pluck(:cost_three_forty_b).first.to_f rescue 0.0
              elsif conversion_criteria == "percent_margin"
                #value = query.pluck(:cms_percent_margin).first.to_f rescue 0.0
                value = query.pluck(:blended_cms_percent_margin).first.to_f rescue 0.0
              end
            end

            cms_cost_hash[insurance] = value
          end

          cms_cost_hash = cms_cost_hash.each_with_object({}) do |(k, v), h| 
            h[k] = v.to_f unless v.to_f.zero?
          end
          
          # Select top/bottom based on condition
          if charge_class.to_s.strip.casecmp("Inpatient").zero? 
            top_pair = cms_cost_hash.min_by { |_, v| v } || [nil, 0]
          else
            if financial_class.to_s.strip.casecmp("Self-Pay").zero?
              if conversion_criteria == "percent_margin"
                top_pair = cms_cost_hash.max_by { |_, v| v } || [nil, 0]
              else 
                top_pair = cms_cost_hash.min_by { |_, v| v } || [nil, 0]
              end 
            else
              if conversion_criteria == "highest_margin" || conversion_criteria == "percent_margin"
                top_pair = cms_cost_hash.max_by { |_, v| v } || [nil, 0]
              else 
                top_pair = cms_cost_hash.min_by { |_, v| v } || [nil, 0]
              end 
            end
          end
          # debugger
          if original_brand_available && top_pair[0] && !top_pair[0].nil?
            brand = top_pair[0]
            corresponding_value = top_pair[1] # highest cms_margin_340b or lowest gpo/340b_cost
            # Fetch conversion product from Og
            # debugger
            if charge_class.to_s.strip.casecmp("Inpatient").zero?
              # calc_conversion_product = Og.where(accounting_period_id: accounting_period_id, brand: brand, billing_unit_per_package_size: billing_unit_per_package_size, gpo_cost: corresponding_value)
              #                         .pluck(:generic_name).first.to_s rescue ""
              calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, gpo_cost: corresponding_value)
                                      .pluck(:generic_name).first.to_s rescue ""
            elsif financial_class.to_s.strip.casecmp("Self-Pay").zero?
              if conversion_criteria == "highest_margin" || conversion_criteria == "low_cost"
                # calc_conversion_product = Og.where(accounting_period_id: accounting_period_id, brand: brand.capitalize,billing_unit_per_package_size: billing_unit_per_package_size,  cost_three_forty_b: corresponding_value)
                #                         .pluck(:generic_name).first.to_s rescue ""
                calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, cost_three_forty_b: corresponding_value)
                                                        .pluck(:generic_name).first.to_s rescue ""

              else
                # calc_conversion_product = Og.where(accounting_period_id: accounting_period_id, brand: brand.capitalize, billing_unit_per_package_size: billing_unit_per_package_size, cms_percent_margin: corresponding_value)
                #                         .pluck(:generic_name).first.to_s rescue ""
                calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, blended_cms_percent_margin: corresponding_value)
                                                        .pluck(:generic_name).first.to_s rescue ""
              end
            else
              if conversion_criteria == "highest_margin"
                # calc_conversion_product = Og.where(accounting_period_id: accounting_period_id, brand: brand.capitalize, billing_unit_per_package_size: billing_unit_per_package_size, blended_cms_margin_340B: corresponding_value)
                #                          .pluck(:generic_name).first.to_s rescue ""
                calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, blended_cms_margin_three_forty_b_cost: corresponding_value)
                                        .pluck(:generic_name).first.to_s rescue ""
              elsif conversion_criteria == "low_cost"
                # calc_conversion_product = Og.where(accounting_period_id: accounting_period_id, brand: brand.capitalize, billing_unit_per_package_size: billing_unit_per_package_size, cost_three_forty_b: corresponding_value)
                #                         .pluck(:generic_name).first.to_s rescue ""
                calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, cost_three_forty_b: corresponding_value)
                                        .pluck(:generic_name).first.to_s rescue ""

              elsif conversion_criteria == "percent_margin"
                # calc_conversion_product = Og.where(accounting_period_id: accounting_period_id, brand: brand.capitalize, billing_unit_per_package_size: billing_unit_per_package_size, blended_cms_340B_percent_margin: corresponding_value)
                #                         .pluck(:generic_name).first.to_s rescue ""
                calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, blended_cms_percent_margin: corresponding_value)
                                                        .pluck(:generic_name).first.to_s rescue ""
              end
            end
          else
            no_conversion_product = true
            brand = brand_down
            if charge_class.to_s.strip.casecmp("Inpatient").zero?
              calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size)
                                      .pluck(:generic_name).first.to_s rescue ""
            elsif financial_class.to_s.strip.casecmp("Self-Pay").zero?
              if conversion_criteria == "highest_margin" || conversion_criteria == "low_cost"
                calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size)
                                                        .pluck(:generic_name).first.to_s rescue ""

              else
                calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size)
                                                        .pluck(:generic_name).first.to_s rescue ""
              end
            else
              if conversion_criteria == "highest_margin"
                calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size)
                                        .pluck(:generic_name).first.to_s rescue ""
              elsif conversion_criteria == "low_cost"
                calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size)
                                        .pluck(:generic_name).first.to_s rescue ""

              elsif conversion_criteria == "percent_margin"
                calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size)
                                                        .pluck(:generic_name).first.to_s rescue ""
              end
            end
          end

          # Compare with extracted
          extracted_conversion_product = text.call(extracted["CONVERSION PRODUCT"])
          #Building Alternatives for the extracted conversion product
          alternatives = []
          # debugger
          cms_cost_hash.each do |other_brand, value|
      
            #next if other_brand == brand   # skip the selected top brand
            # debugger
            alt_product =
              if charge_class.to_s.strip.casecmp("Inpatient").zero?
                # Og.where(
                #   accounting_period_id: accounting_period_id,
                #   brand: other_brand,
                #   billing_unit_per_package_size: billing_unit_per_package_size,
                #   gpo_cost: value
                # ).pluck(:generic_name).first.to_s rescue ""
                NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: other_brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, gpo_cost: value)
                                  .pluck(:generic_name).first.to_s rescue ""
              elsif financial_class.to_s.strip.casecmp("Self-Pay").zero?
                if conversion_criteria == "highest_margin" || conversion_criteria == "low_cost"
                  # Og.where(
                  #   accounting_period_id: accounting_period_id,
                  #   brand: other_brand.capitalize,
                  #   billing_unit_per_package_size: billing_unit_per_package_size,
                  #   cost_three_forty_b: value
                  # ).pluck(:generic_name).first.to_s rescue ""
                  NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: other_brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, cost_three_forty_b: value)
                                  .pluck(:generic_name).first.to_s rescue ""  
                else
                  # Og.where(
                  #   accounting_period_id: accounting_period_id,
                  #   brand: other_brand.capitalize,
                  #   billing_unit_per_package_size: billing_unit_per_package_size,
                  #   cms_percent_margin: value
                  # ).pluck(:generic_name).first.to_s rescue ""
                  NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: other_brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, blended_cms_percent_margin: value)
                                  .pluck(:generic_name).first.to_s rescue ""  
                end
              else
                if conversion_criteria == "highest_margin"
                  # Og.where(
                  #   accounting_period_id: accounting_period_id,
                  #   brand: other_brand.capitalize,
                  #   billing_unit_per_package_size: billing_unit_per_package_size,
                  #   blended_cms_margin_340B: value
                  #   #cms_margin_three_forty_b_cost: value
                  # ).pluck(:generic_name).first.to_s rescue ""
                  NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: other_brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, blended_cms_margin_three_forty_b_cost: value)
                                  .pluck(:generic_name).first.to_s rescue ""
                elsif conversion_criteria == "low_cost"
                  # Og.where(
                  #   accounting_period_id: accounting_period_id,
                  #   brand: other_brand.capitalize,
                  #   billing_unit_per_package_size: billing_unit_per_package_size,
                  #   cost_three_forty_b: value
                  # ).pluck(:generic_name).first.to_s rescue ""
                  NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: other_brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, cost_three_forty_b: value)
                                  .pluck(:generic_name).first.to_s rescue ""
                elsif conversion_criteria == "percent_margin"
                  # Og.where(
                  #   accounting_period_id: accounting_period_id,
                  #   brand: other_brand.capitalize,
                  #   billing_unit_per_package_size: billing_unit_per_package_size,
                  #   blended_cms_340B_percent_margin: value
                  #   #cms_percent_margin: value
                  # ).pluck(:generic_name).first.to_s rescue ""
                  NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: other_brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, blended_cms_percent_margin: value)
                                  .pluck(:generic_name).first.to_s rescue ""
                end
              end
              # debugger
            alternatives << {
              brand: other_brand,
              product: alt_product,
              value: value
            }
          end
        else
          extracted_conversion_product = text.call(extracted["CONVERSION PRODUCT"])
          calc_conversion_product = extracted_conversion_product
          alternatives = []
        end
        if group.upcase == "FILGRASTIM" && (extracted_conversion_product.to_s.downcase.include?("0.8ml") || extracted_conversion_product.to_s.downcase.include?("1.6ml"))
          calc_conversion_product = extracted_conversion_product
        end
        if accounting_period_id == 6 && group.upcase == "INFLIXIMAB" && calc_conversion_product.downcase == "infliximab (in-fliximab) injection 100mg vial"   
          calc_conversion_product = extracted_conversion_product
        end
        if accounting_period_id == 6 && group.upcase == "RITUXIMAB" && (calc_conversion_product.downcase == "rituximab-arrx (riabni) 100mg vial" || calc_conversion_product.downcase == "rituximab-arrx (riabni) 500mg vial")
          calc_conversion_product = extracted_conversion_product
        end
        match_conversion_product = extracted_conversion_product.downcase == calc_conversion_product.downcase
        #Conversion product cost per unit calculation
        if charge_class.to_s.strip.casecmp("Inpatient").zero?
          val_conv_cost_per_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, generic_name: extracted_conversion_product).pluck(:gpo_cost).first
          #val_conv_cost_per_unit = Og.pick(:gpo_cost, accounting_period_id: accounting_period_id, generic_name: extracted_conversion_product).to_f rescue 0.0
        else
          # val_conv_cost_per_unit = (Og.where(accounting_period_id: accounting_period_id, generic_name: extracted_conversion_product).pluck(:cost_three_forty_b).first || 0).to_f
          val_conv_cost_per_unit = (NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, generic_name: extracted_conversion_product).pluck(:cost_three_forty_b).first || 0).to_f
        end
        # ----------------------------------------
        # STEP 5: Final Comparison + Data Packaging
        # ----------------------------------------
        compare = ->(actual, calc) { (actual.to_f - calc.to_f).abs <= 1.001 }
        get_status = lambda do |actual, calc|
          diff = (actual.to_f - calc.to_f).abs
          if diff < 0.01
            "exact"
          elsif diff <= 1.001
            "close"
          else
            "error"
          end
        end

        validated_row = extracted.transform_values(&:to_s)

        {
          "PRODUCT COST PER UNIT" => db_cost_per_unit,
          "TOTAL PRODUCT COST" => calc_total_product_cost,
          "TOTAL INSURANCE PAYMENT" => calc_total_ins_payment,
          "TOTAL MARGIN" => calc_total_margin,
          "PERCENT MARGIN" => calc_percent_margin,
          "CONVERSION PRODUCT COST PER UNIT" => val_conv_cost_per_unit,
          "CONVERSION TOTAL PRODUCT COST" => calc_conv_total_cost,
          "CONVERSION PRODUCT TOTAL INSURANCE PAYMENT" => calc_conv_total_ins_payment,
          "CONVERSION PRODUCT TOTAL MARGIN" => calc_conv_total_margin,
          "CONVERSION PRODUCT PERCENT MARGIN" => calc_conv_percent_margin,
          "BLENDED CONVERSION TOTAL PRODUCT COST" => calc_blended_total_cost,
          "BLENDED CONVERSION TOTAL MARGIN" => calc_blended_total_margin,
          "BLENDED CONVERSION PERCENT MARGIN" => calc_blended_percent_margin,
          "BLENDED CONVERSION COST DIFFERENCE" => calc_blended_cost_diff,
          "BLENDED CONVERSION MARGIN DIFFERENCE" => calc_blended_margin_diff,
          "BLENDED CONVERSION PERCENT MARGIN DIFFERENCE" => calc_blended_percent_margin_diff
        }.each do |col, calc_value|
          actual_val = clean.call(extracted[col])
          safe_calc_value = calc_value.to_f
          validated_row[col] = {
            actual: extracted[col],
            calc: safe_calc_value.round(2),
            match: compare.call(actual_val, safe_calc_value),
            status: get_status.call(actual_val, safe_calc_value)
          }
        end
        
        # Add Conversion Product result
        validated_row["CONVERSION PRODUCT"] = {
          actual: extracted_conversion_product,
          calc: calc_conversion_product,
          match: match_conversion_product,
          status: match_conversion_product ? "exact" : "error",
          no_conversion_product: no_conversion_product || false
        }
        validated_row["ALTERNATIVES"] = alternatives

        # === Insert PAYOR INSURANCES next to PRIMARY PAYOR NAME ===
        ordered_row = {}

        validated_row.each do |key, value|
          ordered_row[key] = value
          
          #if key == "PRIMARY PAYOR NAME"
          if key == "BENEFIT PLAN NAME"
            ordered_row["PAYOR INSURANCES"] = insurance_list
          elsif key == "CONVERSION PRODUCT"
            ordered_row["ALTERNATIVES"] = alternatives
          end
        end

        validated_row = ordered_row

        #validated_row["PAYOR INSURANCES"] = insurance_list


        @validated_data << validated_row
        ValidationRecord.create!(data: validated_row, user_id: current_user.id, user_email: current_user.email)
      end

      render :index
    else
      flash[:alert] = "Please upload an Excel file."
      redirect_to validations_path
    end
  end
end
