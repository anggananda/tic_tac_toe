defmodule TicTacToeWeb.GameControllerTest do
  use TicTacToeWeb.ConnCase, async: true

  setup do
    case TicTacToe.Game.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  test "GET /game", %{conn: conn} do
    conn = get(conn, ~p"/game")
    assert html_response(conn, 200) =~ "Tic Tac Toe"
    assert html_response(conn, 200) =~ "Giliran:"
  end
end
