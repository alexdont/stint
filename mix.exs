defmodule Stint.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Tick-based activity session tracking — no start/stop calls, just report elapsed time and stints (bounded periods of activity) assemble themselves via gap-stitching. Second-resolution start/end per stint, session counts, day/timezone queries. Bring your own Ecto repo."
  @source_url "https://github.com/alexdont/stint"

  def project do
    [
      app: :stint,
      version: @version,
      description: @description,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.10"},
      {:jason, "~> 1.4"},
      {:postgrex, "~> 0.17", optional: true},
      {:ex_doc, "~> 0.39", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "stint",
      maintainers: ["Alexander Don"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      name: "Stint",
      source_ref: "v#{@version}",
      source_url: @source_url,
      main: "Stint",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"]
    ]
  end
end
