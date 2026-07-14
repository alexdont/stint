import Config

if config_env() == :test do
  # Defaults target this dev box's database directly (NOT through
  # pgbouncer — transaction pooling breaks Ecto's SQL sandbox).
  # Override via env vars on any other machine / CI.
  config :stint, Stint.TestRepo,
    hostname: System.get_env("STINT_TEST_DB_HOST", "postgres"),
    port: String.to_integer(System.get_env("STINT_TEST_DB_PORT", "5432")),
    database: System.get_env("STINT_TEST_DB_NAME", "dev_habit_tracker_db"),
    username: System.get_env("STINT_TEST_DB_USER", "dev_habit_tracker_user"),
    password: System.get_env("STINT_TEST_DB_PASS", "cvBmFlxMvzvUaHqUN3SYSqsX4Zqxa20Z"),
    pool: Ecto.Adapters.SQL.Sandbox

  config :stint, ecto_repos: [Stint.TestRepo]
  config :stint, repo: Stint.TestRepo
end
