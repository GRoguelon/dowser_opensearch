defmodule Dowser.Opensearch.IndexStateManagement do
  @moduledoc """
  The OpenSearch Index State Management (ISM) APIs — the policy endpoints tagged
  `Index State Management` in the
  [OpenSearch OpenAPI specification](https://github.com/opensearch-project/opensearch-api-specification).

  Built on `Dowser.Client`. Required OpenSearch attributes are positional
  arguments; everything optional lives in `opts`.

  ISM is an OpenSearch plugin with no Elasticsearch counterpart (it answers the
  same need as Elastic's ILM). A *policy* describes an index's lifecycle as a
  list of states — hot, warm, cold, delete — each with actions to run and
  transitions to the next; ISM then walks every matching index through them on
  its own schedule.

  ## What this module covers

  The tag bundles three separate plugin features under one name. This module is
  the ISM policy API proper — the twelve endpoints under `/_plugins/_ism`, plus
  `refresh_search_analyzers/2`.

  The other two, **rollup jobs** (`/_plugins/_rollup`) and **transform jobs**
  (`/_plugins/_transform`), share the tag but are their own features and are
  not covered here yet.

  ## Plugin paths

  These endpoints live under `/_plugins/_ism`. Every one is also served under
  the older `/_opendistro/_ism` prefix, from before the OpenDistro-to-OpenSearch
  rename; this module uses `/_plugins` throughout, which every supported
  version serves.

  ## Error bodies

  ISM does not always answer with the standard error envelope: some failures
  come back as a flat `%{"error" => "some message"}`. `Dowser.Opensearch.Error`
  recognizes both, so that shape lands in `:reason` with `:type` left `nil`.

  ## Shared conventions

    * Endpoints that accept a request body take it as their first argument,
      required — pass `%{}` to send nothing.
    * `:index` — the index target the operation applies to, as an option;
      absent to let the request apply to every managed index.
    * `HEAD` existence checks come as a pair where the `?` variant plays the
      bang role: `policy_exists/2` returns `{:ok, boolean()}` or
      `{:error, exception}`, `policy_exists?/2` returns the bare boolean
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

  ## Module attributes

  @base "/_plugins/_ism"

  ## Typespecs

  @type index :: Target.t()
  @type policy_id :: Target.name()
  @type body :: term()
  @type result :: {:ok, body()} | {:error, Exception.t()}
  @type exists_result :: {:ok, boolean()} | {:error, Exception.t()}

  ## Public functions — policies

  @doc """
  Creates or updates the policy `policy_id`
  ([Create policy API](https://docs.opensearch.org/latest/im-plugin/ism/api/)).

  `policy` is the request body, `%{policy: %{...}}`:

      %{
        policy: %{
          description: "hot-warm-delete",
          default_state: "hot",
          states: [
            %{name: "hot", actions: [], transitions: [%{state_name: "delete", conditions: %{min_index_age: "30d"}}]},
            %{name: "delete", actions: [%{delete: %{}}], transitions: []}
          ]
        }
      }
      |> Dowser.Opensearch.IndexStateManagement.put_policy("logs-lifecycle")

  Updating an existing policy needs its current version, passed as
  `params: [if_seq_no: seq_no, if_primary_term: primary_term]` — `get_policy/2`
  returns both. Without them OpenSearch refuses the update rather than
  clobbering a concurrent change.

  Note that changing a policy does not move the indices already managed by it
  onto the new version: `change_policy/2` is what does that.
  """
  @spec put_policy(map(), policy_id(), keyword()) :: result()
  def put_policy(%{} = policy, policy_id, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(policy_id, "policy_id") do
      (@base <> "/policies/" <> segment)
      |> Client.put(policy, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `put_policy/3`, but returns the body directly or raises the error
  exception.
  """
  @spec put_policy!(map(), policy_id(), keyword()) :: body()
  def put_policy!(%{} = policy, policy_id, opts \\ []) do
    policy |> put_policy(policy_id, opts) |> Dowser.unwrap()
  end

  @doc """
  Returns the policy `policy_id`
  ([Get policy API](https://docs.opensearch.org/latest/im-plugin/ism/api/)).

  The response carries `_seq_no` and `_primary_term` alongside the policy, which
  is what `put_policy/3` needs to update it.
  """
  @spec get_policy(policy_id(), keyword()) :: result()
  def get_policy(policy_id, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(policy_id, "policy_id") do
      (@base <> "/policies/" <> segment)
      |> Client.get(opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `get_policy/2`, but returns the body directly or raises the error
  exception.
  """
  @spec get_policy!(policy_id(), keyword()) :: body()
  def get_policy!(policy_id, opts \\ []) do
    policy_id |> get_policy(opts) |> Dowser.unwrap()
  end

  @doc """
  Returns every policy
  ([Get policies API](https://docs.opensearch.org/latest/im-plugin/ism/api/)).

  ## Options

    * `:params` — e.g. `from`, `size`, `sortField`, `sortOrder`, `queryString`.
  """
  @spec get_policies(keyword()) :: result()
  def get_policies(opts \\ []) do
    (@base <> "/policies")
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `get_policies/1`, but returns the body directly or raises the error
  exception.
  """
  @spec get_policies!(keyword()) :: body()
  def get_policies!(opts \\ []) do
    opts |> get_policies() |> Dowser.unwrap()
  end

  @doc """
  Creates or updates several policies in one request
  ([Create policy API](https://docs.opensearch.org/latest/im-plugin/ism/api/)).

  `body` is the request body holding the policies to write.
  """
  @spec put_policies(map(), keyword()) :: result()
  def put_policies(%{} = body, opts \\ []) do
    (@base <> "/policies")
    |> Client.put(body, opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `put_policies/2`, but returns the body directly or raises the error
  exception.
  """
  @spec put_policies!(map(), keyword()) :: body()
  def put_policies!(%{} = body, opts \\ []) do
    body |> put_policies(opts) |> Dowser.unwrap()
  end

  @doc """
  Deletes the policy `policy_id`
  ([Delete policy API](https://docs.opensearch.org/latest/im-plugin/ism/api/)).

  The indices already managed by it keep running their copy of it until they
  are removed from it with `remove_policy/1`.
  """
  @spec delete_policy(policy_id(), keyword()) :: result()
  def delete_policy(policy_id, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(policy_id, "policy_id") do
      (@base <> "/policies/" <> segment)
      |> Client.delete(nil, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `delete_policy/2`, but returns the body directly or raises the error
  exception.
  """
  @spec delete_policy!(policy_id(), keyword()) :: body()
  def delete_policy!(policy_id, opts \\ []) do
    policy_id |> delete_policy(opts) |> Dowser.unwrap()
  end

  @doc """
  Checks whether the policy `policy_id` exists.

  Returns `{:ok, true}`, `{:ok, false}` or `{:error, exception}`.
  """
  @spec policy_exists(policy_id(), keyword()) :: exists_result()
  def policy_exists(policy_id, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(policy_id, "policy_id") do
      opts = Helpers.put_default_format(opts, :resp_format, :raw)

      :head
      |> Client.request(@base <> "/policies/" <> segment, nil, opts)
      |> Helpers.parse_exists()
    end
  end

  @doc """
  Like `policy_exists/2`, but returns the boolean directly (`404` → `false`) or
  raises the error exception.
  """
  @spec policy_exists?(policy_id(), keyword()) :: boolean()
  def policy_exists?(policy_id, opts \\ []) do
    policy_id |> policy_exists(opts) |> Dowser.unwrap()
  end

  ## Public functions — managing indices

  @doc """
  Puts indices under the management of a policy
  ([Add policy API](https://docs.opensearch.org/latest/im-plugin/ism/api/)).

  `body` names the policy, `%{policy_id: "logs-lifecycle"}`.

  ## Options

    * `:index` — index target; absent to apply to every index the request
      resolves to.

  This attaches the policy as it stands now: the index keeps running that
  snapshot of it even if the policy is edited afterwards.
  """
  @spec add_policy(map(), keyword()) :: result()
  def add_policy(%{} = body, opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    (@base <> "/add")
    |> Helpers.suffix_path(index)
    |> Client.post(body, opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `add_policy/2`, but returns the body directly or raises the error
  exception.
  """
  @spec add_policy!(map(), keyword()) :: body()
  def add_policy!(%{} = body, opts \\ []) do
    body |> add_policy(opts) |> Dowser.unwrap()
  end

  @doc """
  Removes indices from the management of their policy
  ([Remove policy API](https://docs.opensearch.org/latest/im-plugin/ism/api/)).

  The endpoint takes no request body.

  ## Options

    * `:index` — index target; absent to apply to every managed index.
  """
  @spec remove_policy(keyword()) :: result()
  def remove_policy(opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    (@base <> "/remove")
    |> Helpers.suffix_path(index)
    |> Client.post(nil, opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `remove_policy/1`, but returns the body directly or raises the error
  exception.
  """
  @spec remove_policy!(keyword()) :: body()
  def remove_policy!(opts \\ []) do
    opts |> remove_policy() |> Dowser.unwrap()
  end

  @doc """
  Changes which policy — or which state of it — manages indices
  ([Change policy API](https://docs.opensearch.org/latest/im-plugin/ism/api/)).

  `body` names the new policy and, optionally, which indices it applies to:
  `%{policy_id: "v2", state: "hot", include: [%{state: "warm"}]}`.

  This is what moves indices already managed onto an edited policy, which
  `put_policy/3` alone does not do. The change is queued: ISM applies it when
  each index next finishes the action it is in, so a long-running force-merge
  finishes first.

  ## Options

    * `:index` — index target; absent to apply to every managed index.
  """
  @spec change_policy(map(), keyword()) :: result()
  def change_policy(%{} = body, opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    (@base <> "/change_policy")
    |> Helpers.suffix_path(index)
    |> Client.post(body, opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `change_policy/2`, but returns the body directly or raises the error
  exception.
  """
  @spec change_policy!(map(), keyword()) :: body()
  def change_policy!(%{} = body, opts \\ []) do
    body |> change_policy(opts) |> Dowser.unwrap()
  end

  @doc """
  Retries the failed action of managed indices
  ([Retry failed index API](https://docs.opensearch.org/latest/im-plugin/ism/api/)).

  `body` may name the state to retry from, `%{state: "warm"}`; pass `%{}` to
  retry the action that failed.

  An index whose action fails stops there until it is retried — ISM does not
  retry on its own past the policy's own `retry` settings — so this is the way
  out once whatever caused the failure is fixed.

  ## Options

    * `:index` — index target; absent to retry every failed index.
  """
  @spec retry_index(map(), keyword()) :: result()
  def retry_index(%{} = body, opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    (@base <> "/retry")
    |> Helpers.suffix_path(index)
    |> Client.post(body, opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `retry_index/2`, but returns the body directly or raises the error
  exception.
  """
  @spec retry_index!(map(), keyword()) :: body()
  def retry_index!(%{} = body, opts \\ []) do
    body |> retry_index(opts) |> Dowser.unwrap()
  end

  @doc """
  Explains how ISM is managing indices — which policy, which state, and what
  failed
  ([Explain API](https://docs.opensearch.org/latest/im-plugin/ism/api/)).

  The first place to look when an index is not moving through its policy:

      {:ok, explanation} =
        Dowser.Opensearch.IndexStateManagement.explain_policy(index: "logs-000001")

  ## Options

    * `:index` — index target; absent for every managed index.
    * `:params` — e.g. `show_policy: true` to include each policy in full.
  """
  @spec explain_policy(keyword()) :: result()
  def explain_policy(opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    (@base <> "/explain")
    |> Helpers.suffix_path(index)
    |> Client.get(Helpers.put_idempotent(opts, true))
    |> Helpers.parse_result()
  end

  @doc """
  Like `explain_policy/1`, but returns the body directly or raises the error
  exception.
  """
  @spec explain_policy!(keyword()) :: body()
  def explain_policy!(opts \\ []) do
    opts |> explain_policy() |> Dowser.unwrap()
  end

  ## Public functions — search analyzers

  @doc """
  Reloads the search analyzers of one or several indices
  ([Refresh search analyzers API](https://docs.opensearch.org/latest/im-plugin/refresh-analyzer/)).

  Picks up changes to the synonym files a `search_time` analyzer reads, without
  closing and reopening the index. Note that this lives under `/_plugins`
  directly rather than under `/_plugins/_ism`.
  """
  @spec refresh_search_analyzers(index(), keyword()) :: result()
  def refresh_search_analyzers(index, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(index, "index") do
      ("/_plugins/_refresh_search_analyzers/" <> segment)
      |> Client.post(nil, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `refresh_search_analyzers/2`, but returns the body directly or raises
  the error exception.
  """
  @spec refresh_search_analyzers!(index(), keyword()) :: body()
  def refresh_search_analyzers!(index, opts \\ []) do
    index |> refresh_search_analyzers(opts) |> Dowser.unwrap()
  end

  ## Repository metadata

  # Index-related functions exposed to `Dowser.Opensearch.Repository`:
  # `{index_spec, arity, kind}` where index_spec is :opts (`:index` option) or
  # {:pos, n} (positional index argument), and kind selects the variants
  # (:pair for `!`, :predicate for `?`).
  #
  # The policy CRUD is addressed by policy id rather than index, so only the
  # index-targeting operations are here.
  @doc false
  def __repository__ do
    [
      add_policy: {:opts, 2, :pair},
      remove_policy: {:opts, 1, :pair},
      change_policy: {:opts, 2, :pair},
      retry_index: {:opts, 2, :pair},
      explain_policy: {:opts, 1, :pair},
      refresh_search_analyzers: {{:pos, 0}, 2, :pair}
    ]
  end
end
