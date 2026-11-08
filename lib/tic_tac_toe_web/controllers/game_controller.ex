defmodule TicTacToeWeb.GameController do
  use TicTacToeWeb, :controller

  def index(conn, _params) do
    state = TicTacToe.Game.get_state()
    render(conn, :index, board: state.board)
  end
end
