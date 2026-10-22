# frozen_string_literal: true

module DatabaseTransfer
  # Links transfer models with the foreign keys PostgreSQL has on those tables.
  #
  # The child model gets belongs_to. The parent gets has_one when the foreign
  # key is unique, and has_many otherwise. Application models are never changed.
  class AssociationBuilder
    def self.apply(models_by_table, connection: ApplicationRecord.connection)
      new(models_by_table, connection).apply
    end

    def initialize(models_by_table, connection)
      @models_by_table = models_by_table
      @connection = connection
    end

    def apply
      models_by_table.each do |table_name, child|
        next unless connection.data_source_exists?(table_name)

        connection.foreign_keys(table_name).each do |foreign_key|
          link(child, table_name, foreign_key)
        end
      end
    end

    private

    attr_reader :models_by_table, :connection

    def link(child, table_name, foreign_key)
      column = foreign_key.column
      return if column.is_a?(Array)

      parent = models_by_table[foreign_key.to_table]
      return unless parent

      singular = unique?(table_name, column)
      belongs_name = belongs_to_name(foreign_key, column).to_sym
      inverse = inverse_name(table_name, foreign_key, column, singular: singular).to_sym
      return if child.reflect_on_association(belongs_name) || parent.reflect_on_association(inverse)

      child.belongs_to belongs_name, **belongs_to_options(parent, foreign_key, column, inverse)
      parent.public_send(singular ? :has_one : :has_many, inverse, **inverse_options(child, foreign_key, column, belongs_name))
    rescue StandardError => error
      Rails.logger.error("[DatabaseTransfer] could not link #{table_name}.#{column} to #{foreign_key.to_table}: #{error.class}: #{error.message}")
    end

    def belongs_to_name(foreign_key, column)
      if column.to_s == conventional_column(foreign_key)
        foreign_key.to_table.to_s.singularize
      else
        column.to_s.delete_suffix("_id")
      end
    end

    def inverse_name(table_name, foreign_key, column, singular:)
      base = if column.to_s == conventional_column(foreign_key) && foreign_key.to_table != table_name
        table_name.to_s
      else
        "#{column.to_s.delete_suffix("_id")}_#{table_name}"
      end
      singular ? base.singularize : base
    end

    def conventional_column(foreign_key)
      "#{foreign_key.to_table.to_s.singularize}_id"
    end

    def belongs_to_options(parent, foreign_key, column, inverse)
      options = {
        class_name: parent.name,
        foreign_key: column.to_s,
        inverse_of: inverse
      }
      options[:primary_key] = foreign_key.primary_key if foreign_key.primary_key.to_s != "id"
      options[:optional] = true if nullable?(foreign_key.from_table, column)
      options
    end

    def inverse_options(child, foreign_key, column, belongs_name)
      options = {
        class_name: child.name,
        foreign_key: column.to_s,
        inverse_of: belongs_name
      }
      options[:primary_key] = foreign_key.primary_key if foreign_key.primary_key.to_s != "id"
      options
    end

    def nullable?(table_name, column)
      connection.columns(table_name).any? { |item| item.name == column.to_s && item.null }
    end

    def unique?(table_name, column)
      expected = [ column.to_s ]
      connection.indexes(table_name).any? { |index| index.unique && Array(index.columns).map(&:to_s) == expected }
    end
  end
end
