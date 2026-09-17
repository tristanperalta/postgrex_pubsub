defmodule PostgrexPubsub.MixProject do
  use Mix.Project

  def project do
    [
      app: :postgrex_pubsub,
      name: "Postgrex PubSub",
      description: "A helper for creating and listening to pubsub events from postgres",
      version: "0.4.1",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: "https://github.com/bechurch/postgrex_pubsub",
      homepage_url: "https://github.com/bechurch/postgrex_pubsub",
      package: [
        maintainers: ["Ben Church"],
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/bechurch/postgrex_pubsub"}
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:jason, "~> 1.4"},
      {:postgrex, "~> 0.21 or ~> 1.0"},
      {:ecto_sql, "~> 3.13"}
    ]
  end
end
