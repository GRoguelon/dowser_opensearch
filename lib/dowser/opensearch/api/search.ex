defmodule Dowser.Opensearch.Search do
  @moduledoc """
  The OpenSearch search APIs — the endpoints tagged `Search` in the
  [OpenSearch OpenAPI specification](https://github.com/opensearch-project/opensearch-api-specification).

  Built on `Dowser.Client`. Required OpenSearch attributes are positional
  arguments; everything optional lives in `opts`. Request bodies come first so
  they pipe naturally.

  ## Shared conventions

    * `:index` — where the endpoint accepts an optional index target:
      `nil`/absent for all indices, a single index string, or a list of index
      strings (joined with `,`). Endpoints that *require* an index take it as
      the first argument instead.
    * Endpoints that accept a request body take it as their first argument,
      required — pass `%{}` to send nothing. The argument is named `query`
      when the body is an OpenSearch query DSL document, and `body` (or a
      more specific name such as `template` or `searches`) otherwise.
    * When OpenSearch serves an operation over both `GET` and `POST`, the
      request uses `POST` whenever a body is present and `GET` otherwise.

  All remaining options are forwarded to `Dowser.Client.request/4`, e.g.
  `:context`, `:params` (query-string parameters), `:format`, `:keys` and
  `:http_opts` (including `:headers`) — plus `:codec`, this package's own,
  which picks the per-field codec for this one request (see
  `Dowser.Opensearch.Codec`).

  Response values are cast automatically wherever `Dowser.Opensearch.Codec` is
  configured as `:decoder` — no per-call option needed. A query is never cast:
  build it in the shape OpenSearch expects.

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
  @type query :: map()
  @type id :: String.t()
  @type scroll_id :: String.t() | [String.t()]
  @type pit_id :: String.t() | [String.t()]
  @type body :: term()
  @type result :: {:ok, body()} | {:error, Exception.t()}

  ## Public functions — search

  @doc """
  Runs a search against one, several, or all indices
  ([Search API](https://docs.opensearch.org/latest/api-reference/search-apis/search/)).

  `query` is the search body (the OpenSearch query DSL as a map); pass `%{}`
  to match everything. It comes first so it can be piped:

      %{query: %{match: %{title: "hello"}}}
      |> Dowser.Opensearch.Search.search(index: "posts")

  Every key in the response is cast per `:keys`. Wherever
  `Dowser.Opensearch.Codec` is configured as `:decoder`, each hit's `_source`
  is additionally cast against its own index mapping (dates become `DateTime`,
  IPs become `:inet` tuples, and so on) — automatically, at any nesting depth,
  so `msearch/2`, `search_template/2`, `scroll/2` and the rest get the same
  treatment with no extra options.

  ## Options

    * `:index` — `nil`/absent for all indices, a single index string, or a list
      of index strings (joined with `,`).
  """
  @spec search(query(), keyword()) :: result()
  def search(%{} = query, opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    index
    |> Helpers.path("/_search")
    |> Client.post(query, Helpers.put_idempotent(opts, true))
    |> Helpers.parse_result()
  end

  @doc """
  Like `search/2`, but returns the body directly or raises the error exception.
  """
  @spec search!(query(), keyword()) :: body()
  def search!(%{} = query, opts \\ []) do
    query |> search(opts) |> Dowser.unwrap()
  end

  @doc """
  Runs several searches in one request
  ([Multi-search API](https://docs.opensearch.org/latest/api-reference/search-apis/multi-search/)).

  `searches` is a flat list alternating header and body maps, encoded as
  NDJSON:

      Dowser.Opensearch.Search.msearch([
        %{},
        %{query: %{match_all: %{}}},
        %{index: "comments"},
        %{query: %{match: %{body: "hello"}}}
      ])

  ## Options

    * `:index` — default index target for searches whose header has none.
  """
  @spec msearch([map()], keyword()) :: result()
  def msearch(searches, opts \\ []) when is_list(searches) do
    {index, opts} = Keyword.pop(opts, :index)
    opts = Helpers.put_default_format(opts, :req_format, :ndjson)

    index
    |> Helpers.path("/_msearch")
    |> Client.post(searches, Helpers.put_idempotent(opts, true))
    |> Helpers.parse_result()
  end

  @doc """
  Like `msearch/2`, but returns the body directly or raises the error exception.
  """
  @spec msearch!([map()], keyword()) :: body()
  def msearch!(searches, opts \\ []) do
    searches |> msearch(opts) |> Dowser.unwrap()
  end

  @doc """
  Counts the documents matching a query
  ([Count API](https://docs.opensearch.org/latest/api-reference/search-apis/count/)).

  `query` is the count body (query DSL map); pass `%{}` to count everything.

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec count(query(), keyword()) :: result()
  def count(%{} = query, opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    index
    |> Helpers.path("/_count")
    |> Client.post(query, Helpers.put_idempotent(opts, true))
    |> Helpers.parse_result()
  end

  @doc """
  Like `count/2`, but returns the body directly or raises the error exception.
  """
  @spec count!(query(), keyword()) :: body()
  def count!(%{} = query, opts \\ []) do
    query |> count(opts) |> Dowser.unwrap()
  end

  @doc """
  Explains whether and how the document `id` in `index` matches a query
  ([Explain API](https://docs.opensearch.org/latest/api-reference/search-apis/explain/)).

  `query` is the explain body (query DSL map).
  """
  @spec explain(query(), index(), id(), keyword()) :: result()
  def explain(%{} = query, index, id, opts \\ []) do
    with {:ok, path} <- Helpers.required_path(index, "/_explain/" <> URI.encode(id)) do
      path
      |> Client.post(query, Helpers.put_idempotent(opts, true))
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `explain/4`, but returns the body directly or raises the error exception.
  """
  @spec explain!(query(), index(), id(), keyword()) :: body()
  def explain!(%{} = query, index, id, opts \\ []) do
    query |> explain(index, id, opts) |> Dowser.unwrap()
  end

  @doc """
  Returns the capabilities of fields across indices
  ([Field capabilities API](https://docs.opensearch.org/latest/api-reference/search-apis/field-caps/)).

  `body` is the request body, e.g.
  `%{fields: ["title"], index_filter: %{...}}`.

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec field_caps(map(), keyword()) :: result()
  def field_caps(%{} = body, opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    index
    |> Helpers.path("/_field_caps")
    |> Client.post(body, Helpers.put_idempotent(opts, true))
    |> Helpers.parse_result()
  end

  @doc """
  Like `field_caps/2`, but returns the body directly or raises the error
  exception.
  """
  @spec field_caps!(map(), keyword()) :: body()
  def field_caps!(%{} = body, opts \\ []) do
    body |> field_caps(opts) |> Dowser.unwrap()
  end

  @doc """
  Returns the indices and shards a search would run against
  ([Search shards API](https://docs.opensearch.org/latest/api-reference/search-apis/search-shards/)).

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec search_shards(keyword()) :: result()
  def search_shards(opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    index
    |> Helpers.path("/_search_shards")
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `search_shards/1`, but returns the body directly or raises the error
  exception.
  """
  @spec search_shards!(keyword()) :: body()
  def search_shards!(opts \\ []) do
    opts |> search_shards() |> Dowser.unwrap()
  end

  @doc """
  Validates a query without running it
  ([Validate query API](https://docs.opensearch.org/latest/api-reference/search-apis/validate/)).

  `query` is the query body to check; pass `%{}` to validate nothing in
  particular. Use `params: [explain: true]` to get the reason a query is
  rejected rather than just `valid: false`.

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec validate_query(query(), keyword()) :: result()
  def validate_query(%{} = query, opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    index
    |> Helpers.path("/_validate/query")
    |> Client.post(query, Helpers.put_idempotent(opts, true))
    |> Helpers.parse_result()
  end

  @doc """
  Like `validate_query/2`, but returns the body directly or raises the error
  exception.
  """
  @spec validate_query!(query(), keyword()) :: body()
  def validate_query!(%{} = query, opts \\ []) do
    query |> validate_query(opts) |> Dowser.unwrap()
  end

  ## Public functions — templates

  @doc """
  Runs a search with a stored or inline search template
  ([Search template API](https://docs.opensearch.org/latest/api-reference/search-template/)).

  `template` is the request body, e.g. `%{id: "my-template", params: %{...}}`
  or `%{source: %{...}, params: %{...}}`.

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec search_template(map(), keyword()) :: result()
  def search_template(%{} = template, opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    index
    |> Helpers.path("/_search/template")
    |> Client.post(template, Helpers.put_idempotent(opts, true))
    |> Helpers.parse_result()
  end

  @doc """
  Like `search_template/2`, but returns the body directly or raises the error
  exception.
  """
  @spec search_template!(map(), keyword()) :: body()
  def search_template!(%{} = template, opts \\ []) do
    template |> search_template(opts) |> Dowser.unwrap()
  end

  @doc """
  Runs several template searches in one request
  ([Multi-search template API](https://docs.opensearch.org/latest/api-reference/search-template/)).

  `searches` is a flat list alternating header and template-body maps, encoded
  as NDJSON (see `msearch/2`).

  ## Options

    * `:index` — default index target for searches whose header has none.
  """
  @spec msearch_template([map()], keyword()) :: result()
  def msearch_template(searches, opts \\ []) when is_list(searches) do
    {index, opts} = Keyword.pop(opts, :index)
    opts = Helpers.put_default_format(opts, :req_format, :ndjson)

    index
    |> Helpers.path("/_msearch/template")
    |> Client.post(searches, Helpers.put_idempotent(opts, true))
    |> Helpers.parse_result()
  end

  @doc """
  Like `msearch_template/2`, but returns the body directly or raises the error
  exception.
  """
  @spec msearch_template!([map()], keyword()) :: body()
  def msearch_template!(searches, opts \\ []) do
    searches |> msearch_template(opts) |> Dowser.unwrap()
  end

  @doc """
  Renders a search template into the actual search body it would run
  ([Render search template API](https://docs.opensearch.org/latest/api-reference/search-template/)).

  `template` is the request body, typically `%{params: %{...}}` alongside an
  `id` or a `source`.

  ## Options

    * `:id` — the stored template to render, appended to the path. Omit it for
      an inline `source` given in the body.
  """
  @spec render_search_template(map(), keyword()) :: result()
  def render_search_template(%{} = template, opts \\ []) do
    {id, opts} = Keyword.pop(opts, :id)

    "/_render/template"
    |> Helpers.suffix_path(id)
    |> Client.post(template, Helpers.put_idempotent(opts, true))
    |> Helpers.parse_result()
  end

  @doc """
  Like `render_search_template/2`, but returns the body directly or raises the
  error exception.
  """
  @spec render_search_template!(map(), keyword()) :: body()
  def render_search_template!(%{} = template, opts \\ []) do
    template |> render_search_template(opts) |> Dowser.unwrap()
  end

  ## Public functions — scroll

  @doc """
  Fetches the next page of a scrolling search
  ([Scroll API](https://docs.opensearch.org/latest/api-reference/scroll/)).

  Sends `scroll_id` in the request body, the form OpenSearch recommends over
  the deprecated path parameter.

  ## Options

    * `:scroll` — how long to keep the scroll context alive, e.g. `"1m"`;
      merged into the body.
  """
  @spec scroll(id(), keyword()) :: result()
  def scroll(scroll_id, opts \\ []) do
    {keep_alive, opts} = Keyword.pop(opts, :scroll)

    body =
      if keep_alive do
        %{scroll_id: scroll_id, scroll: keep_alive}
      else
        %{scroll_id: scroll_id}
      end

    "/_search/scroll"
    |> Client.post(body, Helpers.put_idempotent(opts, true))
    |> Helpers.parse_result()
  end

  @doc """
  Like `scroll/2`, but returns the body directly or raises the error exception.
  """
  @spec scroll!(id(), keyword()) :: body()
  def scroll!(scroll_id, opts \\ []) do
    scroll_id |> scroll(opts) |> Dowser.unwrap()
  end

  @doc """
  Releases one or several scroll contexts
  ([Clear scroll API](https://docs.opensearch.org/latest/api-reference/scroll/)).

  `scroll_id` is a scroll id, a list of scroll ids, or `"_all"`.
  """
  @spec clear_scroll(scroll_id(), keyword()) :: result()
  def clear_scroll(scroll_id, opts \\ []) do
    "/_search/scroll"
    |> Client.delete(%{scroll_id: scroll_id}, opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `clear_scroll/2`, but returns the body directly or raises the error
  exception.
  """
  @spec clear_scroll!(scroll_id(), keyword()) :: body()
  def clear_scroll!(scroll_id, opts \\ []) do
    scroll_id |> clear_scroll(opts) |> Dowser.unwrap()
  end

  ## Public functions — point in time

  @doc """
  Creates a point in time over `index`, to search a fixed view of the data
  ([Create PIT API](https://docs.opensearch.org/latest/api-reference/search-apis/point-in-time-api/)).

  `keep_alive` is how long the point in time is kept alive, e.g. `"1m"`; it is
  sent as the required `keep_alive` query-string parameter. The endpoint takes
  no request body.

  Note that this is not Elasticsearch's `/_pit`: OpenSearch serves the whole
  point-in-time API under `/_search/point_in_time`, and the id it returns is
  named `pit_id` rather than `id`.

      {:ok, %{"pit_id" => pit_id}} =
        Dowser.Opensearch.Search.create_pit("posts", "5m")

      Dowser.Opensearch.Search.search!(%{pit: %{id: pit_id}})
  """
  @spec create_pit(index(), String.t(), keyword()) :: result()
  def create_pit(index, keep_alive, opts \\ []) do
    opts = Helpers.put_param(opts, :keep_alive, keep_alive)

    with {:ok, path} <- Helpers.required_path(index, "/_search/point_in_time") do
      path
      |> Client.post(nil, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `create_pit/3`, but returns the body directly or raises the error
  exception.
  """
  @spec create_pit!(index(), String.t(), keyword()) :: body()
  def create_pit!(index, keep_alive, opts \\ []) do
    index |> create_pit(keep_alive, opts) |> Dowser.unwrap()
  end

  @doc """
  Deletes one or several points in time
  ([Delete PIT API](https://docs.opensearch.org/latest/api-reference/search-apis/point-in-time-api/)).

  `pit_id` is one id or a list of them; a single id is wrapped, since
  OpenSearch requires the body's `pit_id` to be an array.
  """
  @spec delete_pit(pit_id(), keyword()) :: result()
  def delete_pit(pit_id, opts \\ []) do
    "/_search/point_in_time"
    |> Client.delete(%{pit_id: List.wrap(pit_id)}, opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `delete_pit/2`, but returns the body directly or raises the error
  exception.
  """
  @spec delete_pit!(pit_id(), keyword()) :: body()
  def delete_pit!(pit_id, opts \\ []) do
    pit_id |> delete_pit(opts) |> Dowser.unwrap()
  end

  @doc """
  Deletes every point in time
  ([Delete all PITs API](https://docs.opensearch.org/latest/api-reference/search-apis/point-in-time-api/)).
  """
  @spec delete_all_pits(keyword()) :: result()
  def delete_all_pits(opts \\ []) do
    "/_search/point_in_time/_all"
    |> Client.delete(nil, opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `delete_all_pits/1`, but returns the body directly or raises the error
  exception.
  """
  @spec delete_all_pits!(keyword()) :: body()
  def delete_all_pits!(opts \\ []) do
    opts |> delete_all_pits() |> Dowser.unwrap()
  end

  @doc """
  Lists every point in time currently open
  ([List all PITs API](https://docs.opensearch.org/latest/api-reference/search-apis/point-in-time-api/)).
  """
  @spec get_all_pits(keyword()) :: result()
  def get_all_pits(opts \\ []) do
    "/_search/point_in_time/_all"
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `get_all_pits/1`, but returns the body directly or raises the error
  exception.
  """
  @spec get_all_pits!(keyword()) :: body()
  def get_all_pits!(opts \\ []) do
    opts |> get_all_pits() |> Dowser.unwrap()
  end

  ## Repository metadata

  # Index-related functions exposed to `Dowser.Opensearch.Repository`:
  # `{index_spec, arity, kind}` where index_spec is :opts (`:index` option) or
  # {:pos, n} (positional index argument), and kind selects the variants
  # (:pair for `!`, :predicate for `?`).
  @doc false
  def __repository__ do
    [
      search: {:opts, 2, :pair},
      msearch: {:opts, 2, :pair},
      count: {:opts, 2, :pair},
      explain: {{:pos, 1}, 4, :pair},
      field_caps: {:opts, 2, :pair},
      search_shards: {:opts, 1, :pair},
      validate_query: {:opts, 2, :pair},
      search_template: {:opts, 2, :pair},
      msearch_template: {:opts, 2, :pair},
      create_pit: {{:pos, 0}, 3, :pair}
    ]
  end
end
