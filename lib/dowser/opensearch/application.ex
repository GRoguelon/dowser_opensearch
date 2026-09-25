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
    mapping_cacher_opts = Application.get_env(:dowser_opensearch, :mapping_cacher_opts, [])

    children = [
      {Dowser.Opensearch.MappingCacher, mapping_cacher_opts}
    ]

    Supervisor.start_link(children, @supervisor_opts)
  end
end
