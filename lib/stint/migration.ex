defmodule Stint.Migration do
  @moduledoc """
  Versioned migrations for the `stints` table — Oban-style. In your
  application's migration:

      defmodule MyApp.Repo.Migrations.AddStint do
        use Ecto.Migration

        def up, do: Stint.Migration.up()
        def down, do: Stint.Migration.down()
      end

  `up/1` migrates to the latest version and is a no-op for versions
  already applied, so future `stint` releases with schema changes just
  need a fresh migration calling `up/1` again.
  """

  use Ecto.Migration

  @latest 1

  @doc "Migrate the stints table up to `:version` (default: latest)."
  def up(opts \\ []) do
    version = Keyword.get(opts, :version, @latest)
    current = current_version()

    for v <- (current + 1)..version//1 do
      change(v, :up)
    end

    :ok
  end

  @doc "Migrate the stints table down below `:version` (default: all the way)."
  def down(opts \\ []) do
    version = Keyword.get(opts, :version, 1)
    current = current_version()

    for v <- current..version//-1 do
      change(v, :down)
    end

    :ok
  end

  # Version discovery: presence of the table implies at least v1; the
  # comment on the table records the exact version for future bumps.
  # Catalog join (not ::regclass) so a missing table yields zero rows
  # instead of an error that would poison the migration transaction.
  defp current_version do
    result =
      repo().query(
        """
        SELECT obj_description(c.oid, 'pg_class')
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = 'stints' AND n.nspname = 'public'
        """,
        []
      )

    case result do
      {:ok, %{rows: [[version]]}} when is_binary(version) ->
        case Integer.parse(version) do
          {v, _} -> v
          :error -> 1
        end

      # Table exists but no version comment → treat as v1.
      {:ok, %{rows: [[nil]]}} ->
        1

      _ ->
        0
    end
  end

  defp change(1, :up) do
    create_if_not_exists table(:stints) do
      add :owner_id, :string, null: false
      add :item, :string, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :ended_at, :utc_datetime_usec, null: false
      add :seconds, :integer, null: false, default: 0
      add :meta, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    # Stitching lookup: latest stint for (owner, item) by recency.
    create_if_not_exists index(:stints, [:owner_id, :item, :ended_at])
    # Day/range queries across all items.
    create_if_not_exists index(:stints, [:owner_id, :ended_at])

    execute "COMMENT ON TABLE public.stints IS '1'"
  end

  defp change(1, :down) do
    drop_if_exists table(:stints)
  end
end
