defmodule Dowser.Opensearch.Index do
  @moduledoc """
  The OpenSearch index APIs — the endpoints tagged `Index` in the
  [OpenSearch OpenAPI specification](https://github.com/opensearch-project/opensearch-api-specification)
  (index lifecycle, resizing, rollover, maintenance and monitoring).

  Built on `Dowser.Client`. Required OpenSearch attributes are positional
  arguments; everything optional lives in `opts`.

  OpenSearch splits what Elasticsearch tags as one `indices` group into several
  tags, so the neighbouring APIs live in modules of their own:
  `Dowser.Opensearch.Mappings`, `Dowser.Opensearch.IndexSettings`,
  `Dowser.Opensearch.Alias`, `Dowser.Opensearch.IndexTemplate`,
  `Dowser.Opensearch.DataStream` and `Dowser.Opensearch.DanglingIndices`. The
  index-target helper they all share is `Dowser.Opensearch.Target`.

  ## Shared conventions

    * An *index target* may be `nil` (all indices), a single index/alias/
      data-stream name (string or atom), or a list of them (joined with `,`).
      Endpoints that accept an optional target take it as the `:index` option;
      endpoints that require one take it as the first argument.
    * Path parameters such as `target`, `metric` or `block` accept the same
      shapes as an index target.
    * Endpoints that accept a request body take it as their first argument,
      required — pass `%{}` to send nothing.
    * `HEAD` existence checks come as a pair where the `?` variant plays the
      bang role: `index_exists/2` returns `{:ok, boolean()}` or
      `{:error, exception}`, `index_exists?/2` returns the bare boolean
      (`404` → `false`) and raises on genuine errors.

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

  @type t :: Target.t()
  @type name :: Target.name()
  @type body :: term()
  @type result :: {:ok, body()} | {:error, Exception.t()}
  @type exists_result :: {:ok, boolean()} | {:error, Exception.t()}

  ## Public functions — index lifecycle

  @doc """
  Creates the index `index`
  ([Create index API](https://docs.opensearch.org/latest/api-reference/index-apis/create-index/)).

  `body` is the request body (e.g. `settings`, `mappings`, `aliases`); pass
  `%{}` to send nothing.

      %{settings: %{number_of_shards: 3}, mappings: %{properties: %{title: %{type: "text"}}}}
      |> Dowser.Opensearch.Index.create_index("posts")
  """
  @spec create_index(map(), t(), keyword()) :: result()
  def create_index(%{} = body, index, opts \\ []) do
    with {:ok, path} <- Helpers.required_path(index, "") do
      path
      |> Client.put(body, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `create_index/3`, but returns the body directly or raises the error
  exception.
  """
  @spec create_index!(map(), t(), keyword()) :: body()
  def create_index!(%{} = body, index, opts \\ []) do
    body |> create_index(index, opts) |> Dowser.unwrap()
  end

  @doc """
  Returns the definition of one or several indices
  ([Get index API](https://docs.opensearch.org/latest/api-reference/index-apis/get-index/)).
  """
  @spec get_index(t(), keyword()) :: result()
  def get_index(index, opts \\ []) do
    with {:ok, path} <- Helpers.required_path(index, "") do
      path
      |> Client.get(opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `get_index/2`, but returns the body directly or raises the error
  exception.
  """
  @spec get_index!(t(), keyword()) :: body()
  def get_index!(index, opts \\ []) do
    index |> get_index(opts) |> Dowser.unwrap()
  end

  @doc """
  Deletes one or several indices
  ([Delete index API](https://docs.opensearch.org/latest/api-reference/index-apis/delete-index/)).
  """
  @spec delete_index(t(), keyword()) :: result()
  def delete_index(index, opts \\ []) do
    with {:ok, path} <- Helpers.required_path(index, "") do
      path
      |> Client.delete(nil, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `delete_index/2`, but returns the body directly or raises the error
  exception.
  """
  @spec delete_index!(t(), keyword()) :: body()
  def delete_index!(index, opts \\ []) do
    index |> delete_index(opts) |> Dowser.unwrap()
  end

  @doc """
  Checks whether one or several indices exist
  ([Index exists API](https://docs.opensearch.org/latest/api-reference/index-apis/exists/)).

  Returns `{:ok, true}`, `{:ok, false}` or `{:error, exception}`.
  """
  @spec index_exists(t(), keyword()) :: exists_result()
  def index_exists(index, opts \\ []) do
    with {:ok, path} <- Helpers.required_path(index, "") do
      path
      |> exists(opts)
    end
  end

  @doc """
  Like `index_exists/2`, but returns the boolean directly (`404` → `false`) or
  raises the error exception.
  """
  @spec index_exists?(t(), keyword()) :: boolean()
  def index_exists?(index, opts \\ []) do
    index |> index_exists(opts) |> Dowser.unwrap()
  end

  @doc """
  Opens one or several closed indices
  ([Open index API](https://docs.opensearch.org/latest/api-reference/index-apis/open-index/)).
  """
  @spec open(t(), keyword()) :: result()
  def open(index, opts \\ []) do
    with {:ok, path} <- Helpers.required_path(index, "/_open") do
      path
      |> Client.post(nil, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `open/2`, but returns the body directly or raises the error exception.
  """
  @spec open!(t(), keyword()) :: body()
  def open!(index, opts \\ []) do
    index |> open(opts) |> Dowser.unwrap()
  end

  @doc """
  Closes one or several indices
  ([Close index API](https://docs.opensearch.org/latest/api-reference/index-apis/close-index/)).
  """
  @spec close(t(), keyword()) :: result()
  def close(index, opts \\ []) do
    with {:ok, path} <- Helpers.required_path(index, "/_close") do
      path
      |> Client.post(nil, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `close/2`, but returns the body directly or raises the error exception.
  """
  @spec close!(t(), keyword()) :: body()
  def close!(index, opts \\ []) do
    index |> close(opts) |> Dowser.unwrap()
  end

  @doc """
  Adds an index block to one or several indices
  ([Add index block API](https://docs.opensearch.org/latest/api-reference/index-apis/blocks/)).

  `block` is the block to add — `"read_only"`, `"read_only_allow_delete"`,
  `"read"`, `"write"` or `"metadata"`.

      Dowser.Opensearch.Index.add_block("posts", "write")

  OpenSearch has no endpoint for removing a block: clear one by setting the
  corresponding `index.blocks.*` setting to `nil` through
  `Dowser.Opensearch.IndexSettings.put_settings/2`.
  """
  @spec add_block(t(), name(), keyword()) :: result()
  def add_block(index, block, opts \\ []) do
    with {:ok, block_segment} <- Helpers.required_segment(block, "block"),
         {:ok, path} <- Helpers.required_path(index, "/_block/" <> block_segment) do
      path
      |> Client.put(nil, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `add_block/3`, but returns the body directly or raises the error
  exception.
  """
  @spec add_block!(t(), name(), keyword()) :: body()
  def add_block!(index, block, opts \\ []) do
    index |> add_block(block, opts) |> Dowser.unwrap()
  end

  ## Public functions — resizing and rollover

  @doc """
  Clones the index `index` into `target`
  ([Clone index API](https://docs.opensearch.org/latest/api-reference/index-apis/clone/)).

  `body` is the request body (e.g. `settings`, `aliases`); pass `%{}` to send
  nothing. The source index must be blocked for writes first — see
  `add_block/3`.
  """
  @spec clone(map(), t(), name(), keyword()) :: result()
  def clone(%{} = body, index, target, opts \\ []) do
    with {:ok, target_segment} <- Helpers.required_segment(target, "target"),
         {:ok, path} <- Helpers.required_path(index, "/_clone/" <> target_segment) do
      path
      |> Client.post(body, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `clone/4`, but returns the body directly or raises the error exception.
  """
  @spec clone!(map(), t(), name(), keyword()) :: body()
  def clone!(%{} = body, index, target, opts \\ []) do
    body |> clone(index, target, opts) |> Dowser.unwrap()
  end

  @doc """
  Shrinks the index `index` into `target`, with fewer primary shards
  ([Shrink index API](https://docs.opensearch.org/latest/api-reference/index-apis/shrink-index/)).

  `body` is the request body (e.g. `settings`, `aliases`); pass `%{}` to send
  nothing.
  """
  @spec shrink(map(), t(), name(), keyword()) :: result()
  def shrink(%{} = body, index, target, opts \\ []) do
    with {:ok, target_segment} <- Helpers.required_segment(target, "target"),
         {:ok, path} <- Helpers.required_path(index, "/_shrink/" <> target_segment) do
      path
      |> Client.post(body, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `shrink/4`, but returns the body directly or raises the error exception.
  """
  @spec shrink!(map(), t(), name(), keyword()) :: body()
  def shrink!(%{} = body, index, target, opts \\ []) do
    body |> shrink(index, target, opts) |> Dowser.unwrap()
  end

  @doc """
  Splits the index `index` into `target`, with more primary shards
  ([Split index API](https://docs.opensearch.org/latest/api-reference/index-apis/split/)).

  `body` is the request body (e.g. `settings`, `aliases`); pass `%{}` to send
  nothing.
  """
  @spec split(map(), t(), name(), keyword()) :: result()
  def split(%{} = body, index, target, opts \\ []) do
    with {:ok, target_segment} <- Helpers.required_segment(target, "target"),
         {:ok, path} <- Helpers.required_path(index, "/_split/" <> target_segment) do
      path
      |> Client.post(body, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `split/4`, but returns the body directly or raises the error exception.
  """
  @spec split!(map(), t(), name(), keyword()) :: body()
  def split!(%{} = body, index, target, opts \\ []) do
    body |> split(index, target, opts) |> Dowser.unwrap()
  end

  @doc """
  Rolls the rollover target `target` (an alias or data stream) over to a new
  index
  ([Rollover API](https://docs.opensearch.org/latest/api-reference/index-apis/rollover/)).

  `body` is the request body (e.g. `conditions`, `settings`, `mappings`,
  `aliases`); pass `%{}` to send nothing.

  ## Options

    * `:new_index` — explicit name for the new index; absent to let OpenSearch
      derive it.
  """
  @spec rollover(map(), name(), keyword()) :: result()
  def rollover(%{} = body, target, opts \\ []) do
    {new_index, opts} = Keyword.pop(opts, :new_index)

    with {:ok, target_segment} <- Helpers.required_segment(target, "target"),
         {:ok, path} <-
           optional_suffix("/" <> target_segment <> "/_rollover", new_index, "new_index") do
      path
      |> Client.post(body, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `rollover/3`, but returns the body directly or raises the error
  exception.
  """
  @spec rollover!(map(), name(), keyword()) :: body()
  def rollover!(%{} = body, target, opts \\ []) do
    body |> rollover(target, opts) |> Dowser.unwrap()
  end

  ## Public functions — maintenance

  @doc """
  Refreshes one, several, or all indices
  ([Refresh API](https://docs.opensearch.org/latest/api-reference/index-apis/refresh/)).

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec refresh(keyword()) :: result()
  def refresh(opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    index
    |> Helpers.path("/_refresh")
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `refresh/1`, but returns the body directly or raises the error
  exception.
  """
  @spec refresh!(keyword()) :: body()
  def refresh!(opts \\ []) do
    opts |> refresh() |> Dowser.unwrap()
  end

  @doc """
  Flushes one, several, or all indices
  ([Flush API](https://docs.opensearch.org/latest/api-reference/index-apis/flush/)).

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec flush(keyword()) :: result()
  def flush(opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    index
    |> Helpers.path("/_flush")
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `flush/1`, but returns the body directly or raises the error exception.
  """
  @spec flush!(keyword()) :: body()
  def flush!(opts \\ []) do
    opts |> flush() |> Dowser.unwrap()
  end

  @doc """
  Force-merges the segments of one, several, or all indices
  ([Force merge API](https://docs.opensearch.org/latest/api-reference/index-apis/force-merge/)).

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec forcemerge(keyword()) :: result()
  def forcemerge(opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    index
    |> Helpers.path("/_forcemerge")
    |> Client.post(nil, opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `forcemerge/1`, but returns the body directly or raises the error
  exception.
  """
  @spec forcemerge!(keyword()) :: body()
  def forcemerge!(opts \\ []) do
    opts |> forcemerge() |> Dowser.unwrap()
  end

  @doc """
  Clears the caches of one, several, or all indices
  ([Clear cache API](https://docs.opensearch.org/latest/api-reference/index-apis/clear-index-cache/)).

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec clear_cache(keyword()) :: result()
  def clear_cache(opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    index
    |> Helpers.path("/_cache/clear")
    |> Client.post(nil, opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `clear_cache/1`, but returns the body directly or raises the error
  exception.
  """
  @spec clear_cache!(keyword()) :: body()
  def clear_cache!(opts \\ []) do
    opts |> clear_cache() |> Dowser.unwrap()
  end

  ## Public functions — monitoring

  @doc """
  Returns statistics for one, several, or all indices
  ([Index stats API](https://docs.opensearch.org/latest/api-reference/index-apis/stats/)).

  ## Options

    * `:index` — index target; absent for all indices.
    * `:metric` — restrict the result to one or several metrics.
  """
  @spec stats(keyword()) :: result()
  def stats(opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)
    {metric, opts} = Keyword.pop(opts, :metric)

    with {:ok, suffix} <- optional_suffix("/_stats", metric, "metric") do
      index
      |> Helpers.path(suffix)
      |> Client.get(opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `stats/1`, but returns the body directly or raises the error exception.
  """
  @spec stats!(keyword()) :: body()
  def stats!(opts \\ []) do
    opts |> stats() |> Dowser.unwrap()
  end

  @doc """
  Returns the shard segments of one, several, or all indices
  ([Segments API](https://docs.opensearch.org/latest/api-reference/index-apis/segment/)).

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec segments(keyword()) :: result()
  def segments(opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    index
    |> Helpers.path("/_segments")
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `segments/1`, but returns the body directly or raises the error
  exception.
  """
  @spec segments!(keyword()) :: body()
  def segments!(opts \\ []) do
    opts |> segments() |> Dowser.unwrap()
  end

  @doc """
  Returns information about ongoing and completed shard recoveries
  ([Recovery API](https://docs.opensearch.org/latest/api-reference/index-apis/recovery/)).

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec recovery(keyword()) :: result()
  def recovery(opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    index
    |> Helpers.path("/_recovery")
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `recovery/1`, but returns the body directly or raises the error
  exception.
  """
  @spec recovery!(keyword()) :: body()
  def recovery!(opts \\ []) do
    opts |> recovery() |> Dowser.unwrap()
  end

  @doc """
  Returns store information for the shards of one, several, or all indices
  ([Shard stores API](https://docs.opensearch.org/latest/api-reference/index-apis/shard-stores/)).

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec shard_stores(keyword()) :: result()
  def shard_stores(opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    index
    |> Helpers.path("/_shard_stores")
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `shard_stores/1`, but returns the body directly or raises the error
  exception.
  """
  @spec shard_stores!(keyword()) :: body()
  def shard_stores!(opts \\ []) do
    opts |> shard_stores() |> Dowser.unwrap()
  end

  @doc """
  Resolves `name` — which may include wildcards — into the concrete indices,
  aliases and data streams it matches
  ([Resolve index API](https://docs.opensearch.org/latest/api-reference/index-apis/)).

      Dowser.Opensearch.Index.resolve_index!("logs-*")
      #=> %{"indices" => [...], "aliases" => [...], "data_streams" => [...]}
  """
  @spec resolve_index(name(), keyword()) :: result()
  def resolve_index(name, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(name, "name") do
      ("/_resolve/index/" <> segment)
      |> Client.get(opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `resolve_index/2`, but returns the body directly or raises the error
  exception.
  """
  @spec resolve_index!(name(), keyword()) :: body()
  def resolve_index!(name, opts \\ []) do
    name |> resolve_index(opts) |> Dowser.unwrap()
  end

  ## Repository metadata

  # Index-related functions exposed to `Dowser.Opensearch.Repository`:
  # `{index_spec, arity, kind}` where index_spec is :opts (`:index` option) or
  # {:pos, n} (positional index argument), and kind selects the variants
  # (:pair for `!`, :predicate for `?`).
  @doc false
  def __repository__ do
    [
      create_index: {{:pos, 1}, 3, :pair},
      get_index: {{:pos, 0}, 2, :pair},
      delete_index: {{:pos, 0}, 2, :pair},
      index_exists: {{:pos, 0}, 2, :predicate},
      open: {{:pos, 0}, 2, :pair},
      close: {{:pos, 0}, 2, :pair},
      add_block: {{:pos, 0}, 3, :pair},
      clone: {{:pos, 1}, 4, :pair},
      shrink: {{:pos, 1}, 4, :pair},
      split: {{:pos, 1}, 4, :pair},
      refresh: {:opts, 1, :pair},
      flush: {:opts, 1, :pair},
      forcemerge: {:opts, 1, :pair},
      clear_cache: {:opts, 1, :pair},
      stats: {:opts, 1, :pair},
      segments: {:opts, 1, :pair},
      recovery: {:opts, 1, :pair},
      shard_stores: {:opts, 1, :pair}
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

  # HEAD responses have no body, so the response format defaults to :raw.
  @spec exists(String.t(), keyword()) :: exists_result()
  defp exists(path, opts) do
    opts = Helpers.put_default_format(opts, :resp_format, :raw)

    :head
    |> Client.request(path, nil, opts)
    |> Helpers.parse_exists()
  end
end
