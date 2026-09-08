class ValidationProcessor
  REQUIRED_COLUMNS = [
    "ORDER_NAME", "NDC CODE", "CHARGE CLASS", "FINANCIAL CLASS",
    "PRIMARY PAYOR NAME", "BENEFIT PLAN NAME", "GROUP", "BRAND NAME", "QUARTER", "PRODUCT COST PER UNIT",
    "TOTAL UNITS", "TOTAL PRODUCT COST", "TOTAL INSURANCE PAYMENT",
    "TOTAL MARGIN", "PERCENT MARGIN", "CONVERSION PRODUCT",
    "CONVERSION PERCENTAGE", "CONVERSION PRODUCT COST PER UNIT",
    "CONVERSION TOTAL PRODUCT COST", "CONVERSION PRODUCT TOTAL INSURANCE PAYMENT",
    "CONVERSION PRODUCT TOTAL MARGIN", "CONVERSION PRODUCT PERCENT MARGIN",
    "BLENDED CONVERSION TOTAL PRODUCT COST", "BLENDED CONVERSION TOTAL MARGIN",
    "BLENDED CONVERSION PERCENT MARGIN", "BLENDED CONVERSION COST DIFFERENCE",
    "BLENDED CONVERSION MARGIN DIFFERENCE", "BLENDED CONVERSION PERCENT MARGIN DIFFERENCE"
  ].freeze

  def initialize(file:, team_id:, conversion_criteria:, user: nil, generic_name_group: nil, quarter: nil)
    @file = file
    @team_id = team_id
    @conversion_criteria = conversion_criteria
    @user = user
    @generic_name_group = generic_name_group
    @quarter_param = quarter
  end

  def call
    spreadsheet = Roo::Spreadsheet.open(@file.path)
    headers = spreadsheet.row(1).map(&:to_s).map(&:strip)
    required_indices = REQUIRED_COLUMNS.map { |col| headers.index(col) }

    display_headers = REQUIRED_COLUMNS.dup
    primary_index = display_headers.index("PRIMARY PAYOR NAME")
    display_headers.insert(primary_index + 1, "PAYOR INSURANCES") if primary_index
    conversion_index = display_headers.index("CONVERSION PRODUCT")
    display_headers.insert(conversion_index + 1, "ALTERNATIVES") if conversion_index

    result_rows = []
    # ValidationRecord.where(user_id: @user&.id).delete_all if @user

    (2..(spreadsheet.last_row - 1)).each do |i|
      row = spreadsheet.row(i)
      extracted = Hash[REQUIRED_COLUMNS.zip(required_indices.map { |idx| row[idx] })]

      clean = ->(val) { val.to_s.gsub(/[\$,()%]/, '').strip.to_f rescue 0.0 }
      text = ->(val) { val.to_s.strip }

      raw_ndc = extracted["NDC CODE"]
      ndc_code = if raw_ndc.is_a?(Float) || raw_ndc.to_s.match?(/\A\d+\.0\z/)
        raw_ndc.to_i.to_s
      else
        raw_ndc.to_s.strip
      end

      primary_payor_name = text.call(extracted["PRIMARY PAYOR NAME"])
      benefit_plan_name = text.call(extracted["BENEFIT PLAN NAME"])
      quarter = text.call(extracted["QUARTER"])
      group = @generic_name_group.present? ? @generic_name_group : text.call(extracted["GROUP"])
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

      # STEP 1: Basic calculations
      calc_total_product_cost = total_units * ppu
      calc_total_margin = total_ins_payment - total_product_cost
      calc_percent_margin = ((calc_total_margin / total_product_cost) * 100).round(1) rescue 0

      calc_conv_total_cost = total_units * conv_cost_per_unit
      calc_conv_total_margin = conv_total_ins - conv_total_cost
      calc_conv_percent_margin = ((calc_conv_total_margin.round(2) / calc_conv_total_cost.round(2)) * 100).round(1) rescue 0

      if conversion_percentage != 100
        per = conversion_percentage.to_f / 100
        calc_blended_total_cost = (per * calc_conv_total_cost.to_f) + ((1 - per) * calc_total_product_cost.to_f)
        calc_blended_total_margin = (per * calc_conv_total_margin.to_f) + ((1 - per) * calc_total_margin.to_f)
        calc_blended_percent_margin = ((calc_blended_total_margin / calc_blended_total_cost) * 100).round(1)
      else
        calc_blended_total_cost = calc_conv_total_cost.to_f
        calc_blended_total_margin = calc_conv_total_margin.to_f
        calc_blended_percent_margin = calc_conv_percent_margin
      end

      calc_blended_cost_diff = calc_blended_total_cost - total_product_cost
      calc_blended_margin_diff = calc_blended_total_margin - total_margin
      calc_blended_percent_margin_diff = calc_blended_percent_margin - percent_margin

      # STEP 2: Total insurance payment validation
      if @quarter_param.present?
        accounting_period_id = @quarter_param.to_i
      else
        quarter_number = quarter[/Quarter\s+(\d)\s+20\d{2}/, 1].to_i
        accounting_period_id =
          case quarter_number
          when 4 then 5
          when 1 then 2
          when 2 then 3
          else 4
          end
      end

      if charge_class.to_s.strip.casecmp("Inpatient").zero?
        calc_total_ins_payment = 0
        calc_conv_total_ins_payment = 0
        billing_unit_per_package_size = NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:billing_unit_per_package_size).first.to_f rescue 0.0
        match = NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:match).first.to_f rescue 0.0
      else
        reimbursement_per_billing_unit = NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:reimbursement_per_billing_unit).first.to_f rescue 0.0
        billing_unit_per_package_size = NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:billing_unit_per_package_size).first.to_f rescue 0.0
        cms_reimbursement_per_package = NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, cost_three_forty_b: conv_cost_per_unit).pluck(:cms_reimbursement_per_package).first.to_f rescue 0.0

        primary_down = primary_payor_name.downcase
        benefit_plan_down = benefit_plan_name.downcase

        if (primary_down.include?("medicare") || primary_down.include?("medicaid")) ||
           (benefit_plan_down.include?("medicare") || benefit_plan_down.include?("medicaid"))
          payment_factor = 1.0
        else
          known_payors = InsuranceFactor.pluck(:benefit_plan_name).compact.uniq.map(&:downcase)
          matched_payor = known_payors.find { |p| benefit_plan_down.include?(p) }
          payment_factor = InsuranceFactor.where(benefit_plan_name: matched_payor&.upcase).pluck(:insurance_factor).first.to_f rescue 1.0
          payment_factor = 1.0 if payment_factor.zero?
        end

        calc_total_ins_payment = total_units * reimbursement_per_billing_unit * billing_unit_per_package_size * payment_factor
        calc_conv_total_ins_payment = total_units * cms_reimbursement_per_package * payment_factor
      end

      # Insurances list fetching based on payor preference
      known_payors = InsuranceFactor.pluck(:benefit_plan_name).compact.uniq.map(&:downcase)
      benefit_plan_down = benefit_plan_name.downcase
      # matched_payor = known_payors.find { |p| benefit_plan_down.include?(p) }
      matched_payor = known_payors.find { |p| p == benefit_plan_down } || known_payors.find { |p| benefit_plan_down.include?(p) }
      final_payor = matched_payor.present? ? matched_payor : "Medipro"

      ins_raw = PayorPreference.where(
        generic_name_group: group.upcase,
        accounting_period_id: accounting_period_id,
        payor: final_payor
      ).pluck(:insurances).first

      insurance_list = ins_raw.present? ? JSON.parse(ins_raw) : []

      package_size = NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:billing_unit_per_package_size)
      all_payors = InsuranceFactor.pluck(:benefit_plan_name).compact.uniq.map(&:downcase)
      insurances_list = []

      if charge_class.to_s.strip.casecmp("Inpatient").zero?
        db_cost_per_unit = NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:gpo_cost).first.to_f rescue 0.0
        insurances_list = NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, generic_name_group: group.upcase).pluck(:extracted_brand_name).uniq
      else
        db_cost_per_unit = NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, ndc_code: ndc_code).pluck(:cost_three_forty_b).first.to_f rescue 0.0

        correct_insurance = if benefit_plan_down.empty?
          all_payors
        else
          all_payors.find { |p| benefit_plan_down.include?(p) }
        end

        if benefit_plan_down.include?("medicaid") || benefit_plan_down.include?("medicare ") || all_payors.none? { |p| benefit_plan_down.include?(p) }
          insurances_list = NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, generic_name_group: group.upcase).pluck(:extracted_brand_name).uniq
        else
          payor_id = Payor.where(generic_name: group.downcase, name: correct_insurance).pluck(:id).first rescue nil
          insurances_list = Insurance.where(payor_id: payor_id).pluck(:name) if payor_id
        end

        insurances_list = insurances_list.compact.map(&:downcase)
        brand_down = brand_name.downcase
        insurances_list << brand_down unless insurances_list.include?(brand_down)
      end

      #conversion rule section
      if @conversion_criteria != "preferred_product"
        cms_cost_hash = {}

        insurances_list.compact.each do |insurance|
          query = NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, extracted_brand_name: insurance.upcase, billing_unit_per_package_size: package_size)

          value = if charge_class.to_s.strip.casecmp("Inpatient").zero?
            query.pluck(:gpo_cost).first.to_f rescue 0.0
          elsif financial_class.to_s.strip.casecmp("Self-Pay").zero?
            if @conversion_criteria == "low_cost" || @conversion_criteria == "highest_margin"
              query.pluck(:cost_three_forty_b).first.to_f rescue 0.0
            elsif @conversion_criteria == "percent_margin"
              query.pluck(:cms_percent_margin).first.to_f rescue 0.0
            end
          else
            if @conversion_criteria == "highest_margin"
              query.pluck(:blended_cms_margin_three_forty_b_cost).first.to_f rescue 0.0
            elsif @conversion_criteria == "low_cost"
              query.pluck(:cost_three_forty_b).first.to_f rescue 0.0
            elsif @conversion_criteria == "percent_margin"
              query.pluck(:blended_cms_340B_percent_margin).first.to_f rescue 0.0
            end
          end

          cms_cost_hash[insurance] = value
        end

        top_pair = if charge_class.to_s.strip.casecmp("Inpatient").zero?
          cms_cost_hash.min_by { |_, v| v } || [nil, 0]
        else
          if financial_class.to_s.strip.casecmp("Self-Pay").zero?
            if @conversion_criteria == "percent_margin"
              cms_cost_hash.max_by { |_, v| v } || [nil, 0]
            else
              cms_cost_hash.min_by { |_, v| v } || [nil, 0]
            end
          else
            if ["highest_margin", "percent_margin"].include?(@conversion_criteria)
              cms_cost_hash.max_by { |_, v| v } || [nil, 0]
            else
              cms_cost_hash.min_by { |_, v| v } || [nil, 0]
            end
          end
        end

        brand = top_pair[0]
        corresponding_value = top_pair[1]

        calc_conversion_product = if charge_class.to_s.strip.casecmp("Inpatient").zero?
          NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand&.upcase, billing_unit_per_package_size: billing_unit_per_package_size, gpo_cost: corresponding_value).pluck(:generic_name).first.to_s rescue ""
        elsif financial_class.to_s.strip.casecmp("Self-Pay").zero?
          if ["highest_margin", "low_cost"].include?(@conversion_criteria)
            NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand&.upcase, billing_unit_per_package_size: billing_unit_per_package_size, cost_three_forty_b: corresponding_value).pluck(:generic_name).first.to_s rescue ""
          else
            NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand&.upcase, billing_unit_per_package_size: billing_unit_per_package_size, blended_cms_340B_percent_margin: corresponding_value).pluck(:generic_name).first.to_s rescue ""
          end
        else
          if @conversion_criteria == "highest_margin"
            NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand&.upcase, billing_unit_per_package_size: billing_unit_per_package_size, blended_cms_margin_three_forty_b_cost: corresponding_value).pluck(:generic_name).first.to_s rescue ""
          elsif @conversion_criteria == "low_cost"
            NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand&.upcase, billing_unit_per_package_size: billing_unit_per_package_size, cost_three_forty_b: corresponding_value).pluck(:generic_name).first.to_s rescue ""
          elsif @conversion_criteria == "percent_margin"
            NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, extracted_brand_name: brand&.upcase, billing_unit_per_package_size: billing_unit_per_package_size, blended_cms_340B_percent_margin: corresponding_value).pluck(:generic_name).first.to_s rescue ""
          end
        end

        extracted_conversion_product = text.call(extracted["CONVERSION PRODUCT"])
        alternatives = []

        cms_cost_hash.each do |other_brand, value|
          alt_product = if charge_class.to_s.strip.casecmp("Inpatient").zero?
            NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, extracted_brand_name: other_brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, gpo_cost: value).pluck(:generic_name).first.to_s rescue ""
          elsif financial_class.to_s.strip.casecmp("Self-Pay").zero?
            if ["highest_margin", "low_cost"].include?(@conversion_criteria)
              NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, extracted_brand_name: other_brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, cost_three_forty_b: value).pluck(:generic_name).first.to_s rescue ""
            else
              NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, extracted_brand_name: other_brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, blended_cms_340B_percent_margin: value).pluck(:generic_name).first.to_s rescue ""
            end
          else
            if @conversion_criteria == "highest_margin"
              NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, extracted_brand_name: other_brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, blended_cms_margin_three_forty_b_cost: value).pluck(:generic_name).first.to_s rescue ""
            elsif @conversion_criteria == "low_cost"
              NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, extracted_brand_name: other_brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, cost_three_forty_b: value).pluck(:generic_name).first.to_s rescue ""
            elsif @conversion_criteria == "percent_margin"
              NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, extracted_brand_name: other_brand.upcase, billing_unit_per_package_size: billing_unit_per_package_size, blended_cms_340B_percent_margin: value).pluck(:generic_name).first.to_s rescue ""
            end
          end

          alternatives << { brand: other_brand, product: alt_product, value: value }
        end
      else
        extracted_conversion_product = text.call(extracted["CONVERSION PRODUCT"])
        calc_conversion_product = extracted_conversion_product
        alternatives = []
      end

      if group.upcase == "FILGRASTIM" && (extracted_conversion_product.to_s.downcase.include?("0.8ml") || extracted_conversion_product.to_s.downcase.include?("1.6ml"))
        calc_conversion_product = extracted_conversion_product
      end

      match_conversion_product = extracted_conversion_product.to_s.downcase == calc_conversion_product.to_s.downcase

      if charge_class.to_s.strip.casecmp("Inpatient").zero?
        val_conv_cost_per_unit = NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, generic_name: extracted_conversion_product).pluck(:gpo_cost).first
      else
        val_conv_cost_per_unit = (NewBiosimilarPrice.where(team_id: @team_id, accounting_period_id: accounting_period_id, generic_name: extracted_conversion_product).pluck(:cost_three_forty_b).first || 0).to_f
      end

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
          calc: calc_value.to_f.round(2),
          match: compare.call(actual_val, calc_value.to_f)
        }
      end

      validated_row["CONVERSION PRODUCT"] = {
        actual: extracted_conversion_product,
        calc: calc_conversion_product,
        match: match_conversion_product
      }
      validated_row["ALTERNATIVES"] = alternatives

      ordered_row = {}
      validated_row.each do |key, value|
        ordered_row[key] = value
        if key == "BENEFIT PLAN NAME"
          ordered_row["PAYOR INSURANCES"] = insurance_list
        elsif key == "CONVERSION PRODUCT"
          ordered_row["ALTERNATIVES"] = alternatives
        end
      end

      validated_row = ordered_row
      result_rows << validated_row
      if @user
        ValidationRecord.create!(data: validated_row, user_id: @user.id, user_email: @user.email)
      else
        AutoValidateRecord.create!(data: validated_row, file: @file.original_filename)
      end
    end

    Rails.logger.info "Validation completed for Team #{@team_id} (#{result_rows.size} rows)"

    { headers: display_headers, validated_data: result_rows }
  end
end
