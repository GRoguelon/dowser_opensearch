defmodule Dowser.Opensearch.List do
  @moduledoc """
  The OpenSearch list APIs — every endpoint tagged `List` in the
  [OpenSearch OpenAPI specification](https://github.com/opensearch-project/opensearch-api-specification).

  Built on `Dowser.Client`. These endpoints take no request body and no
  required attribute: each one's optional path parameter is an option, so every
  function has the same `opts`-only signature.

  ## How this differs from CAT

  These are OpenSearch's own addition, and have no Elasticsearch counterpart.
  They answer the same questions as `Dowser.Opensearch.Cat.indices/1` and
  `Dowser.Opensearch.Cat.shards/1`, but **paginated**: on a cluster with
  thousands of indices, the cat endpoints build the whole table in the
  coordinating node's heap before sending it, while these return one page and a
  `next_token` for the following one.

  Prefer these where the number of indices or shards is large or unbounded, and
  CAT where you know it is small and want the single-response simplicity.

  ## Paging

  A response carries `next_token` until the last page, which returns it as
  `null`. Feed it back through `params: [next_token: token]`:

      def all_indices(token \\\\ nil, acc \\\\ []) do
        params = if token, do: [next_token: token], else: []
        page = Dowser.Opensearch.List.indices!(params: params ++ [size: 100])

        case page["next_token"] do
          nil -> acc ++ page["indices"]
          next -> all_indices(next, acc ++ page["indices"])
        end
      end

  ## Shared options

  Passed through `:params`:

    * `size` — how many rows per page.
    * `next_token` — the page to continue from, as above.
    * `v` — add the column headers.
    * `h` — the columns to return, e.g. `h: "index,docs.count"`.
    * `s` — the columns to sort on, e.g. `s: "docs.count:desc"`.
    * `bytes` / `time` — the unit sizes and durations are expressed in.
    * `format` — see below.

  Like the cat APIs, these are meant for humans at a terminal and answer in
  aligned text by default, but honour the `accept` header `Dowser.Client`
  sends, so the response comes back as JSON. For the aligned text, ask for it
  explicitly — the `format` query parameter wins over the header, and
  `resp_format: :raw` keeps the body from being parsed:

      Dowser.Opensearch.List.indices!(params: [format: "text", v: true], resp_format: :raw)

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
  @type body :: term()
  @type result :: {:ok, body()} | {:error, Exception.t()}

  ## Public functions

  @doc """
  Lists the available list APIs — `GET /_list`
  ([List API](https://docs.opensearch.org/latest/api-reference/list/)).

  Like its cat counterpart, this endpoint answers in plain text whatever the
  `accept` header says — a banner line, then one endpoint per line — so the
  response format defaults to `:raw` and the body is parsed here into the list
  of endpoints:

      Dowser.Opensearch.List.help!()
      #=> ["/_list/indices", "/_list/indices/{index}", "/_list/shards", ...]

  Pass `resp_format: :json` (or `:ndjson`) to opt out of both the `:raw`
  default and the parsing, and get whatever `Dowser.Client` decodes instead.
  """
  @spec help(keyword()) :: {:ok, [String.t()]} | {:error, Exception.t()}
  def help(opts \\ []) do
    opts = Helpers.put_default_format(opts, :resp_format, :raw)

    "/_list"
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

  @doc """
  Returns a page of indices, with their health, status and document counts
  ([List indices API](https://docs.opensearch.org/latest/api-reference/list/list-indices/)).

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec indices(keyword()) :: result()
  def indices(opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    "/_list/indices"
    |> Helpers.suffix_path(index)
    |> Client.get(opts)
    |> Helpers.parse_result()
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
  Returns a page of shards, with their state, node and size
  ([List shards API](https://docs.opensearch.org/latest/api-reference/list/list-shards/)).

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec shards(keyword()) :: result()
  def shards(opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    "/_list/shards"
    |> Helpers.suffix_path(index)
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `shards/1`, but returns the body directly or raises the error exception.
  """
  @spec shards!(keyword()) :: body()
  def shards!(opts \\ []) do
    opts |> shards() |> Dowser.unwrap()
  end

  ## Repository metadata

  # Index-related functions exposed to `Dowser.Opensearch.Repository`:
  # `{index_spec, arity, kind}` where index_spec is :opts (`:index` option) or
  # {:pos, n} (positional index argument), and kind selects the variants
  # (:pair for `!`, :predicate for `?`).
  @doc false
  def __repository__ do
    [
      indices: {:opts, 1, :pair},
      shards: {:opts, 1, :pair}
    ]
  end

  ## Private functions

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
