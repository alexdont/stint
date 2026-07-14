defmodule Stint.Record do
  @moduledoc """
  One stint — a bounded period of activity by one owner on one item,
  with second-resolution start/end.

  `owner_id` and `item` are opaque strings; the library never
  interprets them. `meta` is a free-form map, shallow-merged on every
  extension (last write wins per key) — useful for "what was I on when
  the stint ended" facts like a chapter number.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "stints" do
    field :owner_id, :string
    field :item, :string
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :seconds, :integer, default: 0
    field :meta, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end
end
