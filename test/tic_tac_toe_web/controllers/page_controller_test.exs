defmodule TicTacToeWeb.PageControllerTest do
  use TicTacToeWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Tic Tac Toe"
    assert html_response(conn, 200) =~ "Mulai Bermain"
  end
end
