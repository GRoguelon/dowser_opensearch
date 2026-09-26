defmodule Dowser.Opensearch.Mappings do
  @moduledoc """
  The OpenSearch mapping APIs — the endpoints tagged `Mappings` in the
  [OpenSearch OpenAPI specification](https://github.com/opensearch-project/opensearch-api-specification).

  Built on `Dowser.Client`. Required OpenSearch attributes are positional
  arguments; everything optional lives in `opts`.

  OpenSearch tags these separately from the index APIs, so they live here
  rather than on `Dowser.Opensearch.Index`; the index-target helper they share
  is `Dowser.Opensearch.Target`.

  Note that a mapping fetched through `get_mapping/1` is not what
  `Dowser.Opensearch.Codec` casts against — that one comes from
  `Dowser.Opensearch.MappingCacher`, which caches it per index and context.

  ## Shared conventions

    * An *index target* may be `nil` (all indices), a single index/alias/
      data-stream name (string or atom), or a list of them (joined with `,`).
      `put_mapping/3` requires one and takes it as an argument; the reads take
      it as the `:index` option.
    * Endpoints that accept a request body take it as their first argument,
      required — pass `%{}` to send nothing.

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
  Updates the mapping of one or several indices
  ([Put mapping API](https://docs.opensearch.org/latest/api-reference/index-apis/put-mapping/)).

  `mapping` is the mapping body, e.g. `%{properties: %{title: %{type: "text"}}}`.

      %{properties: %{published_at: %{type: "date"}}}
      |> Dowser.Opensearch.Mappings.put_mapping("posts")

  OpenSearch only lets a mapping grow: adding a field works, changing the type
  of an existing one does not, and needs a reindex into a new index
  (`Dowser.Opensearch.Reindex.reindex/2`).
  """
  @spec put_mapping(map(), index(), keyword()) :: result()
  def put_mapping(%{} = mapping, index, opts \\ []) do
    with {:ok, path} <- Helpers.required_path(index, "/_mapping") do
      path
      |> Client.post(mapping, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `put_mapping/3`, but returns the body directly or raises the error
  exception.
  """
  @spec put_mapping!(map(), index(), keyword()) :: body()
  def put_mapping!(%{} = mapping, index, opts \\ []) do
    mapping |> put_mapping(index, opts) |> Dowser.unwrap()
  end

  @doc """
  Returns the mapping of one, several, or all indices
  ([Get mapping API](https://docs.opensearch.org/latest/api-reference/index-apis/get-mapping/)).

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec get_mapping(keyword()) :: result()
  def get_mapping(opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    index
    |> Helpers.path("/_mapping")
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `get_mapping/1`, but returns the body directly or raises the error
  exception.
  """
  @spec get_mapping!(keyword()) :: body()
  def get_mapping!(opts \\ []) do
    opts |> get_mapping() |> Dowser.unwrap()
  end

  @doc """
  Returns the mapping of one or several fields
  ([Get field mapping API](https://docs.opensearch.org/latest/api-reference/index-apis/get-mapping/)).

  `fields` is one field name or several, and may include wildcards.

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec get_field_mapping(name(), keyword()) :: result()
  def get_field_mapping(fields, opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    with {:ok, fields_segment} <- Helpers.required_segment(fields, "fields") do
      index
      |> Helpers.path("/_mapping/field/" <> fields_segment)
      |> Client.get(opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `get_field_mapping/2`, but returns the body directly or raises the
  error exception.
  """
  @spec get_field_mapping!(name(), keyword()) :: body()
  def get_field_mapping!(fields, opts \\ []) do
    fields |> get_field_mapping(opts) |> Dowser.unwrap()
  end

  ## Repository metadata

  # Index-related functions exposed to `Dowser.Opensearch.Repository`:
  # `{index_spec, arity, kind}` where index_spec is :opts (`:index` option) or
  # {:pos, n} (positional index argument), and kind selects the variants
  # (:pair for `!`, :predicate for `?`).
  @doc false
  def __repository__ do
    [
      put_mapping: {{:pos, 1}, 3, :pair},
      get_mapping: {:opts, 1, :pair},
      get_field_mapping: {:opts, 2, :pair}
    ]
  end
end
