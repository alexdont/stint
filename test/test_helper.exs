defmodule Stint.TestRepo do
  use Ecto.Repo,
    otp_app: :stint,
    adapter: Ecto.Adapters.Postgres
end

defmodule Stint.TestMigration do
  use Ecto.Migration

  def up, do: Stint.Migration.up()
  def down, do: Stint.Migration.down()
end

# The configured database must already exist (the default config
# points at this dev box's database; override via STINT_TEST_DB_*).
{:ok, _} = Stint.TestRepo.start_link()

Ecto.Migrator.run(Stint.TestRepo, [{0, Stint.TestMigration}], :up, all: true, log: false)

Ecto.Adapters.SQL.Sandbox.mode(Stint.TestRepo, :manual)
ExUnit.start()
