# Stint

**Tick-based activity session tracking for Elixir.** No start/stop calls —
report elapsed time as it happens, and *stints* (bounded periods of
activity) assemble themselves.

```elixir
# on every activity ping — a reader's progress tick, a player's
# watch-time beat, a practice timer:
Stint.track(user_id, "manga:mangadex/one-piece", 30)
```

If the owner's latest stint on that item ended within the **gap window**
(default 5 minutes), the tick extends it — `ended_at` moves forward,
`seconds` accumulates. A longer silence means the next tick opens a new
stint. That inference is the point: session *ends* are unobservable in
real apps (tabs close, phones lock, processes die), while periodic ticks
are easy and reliable. "A session" stops being an API someone can forget
to call and becomes an emergent fact of the data.

Each stint carries second-resolution `started_at` / `ended_at` — so your
data can distinguish one two-hour binge from six three-minute peeks, not
just "35 minutes somewhere in hour 15".

## Install

```elixir
def deps do
  [
    {:stint, "~> 0.1"}
  ]
end
```

```elixir
# config/config.exs
config :stint,
  repo: MyApp.Repo,
  default_gap: 300,   # optional: app-wide gap window (s)
  default_min: 0      # optional: app-wide minimum to remember a stint (s)
```

```elixir
# a migration (versioned, Oban-style — future stint releases with
# schema changes just need a fresh migration calling up/0 again)
defmodule MyApp.Repo.Migrations.AddStint do
  use Ecto.Migration

  def up, do: Stint.Migration.up()
  def down, do: Stint.Migration.down()
end
```

## API

```elixir
# record — extends or opens automatically; first tick is back-dated by
# its own duration so it doesn't lose itself
{:ok, stint, :extended | :started} =
  Stint.track(owner, item, seconds,
    gap: 300,                      # silence that splits stints (s)
    min: 10,                       # min seconds to REMEMBER a stint —
                                   # recording never blocks (ticks are tiny
                                   # and must accumulate); stints below the
                                   # bar hide from queries and are GC'd
                                   # once a newer stint opens on the item
    at: DateTime.utc_now(),        # tick timestamp
    meta: %{"chapter" => "153"}    # shallow-merged, last write wins
  )

# query
Stint.on_date(owner, ~D[2026-07-14], utc_offset: 7200)  # local-date sessions
Stint.count(owner, item)          # "read in 14 stints"
Stint.counts(owner)               # %{item => count}
Stint.total_seconds(owner)        # or (owner, item)
Stint.last(owner)                 # most recent stint, or (owner, item)

# display helper: the slice of a midnight-crossing stint that belongs
# to one local date (for day/timeline views)
Stint.clamp_to_date(stint, ~D[2026-07-14], utc_offset: 7200)
#=> {started_at, ended_at} | nil
```

`owner_id` and `item` are opaque strings — a user UUID, a device id,
`"manga:source/slug"`, `"habit:guitar"`. The library never interprets
them.

## Semantics worth knowing

- **Precision** is bounded by your tick cadence: a stint's start is its
  first tick back-dated by that tick's elapsed; its end is the last tick
  received. Tick every ~30s and stints are accurate to seconds.
- **Out-of-order ticks** never move `ended_at` backwards (their seconds
  still count).
- **Different items never stitch** — a stint belongs to one owner and one
  item. Reading two series in one evening = (at least) two stints.
- **Midnight-crossing stints** appear in `on_date/3` for both local dates
  they touch; `clamp_to_date/3` slices them for display.
- Requires PostgreSQL (jsonb `meta`; `postgrex` is your dependency).

## License

MIT
