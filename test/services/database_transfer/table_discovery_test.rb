# frozen_string_literal: true

require "test_helper"
require_relative "../../support/fake_database_transfer_source"

class DatabaseTransferTableDiscoveryTest < ActiveSupport::TestCase
  test "lists public tables alphabetically and counts them with quoted SQL" do
    source = FakeDatabaseTransferSource.new(
      database: "updated_db",
      tables: [ "ndc_codes", "accounting_periods", "ndc_codes", "" ],
      counts: { "accounting_periods" => 8, "ndc_codes" => "45231" }
    )
    discovery = DatabaseTransfer::TableDiscovery.new(source: source)

    assert_equal "updated_db", discovery.source_database
    assert_equal [ "accounting_periods", "ndc_codes" ], discovery.table_names
    assert_equal [
      { name: "accounting_periods", count: 8 },
      { name: "ndc_codes", count: 45_231 }
    ], discovery.tables_with_counts
    assert_includes source.statements, 'SELECT COUNT(*) FROM "public"."accounting_periods"'
    assert_includes source.statements, 'SELECT COUNT(*) FROM "public"."ndc_codes"'
  end

  test "quotes catalog table names before counting" do
    malicious = 'a"; DROP TABLE users; --'
    connection = DiscoveryRecordingConnection.new(tables: [ malicious ], count: 4)
    source = DatabaseTransfer::Source.new(record_class: discovery_record(connection))

    rows = DatabaseTransfer::TableDiscovery.new(source: source).tables_with_counts

    assert_equal [ { name: malicious, count: 4 } ], rows
    assert_equal(
      'SELECT COUNT(*) FROM "public"."a""; DROP TABLE users; --"',
      connection.statements.grep(/COUNT/).first
    )
    assert_equal 1, connection.statements.grep(/SET LOCAL transaction_read_only = on/).size
  end

  private

  def discovery_record(connection)
    record_class = Class.new do
      class << self
        attr_accessor :connection

        def connection_db_config
          Struct.new(:database).new("sep_22")
        end
      end
    end
    record_class.connection = connection
    record_class
  end
end

class DiscoveryRecordingConnection
  attr_reader :statements

  def initialize(tables:, count:)
    @tables = tables
    @count = count
    @statements = []
    @open = false
  end

  def transaction
    raise "nested transaction" if @open

    @open = true
    yield
  ensure
    @open = false
  end

  def transaction_open?
    @open
  end

  def execute(sql)
    @statements << sql
  end

  def select_all(sql)
    @statements << sql
    @tables.map { |name| { "tablename" => name } }
  end

  def select_value(sql)
    @statements << sql
    @count
  end

  def quote_table_name(name)
    %("#{name.to_s.gsub('"', '""')}")
  end
end
