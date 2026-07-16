# Changelog

## 0.1.2 (2026-07-16)

* **Fix: `:min` no longer blocks recording.** 0.1.1 dropped
  below-minimum ticks outright — but tick streams are inherently tiny
  (a reader flushing on every scroll pause sends a few seconds per
  tick), so after a gap no stint could ever open and whole sessions
  were silently lost. `:min` now means "minimum to *remember*":
  ticks always record and accumulate; stints still under the minimum
  are hidden from the query functions (`on_date`, `count`, `counts`,
  `total_seconds`, `last` — per-call `:min` override available) and
  garbage-collected when a newer stint opens on the same item.
  The `{:ok, nil, :skipped}` return is gone; `count/3`, `counts/2`,
  `total_seconds/3`, `last/3` gained an options list.

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
