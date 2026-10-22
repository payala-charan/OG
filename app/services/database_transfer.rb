# frozen_string_literal: true

# FAT → OG database transfer toolkit.
#
# Analysis (read-only): TableDiscovery, DependencyResolver, Analysis.
# Planning (read-only): SchemaReader, Planner, Plan.
# Transfer: Executor copies a reviewed plan inside one OG transaction, started
# by Dispatcher and recorded in DatabaseTransferRun.
# ModelCatalog defines console models for committed tables and links them
# through the foreign keys copied from FAT. MigrationWriter records that
# schema in db/migrate and db/schema.rb.
# Rollback drops the tables from one committed run.
#
# FAT is a source database. Transfer code may write only to the OG primary
# database, through Target, and only by creating new tables.
module DatabaseTransfer
end
