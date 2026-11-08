defmodule TicTacToe.Cluster do
  @moduledoc """
  Manages Erlang node distribution for distributed tic-tac-toe.

  On startup, this module:
  1. Sets the distributed Erlang cookie (if configured).
  2. Connects to configured cluster nodes so GenServer calls and PubSub
     messages can flow between hosts.

  The `TicTacToe.Game` GenServer is started directly by the application
  supervisor so it is guaranteed to be running when the endpoint serves
  requests.

  Configure via environment variables:
    TIC_TAC_TOE_NODE_NAME=tic@host-a
    TIC_TAC_TOE_COOKIE=mysecretcookie
    TIC_TAC_TOE_CLUSTER_NODES=tic@host-b,tic@host-c
  """

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      shutdown: 5000
    }
  end

  def start_link(_args) do
    connect_cluster()
    {:ok, self()}
  end

  defp connect_cluster() do
    cluster_config = Application.get_env(:tic_tac_toe, :cluster, %{})

    cookie = cluster_config[:cookie]
    cluster_nodes = cluster_config[:cluster_nodes] || []

    # Only configure distribution when running as a named (distributed) node.
    # In dev (`mix phx.server`), node() is :nonode@nohost and distribution is off.
    if node() != :nonode@nohost do
      :erlang.set_cookie(node(), String.to_atom(cookie || "tic_tac_toe_cookie"))

      # Give the local node a moment to settle before connecting.
      Process.sleep(500)

      Enum.each(cluster_nodes, fn remote_node ->
        remote = String.to_atom(remote_node)

        case Node.connect(remote) do
          true ->
            :logger.info("Connected to cluster node #{remote_node}")

          false ->
            :logger.warning(
              "Could not connect to cluster node #{remote_node} — check hostname, cookie, and firewall"
            )
        end
      end)
    else
      :logger.info("Running as non-distributed node — tic-tac-toe game available locally only")
    end

    :ok
  end
end
