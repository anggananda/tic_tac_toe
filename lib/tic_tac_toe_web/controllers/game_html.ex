defmodule TicTacToeWeb.GameHTML do
  @moduledoc """
  HTML views for TicTacToeWeb.GameController.
  """
  use TicTacToeWeb, :html

  embed_templates "game_html/*"

  @doc """
  Returns true if the cell at `position` is already taken.
  """
  def cell_disabled?(position, board) do
    Enum.at(board, position) != nil
  end

  @doc """
  Returns the display symbol for the cell at `position`.
  """
  def cell_symbol(position, board) do
    Enum.at(board, position) || ""
  end
end
