defmodule Rx.Mixfile do
  use Mix.Project

  def project do
    [app: :rx,
     version: "0.1.0",
     name: "Rx",
     elixir: "~> 1.4",
     elixirc_options: [warnings_as_errors: true],
     deps: deps(),
     elixirc_paths: elixirc_paths(Mix.env),

     build_per_environment: false,
     test_coverage: [tool: Coverex.Task, coveralls: true],

     description: description(),
     package: package(),

     docs: [main: Rx]]
  end

  # Configuration for the OTP application
  def application do
    [applications: [:logger]]
  end

  # Dependencies
  defp deps do
    [{:coverex, "~> 1.4.15", only: :test},
     {:credo, "~> 0.8", only: [:dev, :test]},
     {:dogma, "~> 0.1", only: :dev},
     {:ex_doc, "~> 0.16", only: :dev},
     {:gen_stage, "~> 0.12"}]
  end

  defp description, do: "ReactiveX for Elixir"

  defp package do
    [maintainers: ["Eric Scouten"],
      licenses: ["Apache2"],
      links: %{"Github" => "https://github.com/scouten/rx"}]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
