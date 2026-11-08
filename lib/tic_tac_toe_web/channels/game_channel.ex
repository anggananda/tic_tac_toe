defmodule TicTacToeWeb.GameChannel do
  @moduledoc """
  Phoenix Channel for real-time tic-tac-toe gameplay.

  Players join a game topic (`games:<game_id>`) and are assigned symbol `:x` or `:o`.
  Moves are sent through `make_move` and broadcast to all subscribers via PubSub,
  enabling real-time play across connected nodes.
  """

  use TicTacToeWeb, :channel

  @game_id "default"

  @impl true
  def join("games:#{@game_id}", _payload, socket) do
    case TicTacToe.Game.join() do
      {:ok, symbol} ->
        {:ok, %{symbol: symbol}, assign(socket, :symbol, symbol)}

      {:error, :game_full} ->
        {:error, %{reason: :game_full}}
    end
  end

  @impl true
  def handle_in("make_move", %{"position" => position}, socket) do
    symbol = socket.assigns.symbol

    case TicTacToe.Game.make_move(symbol, position) do
      {:ok, _state} ->
        {:noreply, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_in("reset_game", _params, socket) do
    TicTacToe.Game.reset()

    Phoenix.PubSub.broadcast(
      TicTacToe.PubSub,
      "games:#{@game_id}",
      %{event: "game_reset"}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info(%{event: "game_move"} = message, socket) do
    push(socket, "game_move", message)
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{event: "game_reset"} = message, socket) do
    push(socket, "game_reset", message)
    {:noreply, socket}
  end
end
