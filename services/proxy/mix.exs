defmodule FiremigProxy.MixProject do
  use Mix.Project

  def project do
    [
      app: :firemig_proxy,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [firemig_proxy: [applications: [runtime_tools: :permanent]]]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:crypto, :logger, :runtime_tools],
      mod: {FiremigProxy.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bandit, "~> 1.8"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.16"},
      {:thousand_island, "~> 1.5"}
    ]
  end
end
