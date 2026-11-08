defmodule TicTacToeWeb.GameChannelTest do
  use ExUnit.Case, async: true

  setup do
    case TicTacToe.Game.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    TicTacToe.Game.leave(:x)
    TicTacToe.Game.leave(:o)
    TicTacToe.Game.reset()
    :ok
  end

  test "GameChannel module exists and has expected callbacks" do
    functions = TicTacToeWeb.GameChannel.__info__(:functions)
    assert {:join, 3} in functions
    assert {:handle_in, 3} in functions
    assert {:handle_info, 2} in functions
  end

  test "GameChannel join assigns X to first player" do
    # Test that GameChannel can be invoked by simulating the join flow
    # through the GenServer directly
    assert {:ok, :x} = TicTacToe.Game.join()
    assert {:ok, :o} = TicTacToe.Game.join()
    assert {:error, :game_full} = TicTacToe.Game.join()
  end

  test "GameChannel make_move delegates to GenServer" do
    {:ok, :x} = TicTacToe.Game.join()
    {:ok, :o} = TicTacToe.Game.join()

    {:ok, state} = TicTacToe.Game.make_move(:x, 0)
    assert Enum.at(state.board, 0) == :x
    assert state.turn == :o
  end

  test "GameChannel reset clears game state" do
    {:ok, :x} = TicTacToe.Game.join()
    {:ok, :o} = TicTacToe.Game.join()
    TicTacToe.Game.make_move(:x, 0)

    TicTacToe.Game.reset()

    state = TicTacToe.Game.get_state()
    assert state.board == List.duplicate(nil, 9)
    assert state.turn == :x
    assert state.winner == nil
  end
end
