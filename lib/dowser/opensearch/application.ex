defmodule Dowser.Opensearch.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  ## Module attributes

  @supervisor_opts [strategy: :one_for_one, name: Dowser.Opensearch.Supervisor]

  ## Public functions

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(children(), @supervisor_opts)
  end

  ## Private functions

  # `Dowser.Opensearch.MappingCacher` joins this list with the type-casting
  # layer; nothing in the transport foundation needs supervising.
  defp children, do: []
end
