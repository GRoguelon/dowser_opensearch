defmodule Dowser.Opensearch.Document do
  @moduledoc """
  The OpenSearch document APIs — the endpoints tagged `Document` in the
  [OpenSearch OpenAPI specification](https://github.com/opensearch-project/opensearch-api-specification)
  (single-document CRUD, bulk, multi-get, term vectors).

  Built on `Dowser.Client`. Required OpenSearch attributes are positional
  arguments; everything optional lives in `opts`.

  Note that the by-query operations live in `Dowser.Opensearch.Reindex`, not
  here: OpenSearch tags `_delete_by_query`, `_update_by_query` and `_reindex`
  as `Reindex`, where Elasticsearch groups them with the document APIs.

  ## Shared conventions

    * Endpoints that accept a request body take it as their first argument,
      required — pass `%{}` to send nothing. The argument is named `query`
      when the body is an OpenSearch query DSL document, and `body` (or a
      more specific name such as `document` or `operations`) otherwise.
    * `:index` — optional index target where the endpoint accepts one;
      endpoints that require an index take it as an argument.
    * `HEAD` existence checks come as a pair where the `?` variant plays the
      bang role: `exists/3` returns `{:ok, boolean()}` or
      `{:error, exception}`, `exists?/3` returns the bare boolean
      (`404` → `false`) and raises on genuine errors.

  All remaining options are forwarded to `Dowser.Client.request/4`, e.g.
  `:context`, `:params` (query-string parameters), `:format`, `:keys` and
  `:http_opts` (including `:headers`) — plus `:codec`, this package's own,
  which picks the per-field codec for this one request (see
  `Dowser.Opensearch.Codec`).

  Values are cast automatically wherever `Dowser.Opensearch.Codec` is
  configured as `:decoder`/`:encoder` — no per-call option needed. A response
  carries each document's own `_index`, so reads need telling nothing; the
  writing functions name the index each source is going to and where in the
  request body it sits, which is the mapping the encoder needs.

  On a 2xx response every function returns `{:ok, body}` with the decoded
  response body. A non-2xx response returns
  `{:error, %Dowser.Opensearch.Error{}}`; a transport, encoding or decoding
  failure returns `{:error, exception}` from `Dowser.Client`. A required
  argument that is missing or empty is reported the same way, before any
  request is made: `{:error, %ArgumentError{}}`. Each function has a bang
  variant that returns the body directly or raises the error exception.
  """

  alias Dowser.Opensearch.Bulk
  alias Dowser.Opensearch.Client
  alias Dowser.Opensearch.Codec
  alias Dowser.Opensearch.Helpers
  alias Dowser.Opensearch.Target

  ## Module attributes

  # Where `update/4`'s body carries a document source, in both key styles — a
  # path that isn't there is skipped rather than created, so listing all four
  # costs nothing and a `%{script: ...}` body is left alone.
  @update_sources [["doc"], [:doc], ["upsert"], [:upsert]]

  ## Typespecs

  @type index :: Target.t()
  @type id :: String.t()
  @type body :: term()
  @type result :: {:ok, body()} | {:error, Exception.t()}
  @type exists_result :: {:ok, boolean()} | {:error, Exception.t()}

  ## Public functions — single documents

  @doc """
  Indexes (creates or replaces) a document
  ([Index document API](https://docs.opensearch.org/latest/api-reference/document-apis/index-document/)).

  `document` is the document body.

  ## Options

    * `:id` — document id; absent to let OpenSearch generate one.
  """
  @spec index(map(), index(), keyword()) :: result()
  def index(%{} = document, index, opts \\ []) do
    {id, opts} = Keyword.pop(opts, :id)
    opts = Client.put_encoder(opts, [index: index], true)

    suffix =
      if id do
        "/_doc/" <> URI.encode(id)
      else
        "/_doc"
      end

    # Indexing at an id the caller chose is a replace, so re-sending it after
    # an ambiguous failure changes nothing. Letting OpenSearch generate the id
    # makes every attempt a new document.
    opts = Helpers.put_idempotent(opts, not is_nil(id))

    with {:ok, path} <- Helpers.required_path(index, suffix) do
      path
      |> Client.post(document, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `index/3`, but returns the body directly or raises the error exception.
  """
  @spec index!(map(), index(), keyword()) :: body()
  def index!(%{} = document, index, opts \\ []) do
    document |> index(index, opts) |> Dowser.unwrap()
  end

  @doc """
  Creates the document `id`, failing if it already exists
  ([Create document API](https://docs.opensearch.org/latest/api-reference/document-apis/index-document/)).

  `document` is the document body.
  """
  @spec create(map(), index(), id(), keyword()) :: result()
  def create(%{} = document, index, id, opts \\ []) do
    opts = Client.put_encoder(opts, [index: index], true)

    with {:ok, path} <- Helpers.required_path(index, "/_create/" <> URI.encode(id)) do
      path
      |> Client.post(document, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `create/4`, but returns the body directly or raises the error exception.
  """
  @spec create!(map(), index(), id(), keyword()) :: body()
  def create!(%{} = document, index, id, opts \\ []) do
    document |> create(index, id, opts) |> Dowser.unwrap()
  end

  @doc """
  Retrieves the document `id`
  ([Get document API](https://docs.opensearch.org/latest/api-reference/document-apis/get-documents/)).
  """
  @spec get(index(), id(), keyword()) :: result()
  def get(index, id, opts \\ []) do
    with {:ok, path} <- Helpers.required_path(index, "/_doc/" <> URI.encode(id)) do
      path
      |> Client.get(opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `get/3`, but returns the body directly or raises the error exception.
  """
  @spec get!(index(), id(), keyword()) :: body()
  def get!(index, id, opts \\ []) do
    index |> get(id, opts) |> Dowser.unwrap()
  end

  @doc """
  Deletes the document `id`
  ([Delete document API](https://docs.opensearch.org/latest/api-reference/document-apis/delete-document/)).
  """
  @spec delete(index(), id(), keyword()) :: result()
  def delete(index, id, opts \\ []) do
    with {:ok, path} <- Helpers.required_path(index, "/_doc/" <> URI.encode(id)) do
      path
      |> Client.delete(nil, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `delete/3`, but returns the body directly or raises the error exception.
  """
  @spec delete!(index(), id(), keyword()) :: body()
  def delete!(index, id, opts \\ []) do
    index |> delete(id, opts) |> Dowser.unwrap()
  end

  @doc """
  Checks whether the document `id` exists
  ([Document exists API](https://docs.opensearch.org/latest/api-reference/document-apis/get-documents/)).

  Returns `{:ok, true}`, `{:ok, false}` or `{:error, exception}`.
  """
  @spec exists(index(), id(), keyword()) :: exists_result()
  def exists(index, id, opts \\ []) do
    with {:ok, path} <- Helpers.required_path(index, "/_doc/" <> URI.encode(id)) do
      path
      |> head(opts)
    end
  end

  @doc """
  Like `exists/3`, but returns the boolean directly (`404` → `false`) or
  raises the error exception.
  """
  @spec exists?(index(), id(), keyword()) :: boolean()
  def exists?(index, id, opts \\ []) do
    index |> exists(id, opts) |> Dowser.unwrap()
  end

  @doc """
  Retrieves the source of the document `id`, without metadata
  ([Get document source API](https://docs.opensearch.org/latest/api-reference/document-apis/get-documents/)).
  """
  @spec get_source(index(), id(), keyword()) :: result()
  def get_source(index, id, opts \\ []) do
    opts = Client.put_decoder(opts, index: index, source: true)

    with {:ok, path} <- Helpers.required_path(index, "/_source/" <> URI.encode(id)) do
      path
      |> Client.get(opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `get_source/3`, but returns the body directly or raises the error
  exception.
  """
  @spec get_source!(index(), id(), keyword()) :: body()
  def get_source!(index, id, opts \\ []) do
    index |> get_source(id, opts) |> Dowser.unwrap()
  end

  @doc """
  Checks whether the document `id` exists and has a source
  ([Source exists API](https://docs.opensearch.org/latest/api-reference/document-apis/get-documents/)).

  Returns `{:ok, true}`, `{:ok, false}` or `{:error, exception}`.
  """
  @spec source_exists(index(), id(), keyword()) :: exists_result()
  def source_exists(index, id, opts \\ []) do
    with {:ok, path} <- Helpers.required_path(index, "/_source/" <> URI.encode(id)) do
      path
      |> head(opts)
    end
  end

  @doc """
  Like `source_exists/3`, but returns the boolean directly (`404` → `false`)
  or raises the error exception.
  """
  @spec source_exists?(index(), id(), keyword()) :: boolean()
  def source_exists?(index, id, opts \\ []) do
    index |> source_exists(id, opts) |> Dowser.unwrap()
  end

  @doc """
  Updates the document `id` with a script or a partial document
  ([Update document API](https://docs.opensearch.org/latest/api-reference/document-apis/update-document/)).

  `body` is the update body, e.g. `%{doc: %{title: "hi"}}` or
  `%{script: %{...}}`.
  """
  @spec update(map(), index(), id(), keyword()) :: result()
  def update(%{} = body, index, id, opts \\ []) do
    opts = Client.put_encoder(opts, [index: index], @update_sources)

    with {:ok, path} <- Helpers.required_path(index, "/_update/" <> URI.encode(id)) do
      path
      |> Client.post(body, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `update/4`, but returns the body directly or raises the error exception.
  """
  @spec update!(map(), index(), id(), keyword()) :: body()
  def update!(%{} = body, index, id, opts \\ []) do
    body |> update(index, id, opts) |> Dowser.unwrap()
  end

  ## Public functions — multi-document

  @doc """
  Performs several index/create/update/delete operations in one request
  ([Bulk API](https://docs.opensearch.org/latest/api-reference/document-apis/bulk/)).

  `operations` is a flat list alternating action and payload maps, encoded as
  NDJSON:

      Dowser.Opensearch.Document.bulk([
        %{index: %{_id: "1"}},
        %{title: "hello"},
        %{delete: %{_id: "2"}}
      ])

  ## Options

    * `:index` — default index target for actions that name none.

  ## Per-item failures

  A bulk request is not all-or-nothing. OpenSearch answers `200 OK` with
  `"errors" => true` and an `items` entry per action, so a request whose
  documents were half rejected — a per-item `429` under load, a mapping
  failure — looks like a successful one at the HTTP level.

  So `{:ok, body}` here means *every* item was applied. As soon as one failed,
  the result is `{:error, %Dowser.Opensearch.BulkError{}}`, which reports what
  failed, what succeeded, and which operations are worth resubmitting:

      {:error, %BulkError{failed: failed, succeeded: 488, retryable: operations}} =
        Dowser.Opensearch.Document.bulk(operations, index: "posts")

  Only the rejected items (`429`/`503`) are listed in `:retryable`;
  resubmitting those writes nothing twice, where resending the whole payload
  would index the successful items a second time.
  """
  @spec bulk([map()], keyword()) :: result()
  def bulk(operations, opts \\ []) when is_list(operations) do
    {index, opts} = Keyword.pop(opts, :index)

    # The payloads are cast here rather than by `Dowser.Client`, so a
    # request-level `:codec` has to be folded in before the encoder is
    # resolved — `Client.post/3` would do it too late.
    opts =
      opts
      |> Client.put_codec()
      |> Helpers.put_default_format(:req_format, :ndjson)
      |> Helpers.put_idempotent(Bulk.idempotent?(operations))

    index
    |> Helpers.path("/_bulk")
    |> Client.post(encode_bulk(operations, index, opts), opts)
    |> Helpers.parse_result()
    |> Bulk.check(operations)
  end

  @doc """
  Like `bulk/2`, but returns the body directly or raises the error exception —
  including the `Dowser.Opensearch.BulkError` a partial failure returns, so it
  raises unless every item was applied.
  """
  @spec bulk!([map()], keyword()) :: body()
  def bulk!(operations, opts \\ []) do
    operations |> bulk(opts) |> Dowser.unwrap()
  end

  @doc """
  Retrieves several documents in one request
  ([Multi-get API](https://docs.opensearch.org/latest/api-reference/document-apis/multi-get/)).

  `body` is the request body, e.g. `%{ids: ["1", "2"]}` or `%{docs: [...]}`.

  ## Options

    * `:index` — index target; absent when each doc names its own.
  """
  @spec mget(map(), keyword()) :: result()
  def mget(%{} = body, opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    index
    |> Helpers.path("/_mget")
    |> Client.post(body, Helpers.put_idempotent(opts, true))
    |> Helpers.parse_result()
  end

  @doc """
  Like `mget/2`, but returns the body directly or raises the error exception.
  """
  @spec mget!(map(), keyword()) :: body()
  def mget!(%{} = body, opts \\ []) do
    body |> mget(opts) |> Dowser.unwrap()
  end

  ## Public functions — term vectors

  @doc """
  Returns term and field statistics for a stored or artificial document
  ([Term vectors API](https://docs.opensearch.org/latest/api-reference/document-apis/term-vectors/)).

  `body` is the request body (e.g. `doc`, `fields`, `filter`); pass `%{}` to
  send nothing.

  ## Options

    * `:id` — stored document id; absent when analyzing a `doc` from the body.
  """
  @spec termvectors(map(), index(), keyword()) :: result()
  def termvectors(%{} = body, index, opts \\ []) do
    {id, opts} = Keyword.pop(opts, :id)

    suffix =
      if id do
        "/_termvectors/" <> URI.encode(id)
      else
        "/_termvectors"
      end

    with {:ok, path} <- Helpers.required_path(index, suffix) do
      path
      |> Client.post(body, Helpers.put_idempotent(opts, true))
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `termvectors/3`, but returns the body directly or raises the error
  exception.
  """
  @spec termvectors!(map(), index(), keyword()) :: body()
  def termvectors!(%{} = body, index, opts \\ []) do
    body |> termvectors(index, opts) |> Dowser.unwrap()
  end

  @doc """
  Returns term vectors for several documents in one request
  ([Multi term vectors API](https://docs.opensearch.org/latest/api-reference/document-apis/term-vectors/)).

  `body` is the request body, e.g. `%{docs: [...]}` or `%{ids: [...]}`.

  ## Options

    * `:index` — index target; absent when each doc names its own.
  """
  @spec mtermvectors(map(), keyword()) :: result()
  def mtermvectors(%{} = body, opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    index
    |> Helpers.path("/_mtermvectors")
    |> Client.post(body, Helpers.put_idempotent(opts, true))
    |> Helpers.parse_result()
  end

  @doc """
  Like `mtermvectors/2`, but returns the body directly or raises the error
  exception.
  """
  @spec mtermvectors!(map(), keyword()) :: body()
  def mtermvectors!(%{} = body, opts \\ []) do
    body |> mtermvectors(opts) |> Dowser.unwrap()
  end

  ## Repository metadata

  # Index-related functions exposed to `Dowser.Opensearch.Repository`:
  # `{index_spec, arity, kind}` where index_spec is :opts (`:index` option) or
  # {:pos, n} (positional index argument), and kind selects the variants
  # (:pair for `!`, :predicate for `?`).
  @doc false
  def __repository__ do
    [
      index: {{:pos, 1}, 3, :pair},
      create: {{:pos, 1}, 4, :pair},
      get: {{:pos, 0}, 3, :pair},
      delete: {{:pos, 0}, 3, :pair},
      exists: {{:pos, 0}, 3, :predicate},
      get_source: {{:pos, 0}, 3, :pair},
      source_exists: {{:pos, 0}, 3, :predicate},
      update: {{:pos, 1}, 4, :pair},
      bulk: {:opts, 2, :pair},
      mget: {:opts, 2, :pair},
      termvectors: {{:pos, 1}, 3, :pair},
      mtermvectors: {:opts, 2, :pair}
    ]
  end

  ## Private functions

  # A bulk payload is cast against the index named on the action line above it,
  # which `Dowser.Client`'s per-line `:encode` can't see — so the whole list is
  # walked here instead, and `:encode` is left off.
  @spec encode_bulk([map()], index() | nil, keyword()) :: [map()]
  defp encode_bulk(operations, index, opts) do
    case Client.resolve_encoder(opts) do
      nil ->
        operations

      {fun, encoder_opts} ->
        Codec.encode_bulk(operations, fun, Keyword.put_new(encoder_opts, :index, index))
    end
  end

  # HEAD responses have no body, so the response format defaults to :raw.
  @spec head(String.t(), keyword()) :: exists_result()
  defp head(path, opts) do
    opts = Helpers.put_default_format(opts, :resp_format, :raw)

    :head
    |> Client.request(path, nil, opts)
    |> Helpers.parse_exists()
  end
end
