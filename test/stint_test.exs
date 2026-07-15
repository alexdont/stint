defmodule StintTest do
  use ExUnit.Case, async: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Stint.TestRepo)
    %{owner: "owner-#{System.unique_integer([:positive])}"}
  end

  @item "manga:test/series"

  defp at(iso), do: DateTime.from_iso8601(iso) |> elem(1)

  test "first tick opens a stint back-dated by its own duration", %{owner: owner} do
    now = at("2026-07-14T20:00:30Z")
    {:ok, stint, :started} = Stint.track(owner, @item, 30, at: now)

    assert stint.seconds == 30
    assert DateTime.compare(stint.started_at, at("2026-07-14T20:00:00Z")) == :eq
    assert DateTime.compare(stint.ended_at, now) == :eq
  end

  test "ticks within the gap extend; a longer silence opens a new stint", %{owner: owner} do
    {:ok, s1, :started} = Stint.track(owner, @item, 30, at: at("2026-07-14T20:00:30Z"))
    {:ok, s2, :extended} = Stint.track(owner, @item, 30, at: at("2026-07-14T20:05:00Z"))
    assert s2.id == s1.id
    assert s2.seconds == 60
    assert DateTime.compare(s2.ended_at, at("2026-07-14T20:05:00Z")) == :eq

    # 20-minute silence > default 5-minute gap → new stint
    {:ok, s3, :started} = Stint.track(owner, @item, 60, at: at("2026-07-14T20:25:00Z"))
    refute s3.id == s1.id
    assert Stint.count(owner, @item) == 2
  end

  test "a below-minimum tick is dropped instead of opening a stint", %{owner: owner} do
    {:ok, nil, :skipped} = Stint.track(owner, @item, 3, at: at("2026-07-14T20:00:03Z"), min: 10)
    assert Stint.count(owner, @item) == 0

    # at or above the minimum opens normally
    {:ok, _s, :started} = Stint.track(owner, @item, 10, at: at("2026-07-14T20:10:10Z"), min: 10)
    assert Stint.count(owner, @item) == 1
  end

  test "a below-minimum tick still extends a running stint", %{owner: owner} do
    {:ok, s1, :started} = Stint.track(owner, @item, 30, at: at("2026-07-14T20:00:30Z"), min: 10)
    {:ok, s2, :extended} = Stint.track(owner, @item, 3, at: at("2026-07-14T20:01:00Z"), min: 10)
    assert s2.id == s1.id
    assert s2.seconds == 33
  end

  test "gap is tunable per call", %{owner: owner} do
    {:ok, s1, :started} = Stint.track(owner, @item, 10, at: at("2026-07-14T20:00:10Z"))
    # 3 minutes later, but with a 60s gap → new stint
    {:ok, s2, :started} = Stint.track(owner, @item, 10, at: at("2026-07-14T20:03:10Z"), gap: 60)
    refute s2.id == s1.id
  end

  test "different items never stitch together", %{owner: owner} do
    {:ok, _, :started} = Stint.track(owner, "a", 10, at: at("2026-07-14T20:00:10Z"))
    {:ok, _, :started} = Stint.track(owner, "b", 10, at: at("2026-07-14T20:00:20Z"))
    assert Stint.counts(owner) == %{"a" => 1, "b" => 1}
  end

  test "out-of-order tick never moves ended_at backwards", %{owner: owner} do
    {:ok, s1, :started} = Stint.track(owner, @item, 30, at: at("2026-07-14T20:05:00Z"))
    {:ok, s2, :extended} = Stint.track(owner, @item, 10, at: at("2026-07-14T20:04:00Z"))
    assert s2.id == s1.id
    assert DateTime.compare(s2.ended_at, s1.ended_at) == :eq
    assert s2.seconds == 40
  end

  test "meta shallow-merges with last write winning", %{owner: owner} do
    {:ok, _, :started} =
      Stint.track(owner, @item, 10, at: at("2026-07-14T20:00:10Z"), meta: %{"chapter" => "1", "device" => "phone"})

    {:ok, s, :extended} =
      Stint.track(owner, @item, 10, at: at("2026-07-14T20:01:00Z"), meta: %{"chapter" => "2"})

    assert s.meta == %{"chapter" => "2", "device" => "phone"}
  end

  test "on_date respects the owner's UTC offset", %{owner: owner} do
    # 23:30 UTC on Jul 14 = 01:30 local Jul 15 for a UTC+2 user
    {:ok, _, :started} = Stint.track(owner, @item, 60, at: at("2026-07-14T23:30:00Z"))

    assert Stint.on_date(owner, ~D[2026-07-14], utc_offset: 7200) == []
    assert [%{item: @item}] = Stint.on_date(owner, ~D[2026-07-15], utc_offset: 7200)
    # …and it IS Jul 14 for a UTC user
    assert [_] = Stint.on_date(owner, ~D[2026-07-14])
  end

  test "midnight-crossing stints appear on both dates and clamp cleanly", %{owner: owner} do
    {:ok, _, :started} = Stint.track(owner, @item, 600, at: at("2026-07-15T00:05:00Z"))
    # started 23:55 Jul 14 → ended 00:05 Jul 15 (UTC)

    assert [s] = Stint.on_date(owner, ~D[2026-07-14])
    assert [^s] = Stint.on_date(owner, ~D[2026-07-15])

    {c_start, c_end} = Stint.clamp_to_date(s, ~D[2026-07-14])
    assert DateTime.compare(c_start, s.started_at) == :eq
    assert DateTime.to_iso8601(c_end) == "2026-07-15T00:00:00Z"

    {c_start2, c_end2} = Stint.clamp_to_date(s, ~D[2026-07-15])
    assert DateTime.to_iso8601(c_start2) == "2026-07-15T00:00:00Z"
    assert DateTime.compare(c_end2, s.ended_at) == :eq

    assert Stint.clamp_to_date(s, ~D[2026-07-16]) == nil
  end

  test "totals and last", %{owner: owner} do
    {:ok, _, _} = Stint.track(owner, "a", 100, at: at("2026-07-14T10:00:00Z"))
    {:ok, _, _} = Stint.track(owner, "b", 50, at: at("2026-07-14T11:00:00Z"))

    assert Stint.total_seconds(owner) == 150
    assert Stint.total_seconds(owner, "a") == 100
    assert Stint.last(owner).item == "b"
    assert Stint.last(owner, "a").item == "a"
  end
end
