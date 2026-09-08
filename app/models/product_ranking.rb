class ProductRanking < ApplicationRecord
  def self.generate_all_rankings
    # 1. find all unique combinations of (generic_name_group, team_id, accounting_period_id) 
    combinations = NewBiosimilarPrice.select(:generic_name_group, :team_id, :accounting_period_id)
                                     .where.not(generic_name_group: [nil, ""])
                                     .where.not(team_id: [nil, ""])
                                     .where.not(accounting_period_id: nil)
                                     .distinct

    combinations.each do |combo|
      generate_rankings_for(combo.generic_name_group, combo.team_id, combo.accounting_period_id)
    end
  end

  def self.generate_rankings_for(generic_name_group, team_id, accounting_period_id)
    return if generic_name_group.blank? || team_id.blank? || accounting_period_id.blank?

    # 2. find payors matching team_id, accounting_period_id, and generic_name_group
    payors = Payor.where(team_id: team_id, accounting_period_id: accounting_period_id)
                  .where("lower(generic_name) = ?", generic_name_group.to_s.downcase)
    
    payors.each do |payor|
      insurances = payor.insurances.pluck(:name)
      
      results = {}
      all_values = []
      
      insurances.each do |ins|
        # match biosimilar by extracted_brand_name
        bp_records = NewBiosimilarPrice.where(
          generic_name_group: generic_name_group,
          team_id: team_id.to_s,
          accounting_period_id: accounting_period_id
        ).where("lower(extracted_brand_name) = ?", ins.to_s.downcase)
        
        strength_results = {}
        bp_records.each do |bp|
          if bp.extracted_strength.present? && bp.cms_margin_three_forty_b_cost.present?
            strength_results[bp.extracted_strength] = bp.cms_margin_three_forty_b_cost
            all_values << { key: "#{ins}-#{bp.extracted_strength}", val: bp.cms_margin_three_forty_b_cost }
          end
        end
        
        results[ins] = strength_results if strength_results.any?
      end
      
      # 3. compute rankings dynamically
      all_values.sort_by! { |item| -item[:val] }
      rankings = {}
      all_values.each_with_index do |item, idx|
        rankings[item[:key]] = idx + 1
      end
      
      # 4. store
      existing = find_or_initialize_by(
        generic_name_group: generic_name_group,
        team_id: team_id.to_s,
        accounting_period_id: accounting_period_id,
        payor: payor.name
      )
      
      existing.update!(
        insurances: insurances,
        results: results,
        rankings: rankings
      )
    end
  end
end
