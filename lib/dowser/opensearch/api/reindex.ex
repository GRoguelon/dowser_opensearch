defmodule Dowser.Opensearch.Reindex do
  @moduledoc """
  The OpenSearch reindex and by-query APIs — the endpoints tagged `Reindex` in
  the [OpenSearch OpenAPI specification](https://github.com/opensearch-project/opensearch-api-specification).

  Built on `Dowser.Client`. Required OpenSearch attributes are positional
  arguments; everything optional lives in `opts`.

  OpenSearch groups `_reindex`, `_delete_by_query` and `_update_by_query` under
  one tag, along with the `_rethrottle` endpoint each of them has, so they all
  live here — where Elasticsearch tags them as document APIs.

  ## Shared conventions

    * Endpoints that accept a request body take it as their first argument,
      required — pass `%{}` to send nothing. The argument is named `query` when
      the body is an OpenSearch query DSL document and `body` otherwise.
    * The by-query endpoints require an index target, so they take it as an
      argument rather than an option.

  All remaining options are forwarded to `Dowser.Client.request/4`, e.g.
  `:context`, `:params` (query-string parameters), `:format`, `:keys` and
  `:http_opts` (including `:headers`) — plus `:codec`, this package's own,
  which picks the per-field codec for this one request (see
  `Dowser.Opensearch.Codec`).

  None of these endpoints is marked retryable: each one writes, and a
  `_reindex` or `_update_by_query` that timed out may well have applied part of
  its work, so re-sending it would redo that part. Pass `retry: [idempotent:
  true]` to override that for a call you know is safe to repeat.

  ## Running long operations in the background

  Every endpoint here can take longer than a request should, so OpenSearch
  accepts `params: [wait_for_completion: false]` on all of them: the response
  is then a task id, which `_tasks` reports on and the `*_rethrottle`
  functions below can slow down or speed up.

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
  @type id :: String.t()
  @type body :: term()
  @type result :: {:ok, body()} | {:error, Exception.t()}

  ## Public functions — reindex

  @doc """
  Copies documents from one index to another
  ([Reindex API](https://docs.opensearch.org/latest/api-reference/document-apis/reindex/)).

  `body` is the request body, e.g.
  `%{source: %{index: "old"}, dest: %{index: "new"}}`.

      %{source: %{index: "posts-v1"}, dest: %{index: "posts-v2"}}
      |> Dowser.Opensearch.Reindex.reindex(params: [wait_for_completion: false])
  """
  @spec reindex(map(), keyword()) :: result()
  def reindex(%{} = body, opts \\ []) do
    "/_reindex"
    |> Client.post(body, opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `reindex/2`, but returns the body directly or raises the error
  exception.
  """
  @spec reindex!(map(), keyword()) :: body()
  def reindex!(%{} = body, opts \\ []) do
    body |> reindex(opts) |> Dowser.unwrap()
  end

  ## Public functions — by-query operations

  @doc """
  Deletes every document matching a query
  ([Delete by query API](https://docs.opensearch.org/latest/api-reference/document-apis/delete-by-query/)).

  `query` is the delete body (query DSL map).
  """
  @spec delete_by_query(map(), index(), keyword()) :: result()
  def delete_by_query(%{} = query, index, opts \\ []) do
    with {:ok, path} <- Helpers.required_path(index, "/_delete_by_query") do
      path
      |> Client.post(query, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `delete_by_query/3`, but returns the body directly or raises the error
  exception.
  """
  @spec delete_by_query!(map(), index(), keyword()) :: body()
  def delete_by_query!(%{} = query, index, opts \\ []) do
    query |> delete_by_query(index, opts) |> Dowser.unwrap()
  end

  @doc """
  Updates every document matching a query
  ([Update by query API](https://docs.opensearch.org/latest/api-reference/document-apis/update-by-query/)).

  `body` is the request body (e.g. `query`, `script`); pass `%{}` to update
  everything.
  """
  @spec update_by_query(map(), index(), keyword()) :: result()
  def update_by_query(%{} = body, index, opts \\ []) do
    with {:ok, path} <- Helpers.required_path(index, "/_update_by_query") do
      path
      |> Client.post(body, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `update_by_query/3`, but returns the body directly or raises the error
  exception.
  """
  @spec update_by_query!(map(), index(), keyword()) :: body()
  def update_by_query!(%{} = body, index, opts \\ []) do
    body |> update_by_query(index, opts) |> Dowser.unwrap()
  end

  ## Public functions — rethrottling

  @doc """
  Changes the throttling of the running reindex task `task_id`
  ([Reindex rethrottle API](https://docs.opensearch.org/latest/api-reference/document-apis/reindex/)).

  `requests_per_second` is sent as the required query-string parameter; pass
  `-1` to remove the throttle entirely.
  """
  @spec reindex_rethrottle(id(), number(), keyword()) :: result()
  def reindex_rethrottle(task_id, requests_per_second, opts \\ []) do
    rethrottle("/_reindex", task_id, requests_per_second, opts)
  end

  @doc """
  Like `reindex_rethrottle/3`, but returns the body directly or raises the
  error exception.
  """
  @spec reindex_rethrottle!(id(), number(), keyword()) :: body()
  def reindex_rethrottle!(task_id, requests_per_second, opts \\ []) do
    task_id |> reindex_rethrottle(requests_per_second, opts) |> Dowser.unwrap()
  end

  @doc """
  Changes the throttling of the running delete-by-query task `task_id`
  ([Delete by query rethrottle API](https://docs.opensearch.org/latest/api-reference/document-apis/delete-by-query/)).

  `requests_per_second` is sent as the required query-string parameter.
  """
  @spec delete_by_query_rethrottle(id(), number(), keyword()) :: result()
  def delete_by_query_rethrottle(task_id, requests_per_second, opts \\ []) do
    rethrottle("/_delete_by_query", task_id, requests_per_second, opts)
  end

  @doc """
  Like `delete_by_query_rethrottle/3`, but returns the body directly or raises
  the error exception.
  """
  @spec delete_by_query_rethrottle!(id(), number(), keyword()) :: body()
  def delete_by_query_rethrottle!(task_id, requests_per_second, opts \\ []) do
    task_id |> delete_by_query_rethrottle(requests_per_second, opts) |> Dowser.unwrap()
  end

  @doc """
  Changes the throttling of the running update-by-query task `task_id`
  ([Update by query rethrottle API](https://docs.opensearch.org/latest/api-reference/document-apis/update-by-query/)).

  `requests_per_second` is sent as the required query-string parameter.
  """
  @spec update_by_query_rethrottle(id(), number(), keyword()) :: result()
  def update_by_query_rethrottle(task_id, requests_per_second, opts \\ []) do
    rethrottle("/_update_by_query", task_id, requests_per_second, opts)
  end

  @doc """
  Like `update_by_query_rethrottle/3`, but returns the body directly or raises
  the error exception.
  """
  @spec update_by_query_rethrottle!(id(), number(), keyword()) :: body()
  def update_by_query_rethrottle!(task_id, requests_per_second, opts \\ []) do
    task_id |> update_by_query_rethrottle(requests_per_second, opts) |> Dowser.unwrap()
  end

  ## Repository metadata

  # Index-related functions exposed to `Dowser.Opensearch.Repository`:
  # `{index_spec, arity, kind}` where index_spec is :opts (`:index` option) or
  # {:pos, n} (positional index argument), and kind selects the variants
  # (:pair for `!`, :predicate for `?`).
  #
  # `reindex/2` names its indices inside the body rather than in the path, and
  # the rethrottles target a task, so neither can be bound to a repository's
  # index.
  @doc false
  def __repository__ do
    [
      delete_by_query: {{:pos, 1}, 3, :pair},
      update_by_query: {{:pos, 1}, 3, :pair}
    ]
  end

  ## Private functions

  @spec rethrottle(String.t(), id(), number(), keyword()) :: result()
  defp rethrottle(prefix, task_id, requests_per_second, opts) do
    opts = Helpers.put_param(opts, :requests_per_second, requests_per_second)

    (prefix <> "/" <> URI.encode(task_id) <> "/_rethrottle")
    |> Client.post(nil, opts)
    |> Helpers.parse_result()
  end
end
