defmodule Dowser.Opensearch.DanglingIndices do
  @moduledoc """
  The OpenSearch dangling index APIs — every endpoint tagged `Dangling Indices`
  in the [OpenSearch OpenAPI specification](https://github.com/opensearch-project/opensearch-api-specification).

  Built on `Dowser.Client`. Required OpenSearch attributes are positional
  arguments; everything optional lives in `opts`.

  An index becomes *dangling* when its directory is present on a node but the
  cluster metadata knows nothing about it — a node rejoining after the index
  was deleted while it was away, or data restored underneath a fresh cluster.
  Such an index is inert: it is neither searchable nor writable until it is
  imported.

  Both write endpoints are addressed by the index's **UUID** rather than its
  name, since a dangling index has no name the cluster agrees on. `list/1` is
  where those UUIDs come from.

  ## accept_data_loss

  OpenSearch requires `accept_data_loss=true` on both writes, so it is a
  positional argument here rather than an option — there is no default that
  would be safe to assume:

    * importing may resurrect an index whose deletion was deliberate, and
      whose shards may be missing or stale;
    * deleting discards the data for good.

  Passing `false` sends the parameter as given and lets OpenSearch reject it,
  rather than second-guessing the call here.

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

  ## Typespecs

  @type index_uuid :: String.t()
  @type body :: term()
  @type result :: {:ok, body()} | {:error, Exception.t()}

  ## Public functions

  @doc """
  Lists every dangling index the cluster can see
  ([List dangling indices API](https://docs.opensearch.org/latest/api-reference/index-apis/dangling-index/)).

  Each entry carries the `index_uuid` the other two functions take:

      {:ok, %{"dangling_indices" => indices}} = Dowser.Opensearch.DanglingIndices.list()
      Enum.map(indices, & &1["index_uuid"])
  """
  @spec list(keyword()) :: result()
  def list(opts \\ []) do
    "/_dangling"
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `list/1`, but returns the body directly or raises the error exception.
  """
  @spec list!(keyword()) :: body()
  def list!(opts \\ []) do
    opts |> list() |> Dowser.unwrap()
  end

  @doc """
  Imports the dangling index `index_uuid` back into the cluster
  ([Import dangling index API](https://docs.opensearch.org/latest/api-reference/index-apis/dangling-index/)).

  `accept_data_loss` must be `true` for OpenSearch to carry the import out; see
  the module documentation.

      Dowser.Opensearch.DanglingIndices.import_dangling_index(uuid, true)
  """
  @spec import_dangling_index(index_uuid(), boolean(), keyword()) :: result()
  def import_dangling_index(index_uuid, accept_data_loss, opts \\ [])
      when is_boolean(accept_data_loss) do
    with {:ok, segment} <- Helpers.required_segment(index_uuid, "index_uuid") do
      opts = Helpers.put_param(opts, :accept_data_loss, accept_data_loss)

      ("/_dangling/" <> segment)
      |> Client.post(nil, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `import_dangling_index/3`, but returns the body directly or raises the
  error exception.
  """
  @spec import_dangling_index!(index_uuid(), boolean(), keyword()) :: body()
  def import_dangling_index!(index_uuid, accept_data_loss, opts \\ []) do
    index_uuid |> import_dangling_index(accept_data_loss, opts) |> Dowser.unwrap()
  end

  @doc """
  Deletes the dangling index `index_uuid`, and its data with it
  ([Delete dangling index API](https://docs.opensearch.org/latest/api-reference/index-apis/dangling-index/)).

  `accept_data_loss` must be `true` for OpenSearch to carry the deletion out;
  see the module documentation. This is not recoverable.
  """
  @spec delete_dangling_index(index_uuid(), boolean(), keyword()) :: result()
  def delete_dangling_index(index_uuid, accept_data_loss, opts \\ [])
      when is_boolean(accept_data_loss) do
    with {:ok, segment} <- Helpers.required_segment(index_uuid, "index_uuid") do
      opts = Helpers.put_param(opts, :accept_data_loss, accept_data_loss)

      ("/_dangling/" <> segment)
      |> Client.delete(nil, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `delete_dangling_index/3`, but returns the body directly or raises the
  error exception.
  """
  @spec delete_dangling_index!(index_uuid(), boolean(), keyword()) :: body()
  def delete_dangling_index!(index_uuid, accept_data_loss, opts \\ []) do
    index_uuid |> delete_dangling_index(accept_data_loss, opts) |> Dowser.unwrap()
  end
end
