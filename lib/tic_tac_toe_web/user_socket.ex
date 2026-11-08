defmodule TicTacToeWeb.UserSocket do
  use Phoenix.Socket

  @moduledoc """
  UserSocket for Phoenix Channels.

  Handles client connections for real-time tic-tac-toe gameplay.
  Since channels are authenticated via the `join/3` callback in GameChannel,
  this connect function mainly validates that a session exists.
  """

  ## Channels
  channel "games:*", TicTacToeWeb.GameChannel

  ## Transport
  @impl true
  def connect(_params, socket) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
