# frozen_string_literal: true

module DatabaseTransfersHelper
  LARGE_TABLE_THRESHOLD = 100_000

  STATUS_LABELS = {
    selected: "User Selected",
    required: "Automatically Required",
    referencing: "References selection"
  }.freeze

  def large_database_table?(count)
    count.to_i >= LARGE_TABLE_THRESHOLD
  end

  def database_transfer_status_label(status)
    STATUS_LABELS[status]
  end

  def database_transfer_console_model(table_name)
    DatabaseTransfer::ModelCatalog.console_constant(table_name)
  end
end
