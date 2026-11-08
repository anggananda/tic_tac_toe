defmodule TicTacToe.Game do
  @moduledoc """
  Manages the state of a tic-tac-toe game.

  This GenServer holds the board, turn order, and winner.
  It is registered globally (`:global`) so any connected node can
  read or update the game state through Erlang distribution.

  ## Example

      {:ok, pid} = TicTacToe.Game.start_link()
  """

  use GenServer

  @board_size 9
  @winning_lines [
    # rows
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8],
    # cols
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8],
    # diagonals
    [0, 4, 8],
    [2, 4, 6]
  ]

  @default_state %{
    board: List.duplicate(nil, @board_size),
    players: %{x: nil, o: nil},
    turn: :x,
    winner: nil,
    game_id: "default"
  }

  ### Client API

  @doc """
  Starts the game GenServer and registers it globally under `{:global, :tic_tac_toe_game}`.
  Any connected node can address it with `GenServer.call({:global, :tic_tac_toe_game}, ...)`.
  """
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{name: :game_server}, name: {:global, :tic_tac_toe_game})
  end

  @doc """
  Returns the current game state as a map.
  """
  def get_state() do
    GenServer.call({:global, :tic_tac_toe_game}, :get_state)
  end

  @doc """
  Joins the game as player `:x` or `:o`. Returns `{:ok, symbol}` if a slot is free,
  or `{:error, :game_full}` if both slots are taken.
  """
  def join() do
    GenServer.call({:global, :tic_tac_toe_game}, {:join, self()})
  end

  @doc """
  Makes a move for `symbol` at `position` (0-8).
  Returns `{:ok, state}` on success or `{:error, reason}` on failure.
  """
  def make_move(symbol, position) when is_integer(position) and position >= 0 and position < 9 do
    GenServer.call({:global, :tic_tac_toe_game}, {:make_move, symbol, position})
  end

  @doc """
  Resets the game to its initial state.
  """
  def reset() do
    GenServer.call({:global, :tic_tac_toe_game}, :reset)
  end

  @doc """
  Leaves the game as `symbol` (`:x` or `:o`), freeing the player slot so
  another client can join. Safe to call when a WebSocket disconnects.
  """
  def leave(symbol) when symbol in [:x, :o] do
    GenServer.call({:global, :tic_tac_toe_game}, {:leave, symbol})
  end

  ### GenServer callbacks

  @impl true
  def init(_args) do
    {:ok, @default_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:join, pid}, _from, state) do
    cond do
      state.players.x == nil ->
        {:reply, {:ok, :x}, %{state | players: %{state.players | x: pid}}}

      state.players.o == nil ->
        {:reply, {:ok, :o}, %{state | players: %{state.players | o: pid}}}

      true ->
        {:reply, {:error, :game_full}, state}
    end
  end

  @impl true
  def handle_call({:make_move, symbol, position}, _from, state) do
    with {:ok, _} <- validate_player(state, symbol),
         :ok <- validate_turn(state, symbol),
         :ok <- validate_cell(state, position),
         :ok <- validate_game_active(state) do
      new_board = List.replace_at(state.board, position, symbol)
      new_turn = if symbol == :x, do: :o, else: :x
      winner = check_winner(new_board)

      new_state =
        %{state | board: new_board, turn: new_turn, winner: winner}

      broadcast_move(new_state, symbol, position)

      {:reply, {:ok, new_state}, new_state}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, @default_state}
  end

  @impl true
  def handle_call({:leave, symbol}, _from, state) do
    {:reply, :ok, %{state | players: %{state.players | symbol => nil}}}
  end

  ### Internal helpers

  defp validate_player(%{players: players}, symbol) do
    if players[symbol] != nil do
      {:ok, symbol}
    else
      {:error, :not_joined}
    end
  end

  defp validate_turn(%{turn: turn}, symbol) do
    if turn == symbol do
      :ok
    else
      {:error, :not_your_turn}
    end
  end

  defp validate_cell(%{board: board}, position) do
    if Enum.at(board, position) == nil do
      :ok
    else
      {:error, :cell_taken}
    end
  end

  defp validate_game_active(%{winner: winner}) do
    if winner == nil do
      :ok
    else
      {:error, :game_over}
    end
  end

  defp check_winner(board) do
    Enum.find(@winning_lines, fn line ->
      [a, b, c] = line
      cell_a = Enum.at(board, a)
      cell_a != nil and cell_a == Enum.at(board, b) and cell_a == Enum.at(board, c)
    end)
    |> case do
      nil ->
        if Enum.all?(board, &(&1 != nil)) do
          :draw
        else
          nil
        end

      line ->
        line
    end
  end

  defp broadcast_move(state, symbol, position) do
    # Publish the move so any subscribed node (e.g. another host) can push it to clients.
    Phoenix.PubSub.broadcast(TicTacToe.PubSub, "games:#{state.game_id}", %{
      event: "game_move",
      board: state.board,
      turn: state.turn,
      winner: state.winner,
      last_move: %{symbol: symbol, position: position}
    })
  end
end
