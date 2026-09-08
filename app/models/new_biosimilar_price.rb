class NewBiosimilarPrice < ApplicationRecord
    def self.extract_brand_and_strength_debug
        target_groups = [ "BEVACIZUMAB", "TRASTUZUMAB", "HYALURONATE SODIUM", "DENOSUMAB", "PEGFILGRASTIM", "FILGRASTIM", "INFLIXIMAB", "RITUXIMAB", "TOCILIZUMAB", "BENDAMUSTINE", "LEUPROLIDE ACETATE" ]

        NewBiosimilarPrice.where(team_id: "209", accounting_period_id: 7, status: nil).find_each do |record|
            next unless target_groups.map(&:upcase).include?(record.generic_name_group.to_s.upcase)
            puts "\n=============================="
            puts "🔍 RECORD ID: #{record.id}"
            puts "GROUP: #{record.generic_name_group}"

            raw = record.generic_name
            puts "RAW: #{raw.inspect}"

            # -------------------------
            # 1. NORMALIZE
            # -------------------------
            generic = raw.to_s.encode("UTF-8", invalid: :replace, undef: :replace)
                        .gsub(/\u00A0/, " ")
                        .gsub(/[\r\n\t]/, " ")
                        .gsub(/\s+/, " ")
                        .strip

            puts "CLEANED: #{generic.inspect}"

            # REMOVE NOISE
            generic = generic.gsub(/\(DO NOT CONVERT\)/i, "")
                            .gsub(/\(weekly\s*x\s*\d+\)/i, "")
                            .strip

            puts "AFTER NOISE REMOVAL: #{generic.inspect}"

            # -------------------------
            # 2. BRAND EXTRACTION
            # -------------------------
            bracket_values = generic.scan(/\(([^)]+)\)/).flatten
            puts "BRACKET VALUES: #{bracket_values.inspect}"

            brand = bracket_values.first
            puts "EXTRACTED BRAND (RAW): #{brand.inspect}"

            brand = brand&.gsub(/\b\d+\s*(months?|weeks?|days?)\b/i, "")&.strip
            puts "CLEANED BRAND: #{brand.inspect}"

            brand = record.generic_name_group if brand.blank?
            # SPECIAL CASES
            if generic.match?(/Pegfilgrastim-CBQV\s*\(Udenyca\)\s*6mg\/0\.6ml\s*OnBody/i)
                brand = "UDENYCA ONBODY"
            end
            if generic.match?(/Pegfilgrastim-CBQV/i) && generic.match?(/OnBody/i)
                brand = "UDENYCA ONBODY"
            end
            if generic.match?(%r{Pegfilgrastim\s*\(Neulasta\)\s*6mg/0\.6ml\s*Onpro\s*Kit}i)
                brand = "NEULASTA ONPRO KIT"
            end
            puts "FINAL BRAND: #{brand.inspect}"

            # -------------------------
            # 3. STRENGTH EXTRACTION
            # -------------------------
            normalized = generic.downcase
                                .gsub(/\s*\/\s*/, "/")
                                .gsub(/\s*(mg|mcg|g|ml)\b/, '\1')

            puts "NORMALIZED STRING: #{normalized.inspect}"

            strength = nil

            pattern1 = normalized[/\d+(?:\.\d+)?(?:mg|mcg|g)\/\d+(?:\.\d+)?ml/]
            puts "PATTERN1 (100mg/4ml): #{pattern1.inspect}"
            strength ||= pattern1

            pattern2 = normalized[/\d+(?:\.\d+)?(?:mg|mcg|g)\/ml/]
            puts "PATTERN2 (25mg/ml): #{pattern2.inspect}"
            strength ||= pattern2

            pattern3 = normalized[/\d+(?:\.\d+)?(?:mg|mcg|g|ml)/]
            puts "PATTERN3 (single): #{pattern3.inspect}"
            strength ||= pattern3

            fallback = normalized.scan(/\d+(?:\.\d+)?[a-zA-Z]+/).first
            puts "FALLBACK: #{fallback.inspect}"
            strength ||= fallback

            final_strength = strength&.upcase
            puts "FINAL STRENGTH: #{final_strength.inspect}"

            # -------------------------
            # 4. SAVE (optional for debug)
            # -------------------------
            puts "➡️ WILL SAVE:"
            puts "BRAND: #{brand&.upcase}"
            puts "STRENGTH: #{final_strength}"

            # comment this while debugging if needed
            record.update(
            extracted_brand_name: brand&.upcase,
            extracted_strength: final_strength
            )

            puts "==============================\n"
        end
    end

    # ✅ INSTANCE METHOD (per record)
    def extract_and_store_insurances
        return if insurances.blank?
        cleaned = insurances
                    .split(",")
                    .map(&:strip)
                    .reject(&:blank?)
                    .uniq
        update_column(:extracted_insurances, cleaned)
    end
    # ✅ CLASS METHOD (runs for records matching team_id and accounting_period_id)
    def self.extract_all_insurances(team_id = "209", accounting_period_id = 7)
        where(team_id: team_id, accounting_period_id: accounting_period_id)
          .where.not(insurances: [ nil, "" ]).find_each do |record|
            record.extract_and_store_insurances
        end
    end

    def self.build_payor_insurance_mapping
        # Step 1: Get all groups
        groups = NewBiosimilarPrice.pluck(:generic_name_group).compact.uniq
        team_id = "209"
        accounting_period_id = 7
        # Step 2: Get all payors
        payors = InsuranceFactor.pluck(:benefit_plan_name).compact.uniq
        groups.each do |group|
            payors.each do |payor|
                matching_brands = []

                # Step 3: Filter records by group
                records = NewBiosimilarPrice.where(generic_name_group: group, team_id: team_id, accounting_period_id: accounting_period_id)

                records.each do |record|
                    # assuming insurances column is JSON array
                    raw_insurances = record.extracted_insurances
                    insurances =
                    if raw_insurances.nil?
                        []
                    elsif raw_insurances.is_a?(String)
                        JSON.parse(raw_insurances) rescue []
                    elsif raw_insurances.is_a?(Array)
                        raw_insurances
                    else
                        []
                    end

                    insurances = insurances.compact.map { |i| i.to_s.downcase }
                    payor_down = payor.downcase

                    # Step 4: Check if payor exists
                    if insurances.any? { |ins| ins.strip.downcase == payor_down.strip.downcase }
                        matching_brands << record.extracted_brand_name
                    end
                end

                # Step 5: Unique brands
                unique_brands = matching_brands.compact.uniq

                next if unique_brands.empty?

                # Step 6: Create Payor
                payor_record = Payor.find_or_create_by!(
                    name: payor.downcase,
                    generic_name: group.downcase,
                    team_id: team_id,
                    accounting_period_id: accounting_period_id
                )

                # Step 7: Create Insurances
                unique_brands.each do |brand|
                    Insurance.find_or_create_by!(
                        name: brand.downcase,
                        payor_id: payor_record.id
                    )
                end
            end
        end

        puts "✅ Payor & Insurance mapping completed!"
    end
end
