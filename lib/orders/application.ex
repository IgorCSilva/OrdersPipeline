defmodule Orders.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    start_ets()

    children = [
      OrdersPipeline
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Orders.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp start_ets() do
    table = :ets.new(:order_lookup, [:set, :public, :named_table])
    IO.inspect(table, label: "ETS table name")
  end
end
