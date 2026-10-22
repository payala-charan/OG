# frozen_string_literal: true

module DatabaseTransfer
  # Defines Active Record models for tables a committed transfer created in OG.
  #
  # The transfer writes tables with SQL, so Rails has no app/models file for
  # them. Models live under DatabaseTransfer::Models. When the top-level name
  # is not already an application model, the same class is also available as
  # PurchaseHistory. Foreign keys between transferred tables become belongs_to
  # and has_many / has_one, so the tables are not independent.
  class ModelCatalog
    MUTEX = Mutex.new

    def self.sync!
      MUTEX.synchronize { sync_unlocked }
    end

    def self.reset!
      MUTEX.synchronize { remove_all_unlocked }
    end

    # "accounting_periods" => "AccountingPeriod"
    def self.constant_name_for(table_name)
      name = table_name.to_s.classify
      name if name.match?(/\A[A-Z][A-Za-z0-9_]*\z/)
    end

    # Name to type in the console. Application models keep their own class.
    def self.console_constant(table_name)
      const_name = constant_name_for(table_name)
      return if const_name.blank?
      return "DatabaseTransfer::Models::#{const_name}" if application_owned?(const_name)

      const_name
    end

    def self.sync_unlocked
      return false unless runs_ready?

      wanted = committed_table_names & existing_tables
      keep = []
      models = {}

      wanted.each do |table_name|
        const_name = constant_name_for(table_name)
        next unless const_name

        model = define_model(table_name, const_name)
        models[table_name] = model
        keep << const_name
      rescue StandardError => error
        Rails.logger.error("[DatabaseTransfer] could not define #{const_name} for #{table_name}: #{error.class}: #{error.message}")
      end

      AssociationBuilder.apply(models)
      (registry - keep).each { |const_name| remove_const_if_ours(const_name) }
      registry.replace(keep)
      true
    end

    def self.runs_ready?
      ApplicationRecord.connection.data_source_exists?(DatabaseTransferRun.table_name)
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
      false
    end

    def self.committed_table_names
      DatabaseTransferRun.succeeded.where(rehearsal: false).pluck(:planned_tables)
                         .flatten.map(&:to_s).uniq
    end

    def self.existing_tables
      ApplicationRecord.connection.tables
    end

    def self.application_owned?(const_name)
      return true if Rails.root.join("app/models/#{const_name.underscore}.rb").exist?
      return false unless Object.const_defined?(const_name, false)

      !transferred_model?(Object.const_get(const_name, false))
    end

    def self.define_model(table_name, const_name)
      model = reusable_model(const_name, table_name)
      unless model
        remove_const_if_ours(const_name)
        model = Class.new(ApplicationRecord) do
          self.table_name = table_name
          self.inheritance_column = nil
        end
        model.define_singleton_method(:database_transfer_model?) { true }
        DatabaseTransfer::Models.const_set(const_name, model)
        model.connection.schema_cache.clear_data_source_cache!(table_name)
        model.reset_column_information
      end

      publish_top_level(const_name, model)
      model
    end

    def self.reusable_model(const_name, table_name)
      return unless DatabaseTransfer::Models.const_defined?(const_name, false)

      model = DatabaseTransfer::Models.const_get(const_name, false)
      return unless transferred_model?(model)
      return unless model.table_name == table_name && model.superclass == ApplicationRecord

      model
    end

    def self.publish_top_level(const_name, model)
      if application_owned?(const_name)
        remove_top_level_if_ours(const_name)
        return
      end
      return if Object.const_defined?(const_name, false) && Object.const_get(const_name, false).equal?(model)

      remove_top_level_if_ours(const_name)
      Object.const_set(const_name, model) unless Object.const_defined?(const_name, false)
    end

    def self.transferred_model?(model)
      model.is_a?(Class) && model.respond_to?(:database_transfer_model?) && model.database_transfer_model?
    end

    def self.remove_all_unlocked
      registry.dup.each { |const_name| remove_const_if_ours(const_name) }
      registry.clear
    end

    def self.remove_const_if_ours(const_name)
      remove_top_level_if_ours(const_name)
      return unless DatabaseTransfer::Models.const_defined?(const_name, false)
      return unless transferred_model?(DatabaseTransfer::Models.const_get(const_name, false))

      DatabaseTransfer::Models.send(:remove_const, const_name)
    end

    def self.remove_top_level_if_ours(const_name)
      return unless Object.const_defined?(const_name, false)
      return unless transferred_model?(Object.const_get(const_name, false))

      Object.send(:remove_const, const_name)
    end

    # config.x returns a blank options object on first read, so assign the array explicitly.
    def self.registry
      names = Rails.application.config.x.database_transfer_model_names
      return names if names.is_a?(Array)

      Rails.application.config.x.database_transfer_model_names = []
    end

    private_class_method :sync_unlocked, :runs_ready?, :committed_table_names, :existing_tables,
                         :application_owned?, :define_model, :reusable_model, :publish_top_level,
                         :transferred_model?, :remove_all_unlocked, :remove_const_if_ours,
                         :remove_top_level_if_ours, :registry
  end
end
