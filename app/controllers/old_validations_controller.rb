class ValidationsController < ApplicationController
  require 'roo'

  def index
  end

  def upload
    if params[:file].present?
      conversion_criteria = params[:conversion_criteria].blank? ? "highest_margin" : params[:conversion_criteria]
      file = params[:file]
      spreadsheet = Roo::Spreadsheet.open(file.path)
      headers = spreadsheet.row(1).map(&:to_s).map(&:strip)

      required_columns = [
        "ORDER_NAME", "NDC CODE", "CHARGE CLASS", "FINANCIAL CLASS",
        "PRIMARY PAYOR NAME", "GROUP", "BRAND NAME", "QUARTER", "PRODUCT COST PER UNIT",
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
      @extracted_headers = required_columns
      @validated_data = []

      (2..spreadsheet.last_row).each do |i|
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
        primary_payor_name = text.call(extracted["PRIMARY PAYOR NAME"])
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
        calc_conv_percent_margin = ((calc_conv_total_margin / calc_conv_total_cost) * 100).round(1) rescue 0

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
        quarter_number = quarter[/Quarter\s+(\d)\s+20\d{2}/, 1].to_i
        if quarter_number == 4
          accounting_period_id = 1
        elsif quarter_number == 1
          accounting_period_id = 2
        elsif quarter_number == 2
          accounting_period_id = 3
        else
          accounting_period_id = 4
        end
        if charge_class.to_s.strip.casecmp("Inpatient").zero?
          calc_total_ins_payment = 0
          calc_conv_total_ins_payment = 0
          billing_unit_per_package_size = Og.where(accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:billing_unit_per_package_size).first.to_f rescue 0.0
        else
          reimbursement_per_billing_unit = Og.where(accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:reimbursement_per_billing_unit).first.to_f rescue 0.0
          billing_unit_per_package_size = Og.where(accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:billing_unit_per_package_size).first.to_f rescue 0.0
          cms_reimbursement_per_package = Og.where(accounting_period_id: accounting_period_id, cost_three_forty_b: conv_cost_per_unit).pluck(:cms_reimbursement_per_package).first.to_f rescue 0.0

          # Determine payment factor
          primary_down = primary_payor_name.downcase
          if primary_down.include?('medicare') || primary_down.include?('medicaid')
            payment_factor = 1.0  
          else
            known_payors = ["aetna", "cigna", "united", "anthem", "sentara"]
            matched_payor = known_payors.find { |p| primary_down.include?(p) }
            payment_factor = PaymentFactor.where(payor: matched_payor).pluck(:factor).first.to_f rescue 1.0
            payment_factor = 1.0 if payment_factor.zero?
          end

          calc_total_ins_payment = total_units * reimbursement_per_billing_unit * billing_unit_per_package_size * payment_factor
          calc_conv_total_ins_payment = total_units * cms_reimbursement_per_package * payment_factor
        end
     
        #product cost per unit and conversion product calculation
        package_size = Og.where(accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:billing_unit_per_package_size)
        all_payors = ["aetna", "cigna", "humana", "united", "anthem"]
        insurances_list = []
        if charge_class.to_s.strip.casecmp("Inpatient").zero?
          db_cost_per_unit = Og.where(accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:gpo_cost).first.to_f rescue 0.0
          insurances_list =  Og.where(accounting_period_id: accounting_period_id, generic_name_group: group.upcase).pluck(:brand).uniq
        else
          db_cost_per_unit = Og.where(accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:cost_three_forty_b).first.to_f rescue 0.0
          #correct_insurance  = all_payors.find { |p| primary_down.include?(p) }
          correct_insurance = if primary_down.empty?
            all_payors
          else
            all_payors.find { |p| primary_down.include?(p) }
          end
          if primary_down.include?('medicaid') || all_payors.none? { |p| primary_down.include?(p) } 
            insurances_list = Og.where(accounting_period_id: accounting_period_id, generic_name_group: group.upcase).pluck(:brand).uniq
          else
            payor_id = Payor.where(generic_name: group.downcase, name: correct_insurance).pluck(:id).first rescue nil
            insurances_list = Insurance.where(payor_id: payor_id).pluck(:name) if payor_id
          end
          #insurances_list.map!(&:downcase)
          insurances_list = insurances_list.compact.map(&:downcase)
          # Ensure brand is in list
          brand_down = brand_name.downcase
          insurances_list << brand_down unless insurances_list.include?(brand_down)
        end
 
        #checking the conversion criteria for the prefered product
        if conversion_criteria != "preferred_product"
          # Build CMS cost hash dynamically based on charge/financial class
          cms_cost_hash = {}

          insurances_list.each do |insurance|
            query = Og.where(accounting_period_id: accounting_period_id, brand: insurance.capitalize, billing_unit_per_package_size: package_size)

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
                value = query.pluck(:cms_margin_three_forty_b_cost).first.to_f rescue 0.0
              elsif conversion_criteria == "low_cost"
                value = query.pluck(:cost_three_forty_b).first.to_f rescue 0.0
              elsif conversion_criteria == "percent_margin"
                value = query.pluck(:cms_percent_margin).first.to_f rescue 0.0
              end
            end

            cms_cost_hash[insurance] = value
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
          brand = top_pair[0]
          corresponding_value = top_pair[1] # highest cms_margin_340b or lowest gpo/340b_cost


          # Fetch conversion product from Og
          if charge_class.to_s.strip.casecmp("Inpatient").zero?
            calc_conversion_product = Og.where(accounting_period_id: accounting_period_id, brand: brand.capitalize, billing_unit_per_package_size: billing_unit_per_package_size, gpo_cost: corresponding_value)
                                    .pluck(:generic_name).first.to_s rescue ""
          elsif financial_class.to_s.strip.casecmp("Self-Pay").zero?
            if conversion_criteria == "highest_margin" || conversion_criteria == "low_cost"
              calc_conversion_product = Og.where(accounting_period_id: accounting_period_id, brand: brand.capitalize,billing_unit_per_package_size: billing_unit_per_package_size,  cost_three_forty_b: corresponding_value)
                                      .pluck(:generic_name).first.to_s rescue ""
            else
              calc_conversion_product = Og.where(accounting_period_id: accounting_period_id, brand: brand.capitalize, billing_unit_per_package_size: billing_unit_per_package_size, cms_percent_margin: corresponding_value)
                                      .pluck(:generic_name).first.to_s rescue ""
            end
          else
            if conversion_criteria == "highest_margin"
              calc_conversion_product = Og.where(accounting_period_id: accounting_period_id, brand: brand.capitalize, billing_unit_per_package_size: billing_unit_per_package_size, cms_margin_three_forty_b_cost: corresponding_value)
                                      .pluck(:generic_name).first.to_s rescue ""
            elsif conversion_criteria == "low_cost"
              calc_conversion_product = Og.where(accounting_period_id: accounting_period_id, brand: brand.capitalize, billing_unit_per_package_size: billing_unit_per_package_size, cost_three_forty_b: corresponding_value)
                                      .pluck(:generic_name).first.to_s rescue ""
            elsif conversion_criteria == "percent_margin"
              calc_conversion_product = Og.where(accounting_period_id: accounting_period_id, brand: brand.capitalize, billing_unit_per_package_size: billing_unit_per_package_size, cms_percent_margin: corresponding_value)
                                      .pluck(:generic_name).first.to_s rescue ""
            end
          end
          # Compare with extracted
          extracted_conversion_product = text.call(extracted["CONVERSION PRODUCT"])
        else
          extracted_conversion_product = text.call(extracted["CONVERSION PRODUCT"])
          calc_conversion_product = extracted_conversion_product
        end
        match_conversion_product = extracted_conversion_product.downcase == calc_conversion_product.downcase
        #Conversion product cost per unit calculation
        if charge_class.to_s.strip.casecmp("Inpatient").zero?
          val_conv_cost_per_unit = Og.where(accounting_period_id: accounting_period_id, generic_name: extracted_conversion_product).pluck(:gpo_cost).first
          #val_conv_cost_per_unit = Og.pick(:gpo_cost, accounting_period_id: accounting_period_id, generic_name: extracted_conversion_product).to_f rescue 0.0
        else
          val_conv_cost_per_unit = (Og.where(accounting_period_id: accounting_period_id, generic_name: extracted_conversion_product).pluck(:cost_three_forty_b).first || 0).to_f

        end

        # ----------------------------------------
        # STEP 5: Final Comparison + Data Packaging
        # ----------------------------------------
        compare = ->(actual, calc) { (actual - calc).abs < 0.01 }

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
          validated_row[col] = {
            actual: extracted[col],
            calc: calc_value.round(2),
            match: compare.call(actual_val, calc_value)
          }
        end

        # Add Conversion Product result
        validated_row["CONVERSION PRODUCT"] = {
          actual: extracted_conversion_product,
          calc: calc_conversion_product,
          match: match_conversion_product
        }

        @validated_data << validated_row
      end

      render :index
    else
      flash[:alert] = "Please upload an Excel file."
      redirect_to validations_path
    end
  end
end
