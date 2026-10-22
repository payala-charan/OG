# frozen_string_literal: true

require "test_helper"

class DatabaseTransferSourceTest < ActiveSupport::TestCase
  test "reads the database name from the connection config" do
    source = build_source(RecordingFatConnection.new)

    assert_equal "updated_db", source.database_name
  end

  test "rejects writes and stacked statements before they reach the connection" do
    connection = RecordingFatConnection.new
    source = build_source(connection)

    assert_raises(ArgumentError) { source.select_value("DELETE FROM users") }
    assert_raises(ArgumentError) { source.select_value("SELECT 1; DELETE FROM users") }
    assert_empty connection.statements
  end

  test "allows a semicolon that is inside a quoted identifier" do
    connection = RecordingFatConnection.new
    source = build_source(connection)
    sql = 'SELECT COUNT(*) FROM "public"."a""; DROP TABLE users; --"'

    assert_equal 7, source.select_value(sql)
    assert_includes connection.statements, "SET LOCAL transaction_read_only = on"
    assert_includes connection.statements, sql
  end

  test "a snapshot is one read-only repeatable read transaction" do
    connection = RecordingFatConnection.new
    source = build_source(connection)

    source.with_snapshot { source.select_value("SELECT 1") }

    assert_equal :repeatable_read, connection.isolation
    assert_equal [ "SET LOCAL transaction_read_only = on", "SELECT 1" ], connection.statements
  end

  test "a snapshot cannot join an open transaction" do
    connection = RecordingFatConnection.new
    source = build_source(connection)

    connection.transaction do
      assert_raises(ArgumentError) { source.with_snapshot { } }
    end
  end

  test "copying rows requires an open transaction" do
    source = build_source(RecordingFatConnection.new)

    assert_raises(ArgumentError) { source.copy_rows("users", [ "id" ]) { } }
  end

  private

  def build_source(connection)
    record_class = Class.new do
      class << self
        attr_accessor :connection

        def connection_db_config
          Struct.new(:database).new("updated_db")
        end
      end
    end
    record_class.connection = connection
    DatabaseTransfer::Source.new(record_class: record_class)
  end
end

class RecordingFatConnection
  attr_reader :statements, :isolation

  def initialize
    @statements = []
    @open = false
  end

  def transaction(isolation: nil)
    raise "nested transaction" if @open

    @isolation = isolation
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
    []
  end

  def select_value(sql)
    @statements << sql
    7
  end

  def quote_table_name(name)
    %("#{name.to_s.gsub('"', '""')}")
  end
end
