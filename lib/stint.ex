defmodule Stint do
  @moduledoc """
  Tick-based activity session tracking. No start/stop calls — report
  elapsed time as it happens, and *stints* (bounded periods of
  activity) assemble themselves.

      # on every activity ping (a reader's progress tick, a player's
      # watch-time beat, a practice timer):
      Stint.track(user_id, "manga:mangadex/one-piece", 30)

  If the owner's latest stint on that item ended within the gap window
  (default 5 minutes), the tick **extends** it — `ended_at` moves to
  now, `seconds` accumulates. A longer silence means the next tick
  **opens a new stint**. That inference is the whole point: session
  *ends* are unobservable in real apps (tabs close, phones lock,
  processes die), while periodic ticks are easy and reliable. A
  "session" stops being an API anyone can forget to call and becomes
  an emergent fact of the data.

  Each stint carries second-resolution `started_at` / `ended_at`, so
  the data distinguishes one two-hour binge from six three-minute
  peeks — not just "N minutes in hour H".

  ## Setup

      config :stint, repo: MyApp.Repo

  And a migration:

      def up, do: Stint.Migration.up()
      def down, do: Stint.Migration.down()

  ## Identity

  `owner_id` and `item` are opaque strings — a user UUID, a device id,
  `"manga:source/slug"`, `"habit:guitar"` — the library never
  interprets them.

  ## Options

    * `:gap` — seconds of silence that split stints (default `300`,
      configurable app-wide via `config :stint, default_gap: n`)
    * `:min` — stints whose accumulated seconds stay below this are
      hidden from the query functions and garbage-collected once a
      newer stint opens on the same item (default `0`, configurable
      app-wide via `config :stint, default_min: n`). Recording is
      never blocked: a blink-and-close open still writes its stint —
      ticks are often tiny and must accumulate, and a quick return
      within the gap extends the ghost into a real session — it just
      isn't *remembered* if it never grows past the minimum.
    * `:at` — the tick's timestamp (default `DateTime.utc_now/0`)
    * `:meta` — map shallow-merged into the stint's `meta` on every
      tick (last write wins per key)

  Timezone-aware day queries take `:utc_offset` in seconds (e.g. a
  UTC+2 user is `utc_offset: 7200`).
  """

  import Ecto.Query

  alias Stint.Record

  @default_gap 300
  @default_min 0

  @type owner :: String.t()
  @type item :: String.t()

  ## ── Recording ─────────────────────────────────────────────────────

  @doc """
  Record `seconds` of activity by `owner` on `item`.

  Extends the latest stint when its end is within the gap window of
  `:at`; opens a new stint otherwise (with `started_at` back-dated by
  `seconds`, so the first tick doesn't lose its own duration).
  Opening a new stint garbage-collects the item's earlier stints that
  never accumulated `:min` seconds — see the `:min` option.

  Returns `{:ok, stint, :extended | :started}`.
  """
  @spec track(owner, item, non_neg_integer, keyword) ::
          {:ok, Record.t(), :extended | :started} | {:error, term}
  def track(owner, item, seconds, opts \\ [])
      when is_binary(owner) and is_binary(item) and is_integer(seconds) do
    seconds = max(seconds, 0)
    # Normalize to microsecond precision — the columns are
    # utc_datetime_usec and caller-supplied :at values often aren't.
    now = DateTime.add(Keyword.get(opts, :at) || DateTime.utc_now(), 0, :microsecond)
    gap = Keyword.get(opts, :gap) || Application.get_env(:stint, :default_gap, @default_gap)
    min = Keyword.get(opts, :min) || Application.get_env(:stint, :default_min, @default_min)
    meta = Keyword.get(opts, :meta, %{})

    repo().transaction(fn ->
      threshold = DateTime.add(now, -gap, :second)

      latest =
        Record
        |> where([s], s.owner_id == ^owner and s.item == ^item)
        |> where([s], s.ended_at >= ^threshold)
        |> order_by([s], desc: s.ended_at)
        |> limit(1)
        |> lock("FOR UPDATE")
        |> repo().one()

      case latest do
        %Record{} = stint ->
          # A late/out-of-order tick must never move ended_at backwards.
          ended_at = if DateTime.compare(now, stint.ended_at) == :gt, do: now, else: stint.ended_at

          stint
          |> Ecto.Changeset.change(
            ended_at: ended_at,
            seconds: stint.seconds + seconds,
            meta: Map.merge(stint.meta, meta)
          )
          |> repo().update!()
          |> then(&{&1, :extended})

        nil ->
          # A new stint is opening, so any earlier stint on this item
          # is closed for good (it's outside the gap window) — sweep
          # the ones that never grew past :min. They were
          # blink-and-close ghosts, not sessions.
          if min > 0 do
            Record
            |> where([s], s.owner_id == ^owner and s.item == ^item)
            |> where([s], s.seconds < ^min and s.ended_at < ^threshold)
            |> repo().delete_all()
          end

          %Record{
            owner_id: owner,
            item: item,
            started_at: DateTime.add(now, -seconds, :second),
            ended_at: now,
            seconds: seconds,
            meta: meta
          }
          |> repo().insert!()
          |> then(&{&1, :started})
      end
    end)
    |> case do
      {:ok, {stint, verb}} -> {:ok, stint, verb}
      {:error, reason} -> {:error, reason}
    end
  end

  ## ── Queries ───────────────────────────────────────────────────────

  @doc """
  Stints intersecting the owner's local `date`, oldest first. A stint
  crossing midnight appears on both dates it touches — clamp for
  display with `clamp_to_date/3` if needed.

  Options: `:utc_offset` (seconds, default 0), `:item` to filter,
  `:min` to override the below-minimum filter.
  """
  @spec on_date(owner, Date.t(), keyword) :: [Record.t()]
  def on_date(owner, %Date{} = date, opts \\ []) do
    {day_start, day_end} = local_day_bounds(date, Keyword.get(opts, :utc_offset, 0))

    Record
    |> where([s], s.owner_id == ^owner)
    |> where([s], s.ended_at > ^day_start and s.started_at < ^day_end)
    |> maybe_filter_item(Keyword.get(opts, :item))
    |> filter_min(opts)
    |> order_by([s], asc: s.started_at)
    |> repo().all()
  end

  @doc """
  Number of stints by `owner` on `item` — "read in 14 stints".
  """
  @spec count(owner, item, keyword) :: non_neg_integer
  def count(owner, item, opts \\ []) do
    Record
    |> where([s], s.owner_id == ^owner and s.item == ^item)
    |> filter_min(opts)
    |> repo().aggregate(:count)
  end

  @doc "Stint counts per item for an owner: `%{item => count}`."
  @spec counts(owner, keyword) :: %{item => non_neg_integer}
  def counts(owner, opts \\ []) do
    Record
    |> where([s], s.owner_id == ^owner)
    |> filter_min(opts)
    |> group_by([s], s.item)
    |> select([s], {s.item, count(s.id)})
    |> repo().all()
    |> Map.new()
  end

  @doc "Total tracked seconds for an owner, optionally per item."
  @spec total_seconds(owner, item | nil, keyword) :: non_neg_integer
  def total_seconds(owner, item \\ nil, opts \\ []) do
    Record
    |> where([s], s.owner_id == ^owner)
    |> maybe_filter_item(item)
    |> filter_min(opts)
    |> repo().aggregate(:sum, :seconds)
    |> Kernel.||(0)
  end

  @doc "The owner's most recent stint, optionally per item."
  @spec last(owner, item | nil, keyword) :: Record.t() | nil
  def last(owner, item \\ nil, opts \\ []) do
    Record
    |> where([s], s.owner_id == ^owner)
    |> maybe_filter_item(item)
    |> filter_min(opts)
    |> order_by([s], desc: s.ended_at)
    |> limit(1)
    |> repo().one()
  end

  @doc """
  Clamp a stint's interval to the owner's local `date` — the slice a
  day view should render for a midnight-crossing stint. Returns
  `{started_at, ended_at}` in UTC, or `nil` when the stint doesn't
  touch the date.
  """
  @spec clamp_to_date(Record.t(), Date.t(), keyword) ::
          {DateTime.t(), DateTime.t()} | nil
  def clamp_to_date(%Record{} = stint, %Date{} = date, opts \\ []) do
    {day_start, day_end} = local_day_bounds(date, Keyword.get(opts, :utc_offset, 0))

    started = if DateTime.compare(stint.started_at, day_start) == :lt, do: day_start, else: stint.started_at
    ended = if DateTime.compare(stint.ended_at, day_end) == :gt, do: day_end, else: stint.ended_at

    if DateTime.compare(started, ended) == :lt, do: {started, ended}
  end

  ## ── Internals ─────────────────────────────────────────────────────

  defp maybe_filter_item(query, nil), do: query
  defp maybe_filter_item(query, item), do: where(query, [s], s.item == ^item)

  # Hide stints that haven't accumulated :min seconds (yet) — they're
  # either blink-and-close ghosts awaiting GC or brand-new sessions
  # that will cross the bar within a tick or two.
  defp filter_min(query, opts) do
    case Keyword.get(opts, :min) || Application.get_env(:stint, :default_min, @default_min) do
      0 -> query
      min -> where(query, [s], s.seconds >= ^min)
    end
  end

  defp local_day_bounds(date, utc_offset) do
    day_start =
      date
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")
      |> DateTime.add(-utc_offset, :second)

    {day_start, DateTime.add(day_start, 86_400, :second)}
  end

  defp repo do
    Application.get_env(:stint, :repo) ||
      raise "config :stint, repo: MyApp.Repo is required"
  end
end
