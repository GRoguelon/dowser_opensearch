defmodule Dowser.Opensearch.Cat do
  @moduledoc """
  The OpenSearch compact and aligned text (CAT) APIs — every endpoint tagged
  `CAT` in the
  [OpenSearch OpenAPI specification](https://github.com/opensearch-project/opensearch-api-specification).

  Built on `Dowser.Client`. The cat endpoints take no request body and no
  required attribute: each one's optional path parameter is an option, so every
  function has the same `opts`-only signature.

  ## JSON, not text

  The cat APIs are meant for humans at a terminal and answer in aligned text by
  default — but they honour the `accept` header `Dowser.Client` already sends,
  so the response comes back as JSON and is decoded like every other endpoint:
  a list of maps, one per row.

      Dowser.Opensearch.Cat.indices!(index: "posts*")
      #=> [%{"index" => "posts", "health" => "green", "docs.count" => "42", ...}]

  Every value in those maps is a string — that is what the cat APIs emit, JSON
  or not. For the aligned text a terminal wants, ask for it explicitly: the
  `format` query parameter wins over the header, and `resp_format: :raw` keeps
  the body from being parsed as JSON.

      Dowser.Opensearch.Cat.indices!(params: [format: "text", v: true], resp_format: :raw)

  ## Large clusters

  A cat response is built whole in the coordinating node's heap before being
  sent. Where the number of indices or shards is large or unbounded, use
  `Dowser.Opensearch.List.indices/1` and `Dowser.Opensearch.List.shards/1`
  instead — OpenSearch's paginated counterparts to `indices/1` and `shards/1`.

  ## Shared options

  Most cat endpoints accept the same query parameters, passed through `:params`:

    * `v` — add the column headers.
    * `h` — the columns to return, e.g. `h: "index,docs.count"`.
    * `s` — the columns to sort on, e.g. `s: "docs.count:desc"`.
    * `bytes` / `time` — the unit sizes and durations are expressed in
      (`"kb"`, `"gb"`, `"s"`, `"ms"`, …).
    * `format` — see above.

  Use `help/1` to ask which cat endpoints the cluster serves.

  All remaining options are forwarded to `Dowser.Client.request/4`, e.g.
  `:context`, `:params` (query-string parameters), `:format`, `:keys` and
  `:http_opts` (including `:headers`).

  On a 2xx response every function returns `{:ok, body}` with the decoded
  response body. A non-2xx response returns
  `{:error, %Dowser.Opensearch.Error{}}`; a transport, encoding or decoding
  failure returns `{:error, exception}` from `Dowser.Client`. Each function has
  a bang variant that returns the body directly or raises the error exception.
  """

  alias Dowser.Opensearch.Client
  alias Dowser.Opensearch.Helpers
  alias Dowser.Opensearch.Target

  ## Typespecs

  @type index :: Target.t()

  @typedoc "A path parameter: a single name, or several (joined with `,`)."
  @type name :: Target.name()

  @type body :: term()
  @type result :: {:ok, body()} | {:error, Exception.t()}

  ## Public functions — help

  @doc """
  Lists the available cat APIs — `GET /_cat`
  ([CAT API](https://docs.opensearch.org/latest/api-reference/cat/index/)).

  This one endpoint answers in plain text whatever the `accept` header says —
  a banner line, then one endpoint per line — so the response format defaults
  to `:raw` and the body is parsed here into the list of endpoints:

      Dowser.Opensearch.Cat.help!()
      #=> ["/_cat/allocation", "/_cat/shards", "/_cat/shards/{index}", ...]

  Pass `resp_format: :json` (or `:ndjson`) to opt out of both the `:raw`
  default and the parsing, and get whatever `Dowser.Client` decodes instead.
  """
  @spec help(keyword()) :: {:ok, [String.t()]} | {:error, Exception.t()}
  def help(opts \\ []) do
    opts = Helpers.put_default_format(opts, :resp_format, :raw)

    "/_cat"
    |> Client.get(opts)
    |> Helpers.parse_result()
    |> parse_help()
  end

  @doc """
  Like `help/1`, but returns the endpoints directly or raises the error
  exception.
  """
  @spec help!(keyword()) :: [String.t()]
  def help!(opts \\ []) do
    opts |> help() |> Dowser.unwrap()
  end

  ## Public functions — indices and documents

  @doc """
  Lists indices with their health, status, counts and sizes
  ([CAT indices](https://docs.opensearch.org/latest/api-reference/cat/cat-indices/)).

  See the module documentation on large clusters — prefer
  `Dowser.Opensearch.List.indices/1` where the index count is unbounded.

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec indices(keyword()) :: result()
  def indices(opts \\ []) do
    suffixed("/_cat/indices", :index, opts)
  end

  @doc """
  Like `indices/1`, but returns the body directly or raises the error
  exception.
  """
  @spec indices!(keyword()) :: body()
  def indices!(opts \\ []) do
    opts |> indices() |> Dowser.unwrap()
  end

  @doc """
  Counts the documents of one, several, or all indices
  ([CAT count](https://docs.opensearch.org/latest/api-reference/cat/cat-count/)).

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec count(keyword()) :: result()
  def count(opts \\ []) do
    suffixed("/_cat/count", :index, opts)
  end

  @doc """
  Like `count/1`, but returns the body directly or raises the error exception.
  """
  @spec count!(keyword()) :: body()
  def count!(opts \\ []) do
    opts |> count() |> Dowser.unwrap()
  end

  @doc """
  Lists aliases with the indices they point at
  ([CAT aliases](https://docs.opensearch.org/latest/api-reference/cat/cat-aliases/)).

  ## Options

    * `:name` — restrict the result to one or several alias names.
  """
  @spec aliases(keyword()) :: result()
  def aliases(opts \\ []) do
    suffixed("/_cat/aliases", :name, opts)
  end

  @doc """
  Like `aliases/1`, but returns the body directly or raises the error
  exception.
  """
  @spec aliases!(keyword()) :: body()
  def aliases!(opts \\ []) do
    opts |> aliases() |> Dowser.unwrap()
  end

  @doc """
  Lists index templates
  ([CAT templates](https://docs.opensearch.org/latest/api-reference/cat/cat-templates/)).

  ## Options

    * `:name` — restrict the result to one or several template names.
  """
  @spec templates(keyword()) :: result()
  def templates(opts \\ []) do
    suffixed("/_cat/templates", :name, opts)
  end

  @doc """
  Like `templates/1`, but returns the body directly or raises the error
  exception.
  """
  @spec templates!(keyword()) :: body()
  def templates!(opts \\ []) do
    opts |> templates() |> Dowser.unwrap()
  end

  @doc """
  Reports the heap used by each field's field data
  ([CAT field data](https://docs.opensearch.org/latest/api-reference/cat/cat-field-data/)).

  ## Options

    * `:fields` — restrict the result to one or several fields.
  """
  @spec fielddata(keyword()) :: result()
  def fielddata(opts \\ []) do
    suffixed("/_cat/fielddata", :fields, opts)
  end

  @doc """
  Like `fielddata/1`, but returns the body directly or raises the error
  exception.
  """
  @spec fielddata!(keyword()) :: body()
  def fielddata!(opts \\ []) do
    opts |> fielddata() |> Dowser.unwrap()
  end

  ## Public functions — shards and segments

  @doc """
  Lists shards with their state, node and size
  ([CAT shards](https://docs.opensearch.org/latest/api-reference/cat/cat-shards/)).

  See the module documentation on large clusters — prefer
  `Dowser.Opensearch.List.shards/1` where the shard count is unbounded.

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec shards(keyword()) :: result()
  def shards(opts \\ []) do
    suffixed("/_cat/shards", :index, opts)
  end

  @doc """
  Like `shards/1`, but returns the body directly or raises the error exception.
  """
  @spec shards!(keyword()) :: body()
  def shards!(opts \\ []) do
    opts |> shards() |> Dowser.unwrap()
  end

  @doc """
  Lists the Lucene segments of each shard
  ([CAT segments](https://docs.opensearch.org/latest/api-reference/cat/cat-segments/)).

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec segments(keyword()) :: result()
  def segments(opts \\ []) do
    suffixed("/_cat/segments", :index, opts)
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
  Reports on ongoing and completed shard recoveries
  ([CAT recovery](https://docs.opensearch.org/latest/api-reference/cat/cat-recovery/)).

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec recovery(keyword()) :: result()
  def recovery(opts \\ []) do
    suffixed("/_cat/recovery", :index, opts)
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
  Reports on segment replication between primaries and replicas
  ([CAT segment replication](https://docs.opensearch.org/latest/api-reference/cat/cat-segment-replication/)).

  This is an OpenSearch addition, and reports on its segment-replication
  strategy — the alternative to document replication — so it has nothing to say
  about an index using the default.

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec segment_replication(keyword()) :: result()
  def segment_replication(opts \\ []) do
    suffixed("/_cat/segment_replication", :index, opts)
  end

  @doc """
  Like `segment_replication/1`, but returns the body directly or raises the
  error exception.
  """
  @spec segment_replication!(keyword()) :: body()
  def segment_replication!(opts \\ []) do
    opts |> segment_replication() |> Dowser.unwrap()
  end

  @doc """
  Lists the segments of the point-in-time contexts on this node
  ([CAT PIT segments](https://docs.opensearch.org/latest/api-reference/cat/cat-pit-segments/)).

  An OpenSearch addition, alongside
  `Dowser.Opensearch.Search.create_pit/3`. Use `all_pit_segments/1` for every
  node's.
  """
  @spec pit_segments(keyword()) :: result()
  def pit_segments(opts \\ []) do
    "/_cat/pit_segments"
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `pit_segments/1`, but returns the body directly or raises the error
  exception.
  """
  @spec pit_segments!(keyword()) :: body()
  def pit_segments!(opts \\ []) do
    opts |> pit_segments() |> Dowser.unwrap()
  end

  @doc """
  Lists the segments of every point-in-time context in the cluster
  ([CAT PIT segments](https://docs.opensearch.org/latest/api-reference/cat/cat-pit-segments/)).
  """
  @spec all_pit_segments(keyword()) :: result()
  def all_pit_segments(opts \\ []) do
    "/_cat/pit_segments/_all"
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `all_pit_segments/1`, but returns the body directly or raises the error
  exception.
  """
  @spec all_pit_segments!(keyword()) :: body()
  def all_pit_segments!(opts \\ []) do
    opts |> all_pit_segments() |> Dowser.unwrap()
  end

  ## Public functions — nodes and cluster

  @doc """
  Lists the nodes of the cluster with their roles and load
  ([CAT nodes](https://docs.opensearch.org/latest/api-reference/cat/cat-nodes/)).
  """
  @spec nodes(keyword()) :: result()
  def nodes(opts \\ []) do
    "/_cat/nodes"
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `nodes/1`, but returns the body directly or raises the error exception.
  """
  @spec nodes!(keyword()) :: body()
  def nodes!(opts \\ []) do
    opts |> nodes() |> Dowser.unwrap()
  end

  @doc """
  Lists the custom attributes of each node
  ([CAT node attributes](https://docs.opensearch.org/latest/api-reference/cat/cat-nodeattrs/)).
  """
  @spec nodeattrs(keyword()) :: result()
  def nodeattrs(opts \\ []) do
    "/_cat/nodeattrs"
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `nodeattrs/1`, but returns the body directly or raises the error
  exception.
  """
  @spec nodeattrs!(keyword()) :: body()
  def nodeattrs!(opts \\ []) do
    opts |> nodeattrs() |> Dowser.unwrap()
  end

  @doc """
  Reports the disk space and shard count allocated to each node
  ([CAT allocation](https://docs.opensearch.org/latest/api-reference/cat/cat-allocation/)).

  ## Options

    * `:node_id` — restrict the result to one or several nodes.
  """
  @spec allocation(keyword()) :: result()
  def allocation(opts \\ []) do
    suffixed("/_cat/allocation", :node_id, opts)
  end

  @doc """
  Like `allocation/1`, but returns the body directly or raises the error
  exception.
  """
  @spec allocation!(keyword()) :: body()
  def allocation!(opts \\ []) do
    opts |> allocation() |> Dowser.unwrap()
  end

  @doc """
  Reports the node currently elected cluster manager
  ([CAT cluster manager](https://docs.opensearch.org/latest/api-reference/cat/cat-cluster_manager/)).

  This is the endpoint to use: `master/1` is the pre-2.0 spelling of the same
  thing, kept only for compatibility.
  """
  @spec cluster_manager(keyword()) :: result()
  def cluster_manager(opts \\ []) do
    "/_cat/cluster_manager"
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `cluster_manager/1`, but returns the body directly or raises the error
  exception.
  """
  @spec cluster_manager!(keyword()) :: body()
  def cluster_manager!(opts \\ []) do
    opts |> cluster_manager() |> Dowser.unwrap()
  end

  @doc """
  Reports the elected cluster manager, under its pre-2.0 name
  ([CAT master](https://docs.opensearch.org/latest/api-reference/cat/cat-master/)).

  Deprecated in OpenSearch in favour of `cluster_manager/1`, which this is an
  alias of. Kept for clusters still serving the old path.
  """
  @spec master(keyword()) :: result()
  def master(opts \\ []) do
    "/_cat/master"
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `master/1`, but returns the body directly or raises the error exception.
  """
  @spec master!(keyword()) :: body()
  def master!(opts \\ []) do
    opts |> master() |> Dowser.unwrap()
  end

  @doc """
  Reports the cluster's health in one row
  ([CAT health](https://docs.opensearch.org/latest/api-reference/cat/cat-health/)).
  """
  @spec health(keyword()) :: result()
  def health(opts \\ []) do
    "/_cat/health"
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `health/1`, but returns the body directly or raises the error exception.
  """
  @spec health!(keyword()) :: body()
  def health!(opts \\ []) do
    opts |> health() |> Dowser.unwrap()
  end

  @doc """
  Lists the installed plugins of each node
  ([CAT plugins](https://docs.opensearch.org/latest/api-reference/cat/cat-plugins/)).
  """
  @spec plugins(keyword()) :: result()
  def plugins(opts \\ []) do
    "/_cat/plugins"
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `plugins/1`, but returns the body directly or raises the error
  exception.
  """
  @spec plugins!(keyword()) :: body()
  def plugins!(opts \\ []) do
    opts |> plugins() |> Dowser.unwrap()
  end

  ## Public functions — tasks and pools

  @doc """
  Lists the tasks currently running
  ([CAT tasks](https://docs.opensearch.org/latest/api-reference/cat/cat-tasks/)).
  """
  @spec tasks(keyword()) :: result()
  def tasks(opts \\ []) do
    "/_cat/tasks"
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `tasks/1`, but returns the body directly or raises the error exception.
  """
  @spec tasks!(keyword()) :: body()
  def tasks!(opts \\ []) do
    opts |> tasks() |> Dowser.unwrap()
  end

  @doc """
  Lists the cluster-level changes still queued
  ([CAT pending tasks](https://docs.opensearch.org/latest/api-reference/cat/cat-pending-tasks/)).
  """
  @spec pending_tasks(keyword()) :: result()
  def pending_tasks(opts \\ []) do
    "/_cat/pending_tasks"
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `pending_tasks/1`, but returns the body directly or raises the error
  exception.
  """
  @spec pending_tasks!(keyword()) :: body()
  def pending_tasks!(opts \\ []) do
    opts |> pending_tasks() |> Dowser.unwrap()
  end

  @doc """
  Reports the thread pools of each node
  ([CAT thread pool](https://docs.opensearch.org/latest/api-reference/cat/cat-thread-pool/)).

  ## Options

    * `:thread_pool_patterns` — restrict the result to one or several pools.
  """
  @spec thread_pool(keyword()) :: result()
  def thread_pool(opts \\ []) do
    suffixed("/_cat/thread_pool", :thread_pool_patterns, opts)
  end

  @doc """
  Like `thread_pool/1`, but returns the body directly or raises the error
  exception.
  """
  @spec thread_pool!(keyword()) :: body()
  def thread_pool!(opts \\ []) do
    opts |> thread_pool() |> Dowser.unwrap()
  end

  ## Public functions — snapshots

  @doc """
  Lists the registered snapshot repositories
  ([CAT repositories](https://docs.opensearch.org/latest/api-reference/cat/cat-repositories/)).
  """
  @spec repositories(keyword()) :: result()
  def repositories(opts \\ []) do
    "/_cat/repositories"
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `repositories/1`, but returns the body directly or raises the error
  exception.
  """
  @spec repositories!(keyword()) :: body()
  def repositories!(opts \\ []) do
    opts |> repositories() |> Dowser.unwrap()
  end

  @doc """
  Lists the snapshots of a repository
  ([CAT snapshots](https://docs.opensearch.org/latest/api-reference/cat/cat-snapshots/)).

  ## Options

    * `:repository` — restrict the result to one or several repositories.
  """
  @spec snapshots(keyword()) :: result()
  def snapshots(opts \\ []) do
    suffixed("/_cat/snapshots", :repository, opts)
  end

  @doc """
  Like `snapshots/1`, but returns the body directly or raises the error
  exception.
  """
  @spec snapshots!(keyword()) :: body()
  def snapshots!(opts \\ []) do
    opts |> snapshots() |> Dowser.unwrap()
  end

  ## Repository metadata

  # Index-related functions exposed to `Dowser.Opensearch.Repository`:
  # `{index_spec, arity, kind}` where index_spec is :opts (`:index` option) or
  # {:pos, n} (positional index argument), and kind selects the variants
  # (:pair for `!`, :predicate for `?`).
  #
  # Only the endpoints that take an `:index` are here; the node- and
  # cluster-level ones have no index to bind.
  @doc false
  def __repository__ do
    [
      indices: {:opts, 1, :pair},
      count: {:opts, 1, :pair},
      shards: {:opts, 1, :pair},
      segments: {:opts, 1, :pair},
      recovery: {:opts, 1, :pair},
      segment_replication: {:opts, 1, :pair}
    ]
  end

  ## Private functions

  # Every cat endpoint with an optional path parameter has the same shape: pop
  # the option, append it to the base path.
  @spec suffixed(String.t(), atom(), keyword()) :: result()
  defp suffixed(base, key, opts) do
    {target, opts} = Keyword.pop(opts, key)

    base
    |> Helpers.suffix_path(target)
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  defp parse_help({:ok, body}) when is_binary(body) do
    endpoints =
      body
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&String.starts_with?(&1, "/"))

    {:ok, endpoints}
  end

  defp parse_help(result) do
    result
  end
end
