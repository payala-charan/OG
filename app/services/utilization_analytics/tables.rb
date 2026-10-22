# frozen_string_literal: true

module UtilizationAnalytics
  # Resolves the analytics tables without depending on where the model class
  # was defined. Transferred tables are published by DatabaseTransfer::ModelCatalog;
  # application models such as NewBiosimilarPrice stay in app/models.
  module Tables
    module_function

    def utilization_reports
      relation("utilization_reports")
    end

    def purchase_histories
      relation("purchase_histories")
    end

    def new_biosimilar_prices
      relation("new_biosimilar_prices")
    end

    def primary_payors
      relation("primary_payors")
    end

    def relation(table_name)
      const_name = table_name.to_s.classify
      return Object.const_get(const_name, false) if Object.const_defined?(const_name, false)

      if DatabaseTransfer::Models.const_defined?(const_name, false)
        return DatabaseTransfer::Models.const_get(const_name, false)
      end

      registry[table_name] ||= Class.new(ApplicationRecord) { self.table_name = table_name }
    end

    def registry
      @registry ||= {}
    end
  end
end
