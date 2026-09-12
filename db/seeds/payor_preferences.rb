# db/seeds/payor_preferences.rb
# puts "🚀 payor_preferences.rb file is running..."

# mapping = {
#   "highest_margin" => { target_col: "cms_margin_three_forty_b_cost", factor: "max" },
#   "low_cost" => { target_col: "cost_three_forty_b", factor: "min" },
#   "percent_margin" => { target_col: "cms_percent_margin", factor: "max" }
# }

# Og.pluck(:accounting_period_id).uniq.each do |period_id|
#   Og.where(accounting_period_id: period_id).pluck(:generic_name_group).uniq.each do |group|
#     # -------------------------
#     # ✅ Existing Payors Logic
#     # -------------------------
#     Payor.where(generic_name: group.downcase).each do |payor|
#       insurances = Insurance.where(payor_id: payor.id).pluck(:name)
#       next if insurances.empty?

#       strengths = Og.where(generic_name_group: group).pluck(:billing_unit_per_package_size).uniq
#       strengths.each do |strength|
#         mapping.each do |conversion_type, config|
#           target_col = config[:target_col]
#           factor = config[:factor]

#           values = {}
#           insurances.each do |brand|
#             val = Og.where(
#               generic_name_group: group,
#               brand: brand.capitalize,
#               billing_unit_per_package_size: strength,
#               accounting_period_id: period_id
#             ).pluck(target_col).compact.first
#             values[brand] = val if val
#           end

#           next if values.empty?

#           result_brand, _val =
#             factor == "max" ? values.max_by { |_, v| v.to_f } : values.min_by { |_, v| v.to_f }

#           PayorPreference.create!(
#             accounting_period_id: period_id,
#             generic_name_group: group,
#             payor: payor.name,
#             insurances: insurances,
#             strength: strength,
#             conversion_type: conversion_type,
#             conversion_target_col: target_col,
#             factor: factor,
#             values: values,
#             result: result_brand
#           )
#         end
#       end
#     end

#     # -------------------------
#     # 🧠 New "Medipro" Logic
#     # -------------------------
#     puts "✨ Generating Medipro payor preferences for #{group} (Period #{period_id})..."

#     all_brands = Og.where(generic_name_group: group).pluck(:brand).compact.uniq
#     next if all_brands.empty?

#     strengths = Og.where(generic_name_group: group).pluck(:billing_unit_per_package_size).uniq
#     strengths.each do |strength|
#       mapping.each do |conversion_type, config|
#         target_col = config[:target_col]
#         factor = config[:factor]

#         values = {}
#         all_brands.each do |brand|
#           val = Og.where(
#             generic_name_group: group,
#             brand: brand.capitalize,
#             billing_unit_per_package_size: strength,
#             accounting_period_id: period_id
#           ).pluck(target_col).compact.first
#           values[brand] = val if val
#         end

#         next if values.empty?

#         result_brand, _val =
#           factor == "max" ? values.max_by { |_, v| v.to_f } : values.min_by { |_, v| v.to_f }

#         PayorPreference.create!(
#           accounting_period_id: period_id,
#           generic_name_group: group,
#           payor: "Medipro",
#           insurances: all_brands,
#           strength: strength,
#           conversion_type: conversion_type,
#           conversion_target_col: target_col,
#           factor: factor,
#           values: values,
#           result: result_brand
#         )
#       end
#     end
#   end
# end

# puts "✅ Payor preferences generated successfully!"


puts "🚀 payor_preferences.rb file is running..."

mapping = {
  "highest_margin" => { target_col: "blended_cms_margin_three_forty_b_cost", factor: "max" },
  "low_cost" => { target_col: "cost_three_forty_b", factor: "min" },
  "percent_margin" => { target_col: "blended_cms_percent_margin", factor: "max" }
}
team_id = "198"
accounting_period_ids = [ 7 ]
# NewBiosimilarPrice.pluck(:accounting_period_id).uniq.each do |period_id|
accounting_period_ids.each do |period_id|
  NewBiosimilarPrice.where(accounting_period_id: period_id, team_id: team_id).pluck(:generic_name_group).compact.uniq.each do |group|
    # -------------------------
    # ✅ Existing Payors Logic
    # -------------------------
    Payor.where(generic_name: group.downcase, team_id: team_id, accounting_period_id: period_id).each do |payor|
      insurances = Insurance.where(payor_id: payor.id).pluck(:name)
      next if insurances.empty?

      strengths = NewBiosimilarPrice.where(generic_name_group: group).pluck(:billing_unit_per_package_size).compact.uniq
      strengths.each do |strength|
        mapping.each do |conversion_type, config|
          target_col = config[:target_col]
          factor = config[:factor]

          values = {}
          insurances.each do |brand|
            val = NewBiosimilarPrice.where(
              generic_name_group: group,
              extracted_brand_name: brand.upcase,
              billing_unit_per_package_size: strength,
              accounting_period_id: period_id
            ).pluck(target_col).compact.first
            values[brand] = val if val
          end

          next if values.empty?

          result_brand, _val =
            factor == "max" ? values.max_by { |_, v| v.to_f } : values.min_by { |_, v| v.to_f }

          PayorPreference.create!(
            accounting_period_id: period_id,
            generic_name_group: group,
            payor: payor.name,
            insurances: insurances,
            strength: strength,
            conversion_type: conversion_type,
            conversion_target_col: target_col,
            factor: factor,
            values: values,
            result: result_brand,
            team_id: team_id
          )
        end
      end
    end

    # -------------------------
    # 🧠 New "Medipro" Logic
    # -------------------------
    puts "✨ Generating Medipro payor preferences for #{group} (Period #{period_id})..."

    all_brands = NewBiosimilarPrice.where(generic_name_group: group).pluck(:extracted_brand_name).compact.uniq
    next if all_brands.empty?

    strengths = NewBiosimilarPrice.where(generic_name_group: group).pluck(:billing_unit_per_package_size).uniq
    strengths.each do |strength|
      mapping.each do |conversion_type, config|
        target_col = config[:target_col]
        factor = config[:factor]

        values = {}
        all_brands.each do |brand|
          val = NewBiosimilarPrice.where(
            generic_name_group: group,
            extracted_brand_name: brand.upcase,
            billing_unit_per_package_size: strength,
            accounting_period_id: period_id
          ).pluck(target_col).compact.first
          values[brand] = val if val
        end

        next if values.empty?

        result_brand, _val =
          factor == "max" ? values.max_by { |_, v| v.to_f } : values.min_by { |_, v| v.to_f }

        PayorPreference.create!(
          accounting_period_id: period_id,
          generic_name_group: group,
          payor: "Medipro",
          insurances: all_brands,
          strength: strength,
          conversion_type: conversion_type,
          conversion_target_col: target_col,
          factor: factor,
          values: values,
          result: result_brand,
          team_id: team_id
        )
      end
    end
  end
end

puts "✅ Payor preferences generated successfully!"
