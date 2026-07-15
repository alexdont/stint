# Changelog

## 0.1.1 (2026-07-15)

* New `:min` option on `Stint.track/4` (app-wide default via
  `config :stint, default_min: n`): the minimum seconds required to
  *open a new* stint. A below-minimum tick with nothing to extend is
  dropped and returns `{:ok, nil, :skipped}` — filters accidental
  blink-and-close opens. Ticks that extend a running stint are never
  dropped, so real sessions keep their closing seconds.

## 0.1.0 (2026-07-14)

Initial release:

* `Stint.track/4` — tick-based recording with gap-stitching: extends
  the owner's latest stint on the item when within the gap window
  (default 5 min), opens a new one otherwise. Back-dated first tick,
  monotonic `ended_at` under out-of-order ticks, shallow-merged `meta`.
* Queries: `on_date/3` (timezone-aware via `:utc_offset`), `count/2`,
  `counts/1`, `total_seconds/2`, `last/2`, and `clamp_to_date/3` for
  rendering midnight-crossing stints on day views.
* `Stint.Migration` — versioned, Oban-style migrations.
