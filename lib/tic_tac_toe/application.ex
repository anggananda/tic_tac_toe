defmodule TicTacToe.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TicTacToeWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:tic_tac_toe, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TicTacToe.PubSub},
      TicTacToe.Game,
      {TicTacToe.Cluster, []},
      # Start to serve requests, typically the last entry
      TicTacToeWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TicTacToe.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TicTacToeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
