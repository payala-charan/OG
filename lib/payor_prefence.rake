# lib/tasks/payor_prefence.rake

namespace :payor_prefence do
  desc "Populate PayorPreference table based on Og, Payor, and Insurance data"
  task populate: :environment do
    puts "Populating PayorPreference table..."

    # Conversion configuration
    conversion_map = {
      "highest_margin" => { target_col: "cms_margin_three_forty_b_cost", factor: "max" },
      "low_cost"       => { target_col: "cost_three_forty_b", factor: "min" },
      "percent_margin" => { target_col: "cms_percent_margin", factor: "max" }
    }

    # Strength data
    strength_map = {
      "BEVACIZUMAB" => [10, 40],
      "TRASTUZUMAB" => [15, 42],
      "PEGFILGRASTIM" => [12],
      "FILGRASTIM" => [300, 480],
      "INFLIXIMAB" => [10],
      "RITUXIMAB" => [10, 50],
      "TOCILIZUMAB" => [80, 200, 400]
    }

    PayorPreference.delete_all # optional — clear old data

    Payor.all.each do |payor|
      payor_name = payor.name
      payor_insurances = Insurance.where(payor_id: payor.id).pluck(:name)

      strength_map.each do |group, strengths|
        strengths.each do |strength|
          conversion_map.each do |conversion_type, cfg|
            target_col = cfg[:target_col]
            factor = cfg[:factor]

            values = payor_insurances.each_with_object({}) do |brand, hash|
              og_record = Og.find_by(generic_name_group: group, brand: brand, strength: strength)
              hash[brand] = og_record&.send(target_col)
            end

            next if values.empty? || values.values.all?(&:nil?)

            result =
              if factor == "max"
                values.max_by { |_, v| v.to_f }&.first
              else
                values.min_by { |_, v| v.to_f }&.first
              end

            PayorPreference.create!(
              accounting_period_id: Og.where(generic_name_group: group).pluck(:accounting_period_id).uniq.last,
              generic_name_group: group,
              payor: payor_name,
              insurances: payor_insurances,
              strength: strength,
              conversion_type: conversion_type,
              conversion_target_col: target_col,
              factor: factor,
              values: values,
              result: result
            )

            puts "Created PayorPreference for #{payor_name} - #{group} (#{conversion_type})"
          end
        end
      end
    end

    puts "✅ PayorPreference population completed."
  end
end
    