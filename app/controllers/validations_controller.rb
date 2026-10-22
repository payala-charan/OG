class ValidationsController < ApplicationController
  require 'roo'

  def index
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
        team_id = %w[198 209 147].include?(params[:team_id].to_s.strip) ? params[:team_id].to_s.strip : "209"

        required_columns = [
          "ORDER_NAME", "NDC CODE", "HCPCS CODE", "CHARGE CLASS", "FINANCIAL CLASS",
          "PRIMARY PAYOR NAME","BENEFIT PLAN NAME", "GROUP", "BRAND NAME", "QUARTER", "PRODUCT COST PER UNIT",
          "TOTAL UNITS","CMS TOTAL UNITS", "TOTAL PRODUCT COST", "TOTAL INSURANCE PAYMENT",
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
        hcpcs_code = text.call(extracted["HCPCS CODE"])
        benefit_plan_name = text.call(extracted["BENEFIT PLAN NAME"])
        quarter =text.call(extracted["QUARTER"])
        group = text.call(extracted["GROUP"])
        brand_name = text.call(extracted["BRAND NAME"])
        order_name = text.call(extracted["ORDER_NAME"])
        financial_class = text.call(extracted["FINANCIAL CLASS"])
        charge_class = text.call(extracted["CHARGE CLASS"])
        total_units = clean.call(extracted["TOTAL UNITS"])
        cms_total_units = clean.call(extracted["CMS TOTAL UNITS"])
    
        extracted_conversion_product = text.call(extracted["CONVERSION PRODUCT"])
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
          billing_unit_per_package_size = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:billing_unit_per_package_size).first.to_f rescue 0.0
          billing_unit_per_package_size = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, alternate_ndc_code: ndc_code).pluck(:billing_unit_per_package_size).first.to_f rescue 0.0 if billing_unit_per_package_size.zero?
        else
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
            known_payors = InsuranceFactor.where(team_id: team_id).pluck(:benefit_plan_name).compact.uniq.map(&:downcase)
            # matched_payor = known_payors.find { |p| benefit_plan_down.include?(p) }
            matched_payor = known_payors.find { |p| p == benefit_plan_down } || known_payors.find { |p| benefit_plan_down.include?(p) }
            # payment_factor = PaymentFactor.where(payor: matched_payor).pluck(:factor).first.to_f rescue 1.0
            payment_factor = InsuranceFactor.where(benefit_plan_name: matched_payor.upcase, team_id: team_id).pluck(:insurance_factor).first.to_f rescue 1.0
            payment_factor = 1.0 if payment_factor.zero?
          end
          calc_total_ins_payment = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code).where("extracted_insurances @> ARRAY[?]::varchar[]", benefit_plan_name.upcase).pluck(:payrate_reimbursement_per_package).first.to_f rescue 0.0
          if calc_total_ins_payment.zero?
            calc_total_ins_payment = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, alternate_ndc_code: ndc_code).where("extracted_insurances @> ARRAY[?]::varchar[]", benefit_plan_name.upcase).pluck(:payrate_reimbursement_per_package).first.to_f rescue 0.0
          end
          if calc_total_ins_payment.zero?
            calc_total_ins_payment = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id).where("other_ndc_codes LIKE ?", "%#{ndc_code}%").where("extracted_insurances @> ARRAY[?]::varchar[]", benefit_plan_name.upcase).pluck(:payrate_reimbursement_per_package).first.to_f rescue 0.0
          end
          if benefit_plan_name.empty? || benefit_plan_name.nil? || calc_total_ins_payment.zero?
            calc_total_ins_payment = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code, category: "CMS").pluck(:payrate_reimbursement_per_package).first.to_f rescue 0.0
            calc_total_ins_payment = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, alternate_ndc_code: ndc_code, category: "CMS").pluck(:payrate_reimbursement_per_package).first.to_f rescue 0.0 if calc_total_ins_payment.zero?
            calc_total_ins_payment = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id).where("other_ndc_codes LIKE ?", "%#{ndc_code}%").where("extracted_insurances @> ARRAY[?]::varchar[]", benefit_plan_name.upcase).pluck(:payrate_reimbursement_per_package).first.to_f rescue 0.0 if calc_total_ins_payment.zero?
            calc_conv_total_ins_payment = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, generic_name: extracted_conversion_product, category: "CMS").pluck(:payrate_reimbursement_per_package).first.to_f rescue 0.0
          else
            calc_conv_total_ins_payment = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, generic_name: extracted_conversion_product).where("extracted_insurances @> ARRAY[?]::varchar[]", benefit_plan_name.upcase).pluck(:payrate_reimbursement_per_package).first.to_f rescue 0.0
          end
          calc_total_ins_payment = calc_total_ins_payment * total_units
          calc_conv_total_ins_payment = calc_conv_total_ins_payment * total_units
          # if team_id == "147"
          #   calc_total_ins_payment = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code).where("extracted_insurances @> ARRAY[?]::varchar[]", benefit_plan_name).pluck(:payrate_reimbursement_per_package).first.to_f rescue 0.0
          #   if calc_total_ins_payment.zero?
          #     calc_total_ins_payment = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, alternate_ndc_code: ndc_code).where("extracted_insurances @> ARRAY[?]::varchar[]", benefit_plan_name).pluck(:payrate_reimbursement_per_package).first.to_f rescue 0.0
          #   end
          #   if calc_total_ins_payment.zero?
          #     calc_total_ins_payment = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id).where("other_ndc_codes LIKE ?", "%#{ndc_code}%").where("extracted_insurances @> ARRAY[?]::varchar[]", benefit_plan_name).pluck(:payrate_reimbursement_per_package).first.to_f rescue 0.0
          #   end
          #   if benefit_plan_name.empty? || benefit_plan_name.nil?
          #     calc_conv_total_ins_payment = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, generic_name: extracted_conversion_product, category: "CMS").pluck(:payrate_reimbursement_per_package).first.to_f rescue 0.0
          #   else
          #     calc_conv_total_ins_payment = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, generic_name: extracted_conversion_product).where("extracted_insurances @> ARRAY[?]::varchar[]", benefit_plan_name).pluck(:payrate_reimbursement_per_package).first.to_f rescue 0.0
          #   end
          # else
          #   calc_total_ins_payment = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code).where("extracted_insurances @> ARRAY[?]::varchar[]", benefit_plan_name).pluck(:payrate_reimbursement_per_package).first.to_f rescue 0.0
          #   if calc_total_ins_payment.zero?
          #     calc_total_ins_payment = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, alternate_ndc_code: ndc_code).where("extracted_insurances @> ARRAY[?]::varchar[]", benefit_plan_name).pluck(:payrate_reimbursement_per_package).first.to_f rescue 0.0
          #   end
          #   if calc_total_ins_payment.zero?
          #     calc_total_ins_payment = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id).where("other_ndc_codes LIKE ?", "%#{ndc_code}%").where("extracted_insurances @> ARRAY[?]::varchar[]", benefit_plan_name).pluck(:payrate_reimbursement_per_package).first.to_f rescue 0.0
          #   end
          #   calc_conv_total_ins_payment = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, generic_name: extracted_conversion_product).where("extracted_insurances @> ARRAY[?]::varchar[]", benefit_plan_name).pluck(:payrate_reimbursement_per_package).first.to_f rescue 0.0
          # end
        end
        known_payors = InsuranceFactor.where(team_id: team_id).pluck(:benefit_plan_name).compact.uniq.map(&:downcase)
        benefit_plan_down = benefit_plan_name.downcase
        matched_payor = known_payors.find { |p| p == benefit_plan_down } || known_payors.find { |p| benefit_plan_down.include?(p) }
        final_payor = matched_payor.present? ? matched_payor : "Medipro"
        ins_raw = PayorPreference.where(
          team_id: team_id,
          generic_name_group: group.upcase,
          accounting_period_id: accounting_period_id,
          payor: final_payor
        ).pluck(:insurances).first
        # Parse JSON list or fallback to []
        payor_insurance_list = ins_raw.present? ? JSON.parse(ins_raw) : []
        package_size = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:billing_unit_per_package_size)
        package_size = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, alternate_ndc_code: ndc_code).pluck(:billing_unit_per_package_size) rescue 0.0 if package_size.blank? || package_size.first.to_f.zero?
        package_size = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id).where("other_ndc_codes LIKE ?", "%#{ndc_code}%").pluck(:billing_unit_per_package_size).first.to_f rescue 0.0 if package_size.blank? || package_size.first.to_f.zero?
        # all_payors = ["aetna", "cigna", "humana", "united", "anthem"]
        all_payors = InsuranceFactor.where(team_id: team_id).pluck(:benefit_plan_name).compact.uniq.map(&:downcase)
        insurances_list = []
        blockers = ["SPD", "PHS"]
        if brand_name.include?(blockers[0]) || brand_name.include?(blockers[1])
          brand_name = brand_name.split(" ").first
        end
        brand_down = brand_name.downcase

        if brand_down == "bendamustine hcl"
          brand_down = "bendamustine"
        elsif brand_down == "neupogen singleject"
          brand_down = "neupogen"
        end

        if charge_class.to_s.strip.casecmp("Inpatient").zero?
          db_cost_per_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code, match: match).pluck(:gpo_cost).first.to_f rescue 0.0
          db_cost_per_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, alternate_ndc_code: ndc_code, match: match).pluck(:gpo_cost).first.to_f rescue 0.0 if db_cost_per_unit.zero?
          # db_cost_per_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, other_ndc_codes: ndc_code).pluck(:gpo_cost).first.to_f rescue 0.0 if db_cost_per_unit.zero?
          db_cost_per_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id).where("other_ndc_codes LIKE ?", "%#{ndc_code}%").where(match: match).pluck(:gpo_cost).first.to_f rescue 0.0 if db_cost_per_unit.zero?
          insurances_list =  NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, generic_name_group: group.upcase).pluck(:extracted_brand_name).uniq
        else
          # db_cost_per_unit = Og.where(accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:cost_three_forty_b).first.to_f rescue 0.0
          db_cost_per_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code, match: match).pluck(:cost_three_forty_b).first.to_f rescue 0.0
          db_cost_per_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, alternate_ndc_code: ndc_code, match: match).pluck(:cost_three_forty_b).first.to_f rescue 0.0 if db_cost_per_unit.zero?
          # db_cost_per_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, other_ndc_codes: ndc_code).pluck(:cost_three_forty_b).first.to_f rescue 0.0 if db_cost_per_unit.zero?
          db_cost_per_unit = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id).where("other_ndc_codes LIKE ?", "%#{ndc_code}%").where(match: match).pluck(:cost_three_forty_b).first.to_f rescue 0.0 if db_cost_per_unit.zero?
          correct_insurance = if benefit_plan_down.empty?
            all_payors
          else
            # all_payors.find { |p| benefit_plan_down.include?(p) }
            all_payors.find { |p| p == benefit_plan_down } || all_payors.find { |p| benefit_plan_down.include?(p) }
          end
          if benefit_plan_down.empty?
            payor_id = nil
          else
            payor_id = Payor.where(team_id: team_id, generic_name: group.downcase, name: correct_insurance).pluck(:id).first rescue nil
          end
          if payor_id == nil
            insurances_list = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, generic_name_group: group.upcase).pluck(:extracted_brand_name).compact.uniq
          else
            insurances_list = Insurance.where(payor_id: payor_id).pluck(:name)
          end
        end
        insurances_list = insurances_list.compact.map(&:downcase)
        insurances_list = insurances_list.compact.map do |insurance|
          insurance.downcase == "in-fliximab" ? "infliximab" : insurance
        end
        original_brand_available = insurances_list.include?(brand_down)
        insurances_list << brand_down unless insurances_list.include?(brand_down)
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
            if benefit_plan_down.empty?
              query = query.where(category: "CMS")
              if charge_class.to_s.strip.casecmp("Inpatient").zero?
                # value = query.pluck(:gpo_cost).first.to_f rescue 0.0
                value = query.pluck(:blended_gpo_cost).first.to_f rescue 0.0
              elsif financial_class.to_s.strip.casecmp("Self-Pay").zero?
                value = query.pluck(:cost_three_forty_b).first.to_f rescue 0.0
              else
                if conversion_criteria == "highest_margin"
                  value = query.pluck(:blended_cms_margin_three_forty_b_cost).first.to_f rescue 0.0
                elsif conversion_criteria == "low_cost"
                  value = query.pluck(:cost_three_forty_b).first.to_f rescue 0.0
                elsif conversion_criteria == "percent_margin"
                  value = query.pluck(:blended_cms_percent_margin).first.to_f rescue 0.0
                end
              end
            else
              if charge_class.to_s.strip.casecmp("Inpatient").zero?
                # value = query.where("? = ANY(extracted_insurances)", benefit_plan_name).pluck(:gpo_cost).first.to_f rescue 0.0
                value = query.where("? = ANY(extracted_insurances)", benefit_plan_name.upcase).pluck(:blended_gpo_cost).first.to_f rescue 0.0
              elsif financial_class.to_s.strip.casecmp("Self-Pay").zero?
                value = query.where("? = ANY(extracted_insurances)", benefit_plan_name.upcase).pluck(:cost_three_forty_b).first.to_f rescue 0.0
              else
                if conversion_criteria == "highest_margin"
                  #value = query.pluck(:cms_margin_three_forty_b_cost).first.to_f rescue 0.0
                  value = query.where("? = ANY(extracted_insurances)", benefit_plan_name.upcase).pluck(:blended_cms_margin_three_forty_b_cost).first.to_f rescue 0.0
                elsif conversion_criteria == "low_cost"
                  value = query.where("? = ANY(extracted_insurances)", benefit_plan_name.upcase).pluck(:cost_three_forty_b).first.to_f rescue 0.0
                elsif conversion_criteria == "percent_margin"
                  #value = query.pluck(:cms_percent_margin).first.to_f rescue 0.0
                  value = query.where("? = ANY(extracted_insurances)", benefit_plan_name.upcase).pluck(:blended_cms_percent_margin).first.to_f rescue 0.0
                end
              end
            end
            cms_cost_hash[insurance] = value
          end

          cms_cost_hash = cms_cost_hash.each_with_object({}) do |(k, v), h| 
            h[k] = v.to_f unless v.to_f.zero?
          end
          if charge_class.to_s.strip.casecmp("Inpatient").zero? 
            top_pair = cms_cost_hash.min_by { |_, v| v } || [nil, 0]
          else
            if financial_class.to_s.strip.casecmp("Self-Pay").zero?
              top_pair = cms_cost_hash.min_by { |_, v| v } || [nil, 0]
            else
              if conversion_criteria == "highest_margin" || conversion_criteria == "percent_margin"
                top_pair = cms_cost_hash.max_by { |_, v| v } || [nil, 0]
              else 
                top_pair = cms_cost_hash.min_by { |_, v| v } || [nil, 0]
              end 
            end
          end
          if original_brand_available && top_pair[0] && !top_pair[0].nil?
            brand = top_pair[0]
            corresponding_value = top_pair[1] # highest cms_margin_340b or lowest gpo/340b_cost
            # Fetch conversion product from Og
            if charge_class.to_s.strip.casecmp("Inpatient").zero?
              calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, billing_unit_per_package_size: billing_unit_per_package_size, generic_name_group: group).order(blended_gpo_cost: :asc)
                                      .pluck(:generic_name).first.to_s rescue ""
            elsif financial_class.to_s.strip.casecmp("Self-Pay").zero?
              if conversion_criteria == "highest_margin" || conversion_criteria == "low_cost"
                calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, cost_three_forty_b: corresponding_value)
                                                        .pluck(:generic_name).first.to_s rescue ""

              else
                calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, cost_three_forty_b: corresponding_value)
                                                        .pluck(:generic_name).first.to_s rescue ""
              end
            else
              if conversion_criteria == "highest_margin"
                calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, blended_cms_margin_three_forty_b_cost: corresponding_value)
                                        .pluck(:generic_name).first.to_s rescue ""
              elsif conversion_criteria == "low_cost"
                calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, cost_three_forty_b: corresponding_value)
                                        .pluck(:generic_name).first.to_s rescue ""
              elsif conversion_criteria == "percent_margin"
                calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, blended_cms_percent_margin: corresponding_value)
                                                        .pluck(:generic_name).first.to_s rescue ""
              end
            end
          else
            no_conversion_product = true
            brand = brand_down
            if charge_class.to_s.strip.casecmp("Inpatient").zero?
              calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, billing_unit_per_package_size: billing_unit_per_package_size,  generic_name_group: group).order(blended_gpo_cost: :asc)
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
              if calc_conversion_product.empty? || calc_conversion_product.nil?
                calc_conversion_product = NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, status: "non_preferred_conversion", generic_name_group: group).where("? = ANY(extracted_insurances)", benefit_plan_name)
                                                        .pluck(:generic_name).first.to_s rescue ""
              end
            end
          end

          # Compare with extracted
          extracted_conversion_product = text.call(extracted["CONVERSION PRODUCT"])
          #Building Alternatives for the extracted conversion product
          alternatives = []
          cms_cost_hash.each do |other_brand, value|
      
            #next if other_brand == brand   # skip the selected top brand
            alt_product =
              if charge_class.to_s.strip.casecmp("Inpatient").zero?
                NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: other_brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, gpo_cost: value)
                                  .pluck(:generic_name).first.to_s rescue ""
              elsif financial_class.to_s.strip.casecmp("Self-Pay").zero?
                if conversion_criteria == "highest_margin" || conversion_criteria == "low_cost"
                  NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: other_brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, cost_three_forty_b: value)
                                  .pluck(:generic_name).first.to_s rescue ""  
                else
                  NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: other_brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, blended_cms_percent_margin: value)
                                  .pluck(:generic_name).first.to_s rescue ""  
                end
              else
                if conversion_criteria == "highest_margin"
                  NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: other_brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, blended_cms_margin_three_forty_b_cost: value)
                                  .pluck(:generic_name).first.to_s rescue ""
                elsif conversion_criteria == "low_cost"
                  NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: other_brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, cost_three_forty_b: value)
                                  .pluck(:generic_name).first.to_s rescue ""
                elsif conversion_criteria == "percent_margin"
                  NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, extracted_brand_name: other_brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, blended_cms_percent_margin: value)
                                  .pluck(:generic_name).first.to_s rescue ""
                end
              end
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
        if group.upcase == "FILGRASTIM" && (calc_conversion_product.to_s.downcase.include?("0.8ml") || calc_conversion_product.to_s.downcase.include?("1.6ml")) && (NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, generic_name: extracted_conversion_product).where("? = ANY(extracted_insurances)", benefit_plan_name.upcase).pluck(:blended_cms_margin_three_forty_b_cost).first.to_f == NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, generic_name: calc_conversion_product).where("? = ANY(extracted_insurances)", benefit_plan_name.upcase).pluck(:blended_cms_margin_three_forty_b_cost).first.to_f)
          calc_conversion_product = extracted_conversion_product
        end
        if group.upcase == 'RITUXIMAB' && (NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, generic_name: extracted_conversion_product).where("? = ANY(extracted_insurances)", benefit_plan_name.upcase).pluck(:blended_gpo_cost).first.to_f.round(2) == NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, generic_name: calc_conversion_product).where("? = ANY(extracted_insurances)", benefit_plan_name.upcase).pluck(:blended_gpo_cost).first.to_f.round(2))
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
        else
          val_conv_cost_per_unit = (NewBiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, generic_name: extracted_conversion_product).pluck(:cost_three_forty_b).first || 0).to_f
        end
        # ----------------------------------------
        # STEP 5: Final Comparison + Data Packaging
        # ----------------------------------------
        compare = ->(actual, calc, col) { ValidationComparison.match?(actual, calc, col) }
        get_status = ->(actual, calc, col) { ValidationComparison.status(actual, calc, col) }

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
            match: compare.call(actual_val, safe_calc_value, col),
            status: get_status.call(actual_val, safe_calc_value, col)
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
            ordered_row["PAYOR INSURANCES"] = payor_insurance_list
          elsif key == "CONVERSION PRODUCT"
            ordered_row["ALTERNATIVES"] = alternatives
          end
        end

        validated_row = ordered_row
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
