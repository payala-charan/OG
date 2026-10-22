# frozen_string_literal: true

module DatabaseTransfer
  # Copies a reviewed plan from FAT into OG.
  #
  # Safety rules:
  # - FAT is read inside one read-only REPEATABLE READ snapshot.
  # - OG is written inside one transaction; any error rolls back every table.
  # - The plan is rebuilt after taking the transfer lock and must match the
  #   fingerprint the user reviewed, so a changed FAT schema or a table that
  #   appeared in OG meanwhile stops the run.
  # - Row counts are checked against the FAT snapshot before commit.
  # - A rehearsal does all of the above and then rolls back.
  class Executor
    class PlanChanged < StandardError; end
    class PlanBlocked < StandardError; end
    class VerificationFailed < StandardError; end
    class RehearsalComplete < StandardError; end

    def initialize(run, source: DatabaseTransfer::Source.new, target: DatabaseTransfer::Target.new, logger: Rails.logger)
      @run = run
      @source = source
      @target = target
      @logger = logger
    end

    def call
      return false unless claim!

      results = nil
      source.with_snapshot do
        target.transaction do |session|
          plan = current_plan(session)
          results = transfer(plan, session)
          raise RehearsalComplete if run.rehearsal?
        end
      end
      target.clear_schema_cache
      finish!(:succeeded, results, "Committed #{results.size} table(s) to #{run.target_database}. They are available in the Rails console.")
      true
    rescue RehearsalComplete
      finish!(:succeeded, results, "Rehearsal passed for #{results.size} table(s). Everything was rolled back.")
      true
    rescue StandardError => error
      logger.error("[DatabaseTransfer] run #{run.id} failed: #{error.class}: #{error.message}\n#{Array(error.backtrace).first(20).join("\n")}")
      fail!(error)
      false
    end

    private

    attr_reader :run, :source, :target, :logger

    # Guards against a job running twice for the same run.
    def claim!
      now = Time.current
      claimed = DatabaseTransferRun.where(id: run.id, status: DatabaseTransferRun.statuses[:pending])
                                   .update_all(status: DatabaseTransferRun.statuses[:running], started_at: now, updated_at: now)
      run.reload
      claimed == 1
    end

    def current_plan(session)
      progress("Re-checking the plan")
      known = DatabaseTransfer::TableDiscovery.new(source: source).table_names
      analysis = DatabaseTransfer::DependencyResolver.new(source: source).resolve(run.selected_tables, known_tables: known)
      plan = DatabaseTransfer::Planner.new(source: source, target: target).build(analysis, catalog: session)

      unless plan.transferable?
        reasons = plan.blockers + plan.blocked_tables.flat_map(&:blockers)
        raise PlanBlocked, "The plan is blocked: #{reasons.join(' ')}"
      end
      if plan.fingerprint != run.plan_fingerprint || plan.table_names != run.planned_tables
        raise PlanChanged, "The FAT schema or the table list changed after the plan was reviewed. Review the plan again."
      end
      plan
    end

    def transfer(plan, session)
      tables = plan.tables
      tables.each do |table|
        progress("Creating #{table.name}")
        create_table(table.definition, session)
      end

      results = tables.each_with_index.map do |table, index|
        progress("Copying #{table.name} (#{index + 1}/#{tables.size})")
        copy_table(table, session)
      end

      tables.each do |table|
        progress("Adding keys and indexes to #{table.name}")
        add_constraints(table.definition, session)
        add_indexes(table.definition, session)
      end

      progress("Adding foreign keys")
      tables.each { |table| add_foreign_keys(table.definition, session) }

      progress("Setting sequences")
      tables.each { |table| reset_sequences(table.definition, session) }

      progress("Verifying row counts")
      results.each { |result| verify!(result, session) }
      results
    end

    def create_table(definition, session)
      definition.sequences.each do |sequence|
        session.execute(<<~SQL.squish)
          CREATE SEQUENCE #{session.qualified(sequence.name)}
          AS #{sequence.data_type}
          INCREMENT BY #{sequence.increment_by}
          MINVALUE #{sequence.min_value}
          MAXVALUE #{sequence.max_value}
          START WITH #{sequence.start_value}
          CACHE #{sequence.cache_size}
          #{sequence.cycle ? "CYCLE" : "NO CYCLE"}
        SQL
      end

      columns = definition.columns.map do |column|
        parts = [ session.quote_identifier(column.name), column.data_type ]
        parts << "DEFAULT #{column.default_sql}" if column.default_sql
        parts << "NOT NULL" if column.not_null
        parts.join(" ")
      end
      session.execute("CREATE TABLE #{session.qualified(definition.name)} (#{columns.join(', ')})")

      definition.sequences.each do |sequence|
        session.execute(
          "ALTER SEQUENCE #{session.qualified(sequence.name)} OWNED BY " \
          "#{session.qualified(definition.name)}.#{session.quote_identifier(sequence.column_name)}"
        )
      end
    end

    def copy_table(table, session)
      name = table.name
      columns = table.definition.column_names
      expected = source.select_value("SELECT COUNT(*) FROM #{source.quote_public_table(name)}").to_i
      copied = session.copy_into(name, columns) do |put|
        source.copy_rows(name, columns) { |row| put.call(row) }
      end
      { "name" => name, "role" => table.role.to_s, "fat_rows" => expected, "rows" => copied }
    end

    def add_constraints(definition, session)
      definition.constraints.each do |constraint|
        session.execute(
          "ALTER TABLE #{session.qualified(definition.name)} " \
          "ADD CONSTRAINT #{session.quote_identifier(constraint.name)} #{constraint.definition}"
        )
      end
    end

    # pg_get_indexdef always names the table as public.<table>; point it at the target.
    def add_indexes(definition, session)
      source_ref = " ON public.#{session.select_value("SELECT quote_ident(#{session.quote(definition.name)})")} USING "
      definition.indexes.each do |index|
        unless index.definition.include?(source_ref)
          raise PlanBlocked, "Could not read the definition of index #{index.name} on #{definition.name}."
        end

        session.execute(index.definition.sub(source_ref, " ON #{session.qualified(definition.name)} USING "))
      end
    end

    def add_foreign_keys(definition, session)
      definition.foreign_keys.each do |foreign_key|
        session.execute(
          "ALTER TABLE #{session.qualified(definition.name)} " \
          "ADD CONSTRAINT #{session.quote_identifier(foreign_key.name)} #{foreign_key.definition}"
        )
      end
    end

    # Continues from FAT's position, or past the highest copied value if that is higher.
    def reset_sequences(definition, session)
      definition.sequences.each do |sequence|
        state = source.select_all(
          "SELECT last_value, is_called FROM #{source.quote_public_table(sequence.name)}"
        ).to_a.first || {}
        fat_value = state["last_value"].to_i
        fat_called = state["is_called"] == true || state["is_called"].to_s == "t"

        value, called = if sequence.increment_by.positive?
          max = session.select_value(
            "SELECT MAX(#{session.quote_identifier(sequence.column_name)}) FROM #{session.qualified(definition.name)}"
          )
          candidates = [ (fat_value if fat_called), max&.to_i ].compact
          candidates.any? ? [ candidates.max, true ] : [ sequence.start_value, false ]
        else
          [ fat_value, fat_called ]
        end

        session.select_value(
          "SELECT setval(#{session.quote(session.qualified(sequence.name))}::regclass, #{Integer(value)}, #{called})"
        )
      end
    end

    def verify!(result, session)
      actual = session.select_value("SELECT COUNT(*) FROM #{session.qualified(result['name'])}").to_i
      result["og_rows"] = actual
      return if actual == result["fat_rows"] && actual == result["rows"]

      raise VerificationFailed,
            "#{result['name']}: FAT has #{result['fat_rows']} rows, copied #{result['rows']}, OG has #{actual}."
    end

    def progress(message)
      run.update_columns(progress_message: message, updated_at: Time.current)
    end

    def finish!(status, results, message)
      run.update!(
        status: status,
        progress_message: message,
        summary: { "tables" => Array(results), "rolled_back" => run.rehearsal? },
        finished_at: Time.current
      )
      return unless status == :succeeded && !run.rehearsal?

      record_migration(message)
      DatabaseTransfer::ModelCatalog.sync!
    end

    def record_migration(message)
      return unless target.schema == "public"

      version = DatabaseTransfer::MigrationWriter.record!(run)
      return if version.blank?

      run.update!(progress_message: "#{message} Rails migration #{version} records the schema and foreign keys.")
    rescue StandardError => error
      logger.error("[DatabaseTransfer] run #{run.id} migration was not written: #{error.class}: #{error.message}")
      run.update!(progress_message: "#{message} The Rails migration could not be written: #{error.message}")
    end

    def fail!(error)
      run.update!(
        status: :failed,
        progress_message: "Failed. Nothing was written to #{run.target_database}.",
        error_message: "#{error.class.name.demodulize}: #{error.message}".truncate(4_000),
        finished_at: Time.current
      )
    rescue StandardError => update_error
      logger.error("[DatabaseTransfer] could not record failure for run #{run.id}: #{update_error.message}")
    end
  end
end
