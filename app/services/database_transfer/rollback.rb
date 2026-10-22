# frozen_string_literal: true

module DatabaseTransfer
  # Drops the tables a committed transfer created in OG.
  #
  # Parents are listed first on the run, and tables in the same run can
  # reference each other, so they are dropped in one statement. A later
  # committed transfer that lists the same tables, or any OG table outside
  # this run that points at them, stops the rollback with nothing dropped.
  class Rollback
    class Blocked < StandardError; end

    def initialize(run, target: DatabaseTransfer::Target.new)
      @run = run
      @target = target
    end

    def call
      ensure_rollbackable!

      target.transaction do |session|
        owners = later_runs.select { |other| (Array(other.planned_tables).map(&:to_s) & tables).any? }
        if owners.any?
          shared = owners.flat_map { |other| Array(other.planned_tables).map(&:to_s) } & tables
          raise Blocked, "Roll back transfer #{owners.map { |other| "##{other.id}" }.join(', ')} first. " \
                         "It also committed #{shared.join(', ')}."
        end

        dependents = external_dependents(session)
        if dependents.any?
          raise Blocked, "Other tables still reference this transfer: #{dependents.join(', ')}. " \
                         "Roll those back first."
        end

        quoted = tables.map { |name| session.qualified(name) }.join(", ")
        session.execute("DROP TABLE IF EXISTS #{quoted}")
      end

      target.clear_schema_cache
      MigrationWriter.revert!(run) if target.schema == "public"
      record!
      ModelCatalog.sync!
      true
    rescue Target::LockUnavailable => error
      raise Blocked, error.message
    rescue ActiveRecord::StatementInvalid => error
      raise Blocked, "Could not drop the tables. #{error.message}"
    end

    private

    attr_reader :run, :target

    def ensure_rollbackable!
      if run.rolled_back?
        raise Blocked, "These tables were already rolled back."
      end
      if run.rehearsal?
        raise Blocked, "A rehearsal keeps nothing, so there are no tables to roll back."
      end
      unless run.succeeded?
        raise Blocked, "Only a committed transfer can be rolled back."
      end
      if tables.empty?
        raise Blocked, "This transfer has no tables to drop."
      end
      if DatabaseTransferRun.active.exists?
        raise Blocked, "Another transfer is waiting or running. Wait for it to finish before rolling back."
      end
    end

    def tables
      Array(run.planned_tables).map(&:to_s)
    end

    def later_runs
      DatabaseTransferRun.succeeded.where(rehearsal: false).where("id > ?", run.id)
    end

    def external_dependents(session)
      values = tables.map { |name| session.quote(name) }.join(", ")
      schema = session.quote(session.schema)
      session.select_values(<<~SQL)
        SELECT DISTINCT src.relname
        FROM pg_constraint con
        INNER JOIN pg_class src ON src.oid = con.conrelid
        INNER JOIN pg_namespace sn ON sn.oid = src.relnamespace
        INNER JOIN pg_class dst ON dst.oid = con.confrelid
        INNER JOIN pg_namespace dn ON dn.oid = dst.relnamespace
        WHERE con.contype = 'f'
          AND dn.nspname = #{schema}
          AND dst.relname IN (#{values})
          AND NOT (sn.nspname = #{schema} AND src.relname IN (#{values}))
        ORDER BY src.relname
      SQL
    end

    def record!
      run.update!(
        status: :rolled_back,
        progress_message: "Dropped #{tables.size} table(s) from #{run.target_database}.",
        summary: run.summary.merge(
          "user_rolled_back" => true,
          "rolled_back_at" => Time.current.iso8601
        )
      )
    end
  end
end
