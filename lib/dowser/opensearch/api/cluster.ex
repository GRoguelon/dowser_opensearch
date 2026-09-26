defmodule Dowser.Opensearch.Cluster do
  @moduledoc """
  The OpenSearch cluster APIs — every endpoint tagged `Cluster` in the
  [OpenSearch OpenAPI specification](https://github.com/opensearch-project/opensearch-api-specification)
  (health, state, settings, routing and the awareness controls).

  Built on `Dowser.Client`. Required OpenSearch attributes are positional
  arguments; everything optional lives in `opts`.

  For the node name, cluster name and version, see
  `Dowser.Opensearch.Info.info/1` (`GET /`).

  ## Shared conventions

    * Endpoints that accept a request body take it as their first argument,
      required — pass `%{}` to send nothing.
    * Optional path parameters are options (`:index`, `:metric`, `:node_id`).
      Where OpenSearch reads one segment as the position *after* another —
      `state/1`'s index after its metric — naming the inner one without the
      outer is an `ArgumentError` rather than a silently wrong path.

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

  ## Public functions — health and state

  @doc """
  Returns the health of the cluster, or of one or several indices
  ([Cluster health API](https://docs.opensearch.org/latest/api-reference/cluster-api/cluster-health/)).

  ## Options

    * `:index` — index target; absent for the whole cluster.
    * `:params` — e.g. `level`, `wait_for_status`, `timeout`.

  `wait_for_status` is what makes this endpoint useful in a setup script: it
  blocks until the cluster reaches the status asked for, or the timeout
  elapses.

      Dowser.Opensearch.Cluster.health!(params: [wait_for_status: "yellow", timeout: "30s"])
  """
  @spec health(keyword()) :: result()
  def health(opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    "/_cluster/health"
    |> Helpers.suffix_path(index)
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
  Returns the cluster state — the metadata the cluster manager holds
  ([Cluster state API](https://docs.opensearch.org/latest/api-reference/cluster-api/cluster-stats/)).

  ## Options

    * `:metric` — restrict the state to one or several metrics (`metadata`,
      `routing_table`, `nodes`, …).
    * `:index` — index target. OpenSearch reads it as the segment *after* the
      metric, so it needs one: passing an index with no metric is an
      `ArgumentError`. Use `metric: "_all"` to ask for everything.

  The full state of a large cluster is a big document; naming a metric is
  usually what you want.
  """
  @spec state(keyword()) :: result()
  def state(opts \\ []) do
    {metric, opts} = Keyword.pop(opts, :metric)
    {index, opts} = Keyword.pop(opts, :index)

    with {:ok, path} <- nested_path("/_cluster/state", {metric, :metric}, {index, :index}) do
      path
      |> Client.get(opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `state/1`, but returns the body directly or raises the error exception.
  """
  @spec state!(keyword()) :: body()
  def state!(opts \\ []) do
    opts |> state() |> Dowser.unwrap()
  end

  @doc """
  Returns cluster-wide statistics — indices, nodes, shards, and the plugins
  installed
  ([Cluster stats API](https://docs.opensearch.org/latest/api-reference/cluster-api/cluster-stats/)).

  ## Options

    * `:node_id` — restrict the statistics to one or several nodes.
  """
  @spec stats(keyword()) :: result()
  def stats(opts \\ []) do
    {node_id, opts} = Keyword.pop(opts, :node_id)

    "/_cluster/stats"
    |> Helpers.suffix_path(node_id, "/nodes")
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `stats/1`, but returns the body directly or raises the error exception.
  """
  @spec stats!(keyword()) :: body()
  def stats!(opts \\ []) do
    opts |> stats() |> Dowser.unwrap()
  end

  @doc """
  Returns the cluster-level changes not yet executed
  ([Pending tasks API](https://docs.opensearch.org/latest/api-reference/cluster-api/cluster-pending-tasks/)).
  """
  @spec pending_tasks(keyword()) :: result()
  def pending_tasks(opts \\ []) do
    "/_cluster/pending_tasks"
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
  Returns the configured remote clusters
  ([Remote cluster info API](https://docs.opensearch.org/latest/api-reference/cluster-api/cluster-stats/)).

  Note the path: this one endpoint lives at `/_remote/info`, not under
  `/_cluster`.
  """
  @spec remote_info(keyword()) :: result()
  def remote_info(opts \\ []) do
    "/_remote/info"
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `remote_info/1`, but returns the body directly or raises the error
  exception.
  """
  @spec remote_info!(keyword()) :: body()
  def remote_info!(opts \\ []) do
    opts |> remote_info() |> Dowser.unwrap()
  end

  ## Public functions — settings

  @doc """
  Returns the cluster settings
  ([Cluster settings API](https://docs.opensearch.org/latest/api-reference/cluster-api/cluster-settings/)).

  ## Options

    * `:params` — e.g. `include_defaults: true` to see the settings nobody has
      changed, which is otherwise omitted.
  """
  @spec get_settings(keyword()) :: result()
  def get_settings(opts \\ []) do
    "/_cluster/settings"
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `get_settings/1`, but returns the body directly or raises the error
  exception.
  """
  @spec get_settings!(keyword()) :: body()
  def get_settings!(opts \\ []) do
    opts |> get_settings() |> Dowser.unwrap()
  end

  @doc """
  Updates the cluster settings
  ([Cluster settings API](https://docs.opensearch.org/latest/api-reference/cluster-api/cluster-settings/)).

  `settings` is the settings body, under `persistent` or `transient`:

      %{persistent: %{"cluster.routing.allocation.enable" => "all"}}
      |> Dowser.Opensearch.Cluster.put_settings()

  `persistent` survives a full cluster restart, `transient` does not. Setting a
  value to `nil` resets it to its default.
  """
  @spec put_settings(map(), keyword()) :: result()
  def put_settings(%{} = settings, opts \\ []) do
    "/_cluster/settings"
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

  ## Public functions — routing

  @doc """
  Moves, allocates or cancels shards by hand
  ([Cluster reroute API](https://docs.opensearch.org/latest/api-reference/cluster-api/cluster-reroute/)).

  `body` is the request body, typically `%{commands: [...]}`; pass `%{}` to let
  OpenSearch retry the allocations it had given up on.

  Use `params: [dry_run: true]` to see what the commands would do without
  applying them, and `params: [explain: true]` for why each one was accepted or
  rejected.
  """
  @spec reroute(map(), keyword()) :: result()
  def reroute(%{} = body, opts \\ []) do
    "/_cluster/reroute"
    |> Client.post(body, opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `reroute/2`, but returns the body directly or raises the error
  exception.
  """
  @spec reroute!(map(), keyword()) :: body()
  def reroute!(%{} = body, opts \\ []) do
    body |> reroute(opts) |> Dowser.unwrap()
  end

  @doc """
  Explains why a shard is or is not allocated where it is
  ([Cluster allocation explain API](https://docs.opensearch.org/latest/api-reference/cluster-api/cluster-allocation/)).

  `body` names the shard to explain, e.g.
  `%{index: "posts", shard: 0, primary: true}`; pass `%{}` to have OpenSearch
  pick the first unassigned shard it finds — which is usually the one you are
  asking about.
  """
  @spec allocation_explain(map(), keyword()) :: result()
  def allocation_explain(%{} = body, opts \\ []) do
    "/_cluster/allocation/explain"
    |> Client.post(body, Helpers.put_idempotent(opts, true))
    |> Helpers.parse_result()
  end

  @doc """
  Like `allocation_explain/2`, but returns the body directly or raises the
  error exception.
  """
  @spec allocation_explain!(map(), keyword()) :: body()
  def allocation_explain!(%{} = body, opts \\ []) do
    body |> allocation_explain(opts) |> Dowser.unwrap()
  end

  ## Public functions — voting configuration

  @doc """
  Excludes nodes from the voting configuration
  ([Voting configuration exclusions API](https://docs.opensearch.org/latest/api-reference/cluster-api/cluster-settings/)).

  The nodes to exclude are named through `:params` — `node_names` or
  `node_ids`. This is the step before removing cluster-manager-eligible nodes,
  so the remaining ones can still elect a manager.
  """
  @spec post_voting_config_exclusions(keyword()) :: result()
  def post_voting_config_exclusions(opts \\ []) do
    "/_cluster/voting_config_exclusions"
    |> Client.post(nil, opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `post_voting_config_exclusions/1`, but returns the body directly or
  raises the error exception.
  """
  @spec post_voting_config_exclusions!(keyword()) :: body()
  def post_voting_config_exclusions!(opts \\ []) do
    opts |> post_voting_config_exclusions() |> Dowser.unwrap()
  end

  @doc """
  Clears the voting configuration exclusions
  ([Voting configuration exclusions API](https://docs.opensearch.org/latest/api-reference/cluster-api/cluster-settings/)).
  """
  @spec delete_voting_config_exclusions(keyword()) :: result()
  def delete_voting_config_exclusions(opts \\ []) do
    "/_cluster/voting_config_exclusions"
    |> Client.delete(nil, opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `delete_voting_config_exclusions/1`, but returns the body directly or
  raises the error exception.
  """
  @spec delete_voting_config_exclusions!(keyword()) :: body()
  def delete_voting_config_exclusions!(opts \\ []) do
    opts |> delete_voting_config_exclusions() |> Dowser.unwrap()
  end

  ## Public functions — weighted routing

  @doc """
  Sets the search-traffic weights of an awareness attribute's zones
  ([Weighted routing API](https://docs.opensearch.org/latest/api-reference/cluster-api/cluster-awareness/)).

  An OpenSearch addition with no Elasticsearch counterpart. `attribute` is the
  awareness attribute (typically `"zone"`), and `body` the weights, e.g.
  `%{weights: %{"us-east-1a" => "1", "us-east-1b" => "0"}}` — a weight of `0`
  takes a zone out of search rotation without removing its nodes.
  """
  @spec put_weighted_routing(map(), name(), keyword()) :: result()
  def put_weighted_routing(%{} = body, attribute, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(attribute, "attribute") do
      ("/_cluster/routing/awareness/" <> segment <> "/weights")
      |> Client.put(body, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `put_weighted_routing/3`, but returns the body directly or raises the
  error exception.
  """
  @spec put_weighted_routing!(map(), name(), keyword()) :: body()
  def put_weighted_routing!(%{} = body, attribute, opts \\ []) do
    body |> put_weighted_routing(attribute, opts) |> Dowser.unwrap()
  end

  @doc """
  Returns the weights of an awareness attribute's zones
  ([Weighted routing API](https://docs.opensearch.org/latest/api-reference/cluster-api/cluster-awareness/)).
  """
  @spec get_weighted_routing(name(), keyword()) :: result()
  def get_weighted_routing(attribute, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(attribute, "attribute") do
      ("/_cluster/routing/awareness/" <> segment <> "/weights")
      |> Client.get(opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `get_weighted_routing/2`, but returns the body directly or raises the
  error exception.
  """
  @spec get_weighted_routing!(name(), keyword()) :: body()
  def get_weighted_routing!(attribute, opts \\ []) do
    attribute |> get_weighted_routing(opts) |> Dowser.unwrap()
  end

  @doc """
  Clears the weighted routing configuration
  ([Weighted routing API](https://docs.opensearch.org/latest/api-reference/cluster-api/cluster-awareness/)).

  Note that OpenSearch serves the delete on the unscoped path, with no
  attribute segment — so this clears the whole configuration rather than one
  attribute's.
  """
  @spec delete_weighted_routing(keyword()) :: result()
  def delete_weighted_routing(opts \\ []) do
    "/_cluster/routing/awareness/weights"
    |> Client.delete(nil, opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `delete_weighted_routing/1`, but returns the body directly or raises the
  error exception.
  """
  @spec delete_weighted_routing!(keyword()) :: body()
  def delete_weighted_routing!(opts \\ []) do
    opts |> delete_weighted_routing() |> Dowser.unwrap()
  end

  ## Public functions — decommission awareness

  @doc """
  Decommissions a zone, taking its nodes out of the cluster
  ([Decommission API](https://docs.opensearch.org/latest/api-reference/cluster-api/cluster-decommission/)).

  An OpenSearch addition with no Elasticsearch counterpart.
  `awareness_attribute_name` is the attribute (typically `"zone"`) and
  `awareness_attribute_value` the zone to decommission.

  Weight the zone down with `put_weighted_routing/3` first: decommissioning
  moves traffic off its nodes and then excludes them, and doing it to a zone
  still taking searches drops the ones in flight.
  """
  @spec put_decommission_awareness(name(), name(), keyword()) :: result()
  def put_decommission_awareness(
        awareness_attribute_name,
        awareness_attribute_value,
        opts \\ []
      ) do
    with {:ok, name_segment} <-
           Helpers.required_segment(awareness_attribute_name, "awareness_attribute_name"),
         {:ok, value_segment} <-
           Helpers.required_segment(awareness_attribute_value, "awareness_attribute_value") do
      ("/_cluster/decommission/awareness/" <> name_segment <> "/" <> value_segment)
      |> Client.put(nil, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `put_decommission_awareness/3`, but returns the body directly or raises
  the error exception.
  """
  @spec put_decommission_awareness!(name(), name(), keyword()) :: body()
  def put_decommission_awareness!(
        awareness_attribute_name,
        awareness_attribute_value,
        opts \\ []
      ) do
    awareness_attribute_name
    |> put_decommission_awareness(awareness_attribute_value, opts)
    |> Dowser.unwrap()
  end

  @doc """
  Returns the status of a zone decommission
  ([Decommission API](https://docs.opensearch.org/latest/api-reference/cluster-api/cluster-decommission/)).
  """
  @spec get_decommission_awareness(name(), keyword()) :: result()
  def get_decommission_awareness(awareness_attribute_name, opts \\ []) do
    with {:ok, segment} <-
           Helpers.required_segment(awareness_attribute_name, "awareness_attribute_name") do
      ("/_cluster/decommission/awareness/" <> segment <> "/_status")
      |> Client.get(opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `get_decommission_awareness/2`, but returns the body directly or raises
  the error exception.
  """
  @spec get_decommission_awareness!(name(), keyword()) :: body()
  def get_decommission_awareness!(awareness_attribute_name, opts \\ []) do
    awareness_attribute_name |> get_decommission_awareness(opts) |> Dowser.unwrap()
  end

  @doc """
  Recommissions every decommissioned zone
  ([Decommission API](https://docs.opensearch.org/latest/api-reference/cluster-api/cluster-decommission/)).

  As with `delete_weighted_routing/1`, OpenSearch serves this on the unscoped
  path, so it clears every decommission rather than one attribute's.
  """
  @spec delete_decommission_awareness(keyword()) :: result()
  def delete_decommission_awareness(opts \\ []) do
    "/_cluster/decommission/awareness"
    |> Client.delete(nil, opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `delete_decommission_awareness/1`, but returns the body directly or
  raises the error exception.
  """
  @spec delete_decommission_awareness!(keyword()) :: body()
  def delete_decommission_awareness!(opts \\ []) do
    opts |> delete_decommission_awareness() |> Dowser.unwrap()
  end

  ## Private functions

  # Two optional segments where OpenSearch reads the second as the position
  # after the first: the inner one alone would land in the outer's place and
  # mean something else, so it is refused instead.
  @spec nested_path(String.t(), {name(), atom()}, {name(), atom()}) ::
          {:ok, String.t()} | {:error, Helpers.argument_error()}
  defp nested_path(base, {outer, outer_key}, {inner, inner_key}) do
    case {Target.segment(outer), Target.segment(inner)} do
      {nil, nil} ->
        {:ok, base}

      {nil, _inner} ->
        {:error,
         %ArgumentError{
           message:
             "#{inspect(inner_key)} needs #{inspect(outer_key)}: OpenSearch reads it as " <>
               "the path segment after one, got: #{inspect(inner)}"
         }}

      {outer, nil} ->
        {:ok, base <> "/" <> outer}

      {outer, inner} ->
        {:ok, base <> "/" <> outer <> "/" <> inner}
    end
  end
end
