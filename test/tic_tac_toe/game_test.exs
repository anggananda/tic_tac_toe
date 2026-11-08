defmodule TicTacToe.GameTest do
  use ExUnit.Case, async: true

  setup do
    case TicTacToe.Game.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Clean slate: release any leftover player slots from concurrent tests,
    # then reset board/turn/winner while keeping the GenServer alive.
    TicTacToe.Game.leave(:x)
    TicTacToe.Game.leave(:o)
    TicTacToe.Game.reset()
    :ok
  end

  describe "game state" do
    test "initial state has empty board and X goes first" do
      state = TicTacToe.Game.get_state()

      assert state.board == List.duplicate(nil, 9)
      assert state.turn == :x
      assert state.winner == nil
    end

    test "two players can join as X and O" do
      assert {:ok, :x} = TicTacToe.Game.join()
      assert {:ok, :o} = TicTacToe.Game.join()
      assert {:error, :game_full} = TicTacToe.Game.join()
    end

    test "X can make a valid move" do
      {:ok, :x} = TicTacToe.Game.join()
      {:ok, :o} = TicTacToe.Game.join()

      {:ok, state} = TicTacToe.Game.make_move(:x, 0)

      assert Enum.at(state.board, 0) == :x
      assert state.turn == :o
    end

    test "X cannot move when it's O's turn" do
      {:ok, :x} = TicTacToe.Game.join()
      {:ok, :o} = TicTacToe.Game.join()

      TicTacToe.Game.make_move(:x, 0)
      # Now it's O's turn, X cannot move again
      assert {:error, :not_your_turn} = TicTacToe.Game.make_move(:x, 1)
    end

    test "cannot move in an occupied cell" do
      {:ok, :x} = TicTacToe.Game.join()
      {:ok, :o} = TicTacToe.Game.join()

      TicTacToe.Game.make_move(:x, 0)
      assert {:error, :cell_taken} = TicTacToe.Game.make_move(:o, 0)
    end

    test "X wins with a row" do
      {:ok, :x} = TicTacToe.Game.join()
      {:ok, :o} = TicTacToe.Game.join()

      TicTacToe.Game.make_move(:x, 0)
      TicTacToe.Game.make_move(:o, 3)
      TicTacToe.Game.make_move(:x, 1)
      TicTacToe.Game.make_move(:o, 4)
      {:ok, state} = TicTacToe.Game.make_move(:x, 2)

      assert state.winner == [0, 1, 2]
    end

    test "game ends in draw when board is full with no winner" do
      {:ok, :x} = TicTacToe.Game.join()
      {:ok, :o} = TicTacToe.Game.join()

      # Draw pattern:
      # X O X
      # O O X
      # X X O
      moves = [{:x, 0}, {:o, 1}, {:x, 2}, {:o, 3}, {:x, 6}, {:o, 4}, {:x, 7}, {:o, 8}, {:x, 5}]
      Enum.each(moves, fn {sym, pos} -> TicTacToe.Game.make_move(sym, pos) end)

      state = TicTacToe.Game.get_state()
      assert state.winner == :draw
    end

    test "cannot move after game is over" do
      {:ok, :x} = TicTacToe.Game.join()
      {:ok, :o} = TicTacToe.Game.join()

      TicTacToe.Game.make_move(:x, 0)
      TicTacToe.Game.make_move(:o, 3)
      TicTacToe.Game.make_move(:x, 1)
      TicTacToe.Game.make_move(:o, 4)
      # X wins
      TicTacToe.Game.make_move(:x, 2)

      assert {:error, :game_over} = TicTacToe.Game.make_move(:o, 5)
    end

    test "reset restores initial state" do
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
end
