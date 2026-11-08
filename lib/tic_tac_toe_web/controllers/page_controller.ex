defmodule TicTacToeWeb.PageController do
  use TicTacToeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
