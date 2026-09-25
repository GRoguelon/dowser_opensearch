defmodule DowserOpensearch.MixProject do
  use Mix.Project

  @source_url "https://github.com/GRoguelon/dowser_opensearch"
  @version "0.1.0"

  def project do
    [
      app: :dowser_opensearch,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      package: package(),
      name: "Dowser.Opensearch",
      description: "Elixir client for the OpenSearch API, built on top of Dowser.Client",
      source_url: @source_url,
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:crypto, :logger],
      mod: {Dowser.Opensearch.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp aliases do
    [
      credo: ["credo --strict"],
      lint: ["format --check-formatted", "credo", "dialyzer"]
    ]
  end

  defp dialyzer do
    [
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts",
      plt_add_apps: [:mix, :ex_unit],
      flags: [:error_handling, :extra_return, :missing_return]
    ]
  end

  defp package do
    [
      name: :dowser_opensearch,
      files: ~w[lib .formatter.exs mix.exs README* CHANGELOG* LICENSE*],
      maintainers: ["Geoffrey Roguelon"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "https://dowser-opensearch.hexdocs.pm/changelog.html",
        "Dowser.Client" => "https://hex.pm/packages/dowser_client"
      }
    ]
  end

  defp docs do
    [
      formatters: ["html"],
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url: @source_url,
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      groups_for_modules: [
        API: [
          Dowser.Opensearch.Alias,
          Dowser.Opensearch.Cat,
          Dowser.Opensearch.Cluster,
          Dowser.Opensearch.DanglingIndices,
          Dowser.Opensearch.DataStream,
          Dowser.Opensearch.Document,
          Dowser.Opensearch.Index,
          Dowser.Opensearch.IndexSettings,
          Dowser.Opensearch.IndexStateManagement,
          Dowser.Opensearch.IndexTemplate,
          Dowser.Opensearch.Info,
          Dowser.Opensearch.List,
          Dowser.Opensearch.Mappings,
          Dowser.Opensearch.Reindex,
          Dowser.Opensearch.Repository,
          Dowser.Opensearch.Search,
          Dowser.Opensearch.Streamer,
          Dowser.Opensearch.Target
        ],
        "Type casting": [
          Dowser.Opensearch.Codec,
          Dowser.Opensearch.MappingCacher,
          Dowser.Opensearch.Codec.Binary,
          Dowser.Opensearch.Codec.Date,
          Dowser.Opensearch.Codec.DateRange,
          Dowser.Opensearch.Codec.GeoPoint,
          Dowser.Opensearch.Codec.IP,
          Dowser.Opensearch.Codec.Range
        ]
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      dowser_client(),
      {:telemetry, "~> 1.2", optional: true},

      ## Dev
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false, warn_if_outdated: true}
    ]
  end

  # The two packages are developed together: `DOWSER_CLIENT_PATH=../dowser_client`
  # builds against a working copy instead of the published version.
  defp dowser_client do
    if path = System.get_env("DOWSER_CLIENT_PATH") do
      {:dowser_client, path: path, override: true}
    else
      {:dowser_client, "~> 0.3.0"}
    end
  end
end
