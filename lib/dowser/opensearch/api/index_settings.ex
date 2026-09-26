defmodule Dowser.Opensearch.IndexSettings do
  @moduledoc """
  The OpenSearch index settings APIs — the endpoints tagged `Index Settings` in
  the [OpenSearch OpenAPI specification](https://github.com/opensearch-project/opensearch-api-specification).

  Built on `Dowser.Client`. Required OpenSearch attributes are positional
  arguments; everything optional lives in `opts`.

  OpenSearch tags these separately from the index APIs, so they live here
  rather than on `Dowser.Opensearch.Index`; the index-target helper they share
  is `Dowser.Opensearch.Target`.

  ## Shared conventions

    * An *index target* may be `nil` (all indices), a single index/alias/
      data-stream name (string or atom), or a list of them (joined with `,`).
      Both endpoints accept one as the `:index` option.
    * `put_settings/2` takes the settings body as its first argument, required.

  All remaining options are forwarded to `Dowser.Client.request/4`, e.g.
  `:context`, `:params` (query-string parameters), `:format`, `:keys` and
  `:http_opts` (including `:headers`) — plus `:codec`, this package's own,
  which picks the per-field codec for this one request (see
  `Dowser.Opensearch.Codec`).

  On a 2xx response every function returns `{:ok, body}` with the decoded
  response body. A non-2xx response returns
  `{:error, %Dowser.Opensearch.Error{}}`; a transport, encoding or decoding
  failure returns `{:error, exception}` from `Dowser.Client`. A required
  argument that is missing or empty is reported the same way, before any
  request is made: `{:error, %ArgumentError{}}`. Each function has a bang
  variant that returns the body directly or raises the error exception.
  """

  alias Dowser.Opensearch.Client
  alias Dowser.Opensearch.Helpers
  alias Dowser.Opensearch.Target

  ## Typespecs

  @type index :: Target.t()
  @type name :: Target.name()
  @type body :: term()
  @type result :: {:ok, body()} | {:error, Exception.t()}

  ## Public functions

  @doc """
  Updates the settings of one, several, or all indices
  ([Update index settings API](https://docs.opensearch.org/latest/api-reference/index-apis/update-settings/)).

  `settings` is the settings body, e.g. `%{index: %{number_of_replicas: 2}}`.

      %{index: %{number_of_replicas: 2}}
      |> Dowser.Opensearch.IndexSettings.put_settings(index: "posts")

  Only *dynamic* settings can be changed on an open index; a static one needs
  the index closed first (`Dowser.Opensearch.Index.close/2`). Setting a value
  to `nil` resets it to its default, which is how an index block added by
  `Dowser.Opensearch.Index.add_block/3` is cleared:

      %{index: %{blocks: %{write: nil}}}
      |> Dowser.Opensearch.IndexSettings.put_settings(index: "posts")

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec put_settings(map(), keyword()) :: result()
  def put_settings(%{} = settings, opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    index
    |> Helpers.path("/_settings")
    |> Client.put(settings, opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `put_settings/2`, but returns the body directly or raises the error
  exception.
  """
  @spec put_settings!(map(), keyword()) :: body()
  def put_settings!(%{} = settings, opts \\ []) do
    settings |> put_settings(opts) |> Dowser.unwrap()
  end

  @doc """
  Returns the settings of one, several, or all indices
  ([Get index settings API](https://docs.opensearch.org/latest/api-reference/index-apis/get-settings/)).

  ## Options

    * `:index` — index target; absent for all indices.
    * `:name` — restrict the result to one or several setting names, which may
      include wildcards (`"index.number_of_*"`).
  """
  @spec get_settings(keyword()) :: result()
  def get_settings(opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)
    {name, opts} = Keyword.pop(opts, :name)

    with {:ok, suffix} <- optional_suffix("/_settings", name, "name") do
      index
      |> Helpers.path(suffix)
      |> Client.get(opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `get_settings/1`, but returns the body directly or raises the error
  exception.
  """
  @spec get_settings!(keyword()) :: body()
  def get_settings!(opts \\ []) do
    opts |> get_settings() |> Dowser.unwrap()
  end

  ## Repository metadata

  # Index-related functions exposed to `Dowser.Opensearch.Repository`:
  # `{index_spec, arity, kind}` where index_spec is :opts (`:index` option) or
  # {:pos, n} (positional index argument), and kind selects the variants
  # (:pair for `!`, :predicate for `?`).
  @doc false
  def __repository__ do
    [
      put_settings: {:opts, 2, :pair},
      get_settings: {:opts, 1, :pair}
    ]
  end

  ## Private functions

  # An optional path parameter appended to `base`: absent leaves `base` alone,
  # present but empty is the same bad argument a required one would be.
  @spec optional_suffix(String.t(), name(), String.t()) ::
          {:ok, String.t()} | {:error, Helpers.argument_error()}
  defp optional_suffix(base, nil, _label) do
    {:ok, base}
  end

  defp optional_suffix(base, value, label) do
    with {:ok, segment} <- Helpers.required_segment(value, label) do
      {:ok, base <> "/" <> segment}
    end
  end
end
