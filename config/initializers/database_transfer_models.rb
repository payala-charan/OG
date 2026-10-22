# frozen_string_literal: true

# Committed FAT → OG transfers have tables but no app/models file.
# Define those models on boot, and again on each reload in development,
# so the console can call AccountingPeriod.all after a transfer.
Rails.application.config.to_prepare do
  DatabaseTransfer::ModelCatalog.sync!
rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid
  nil
end
