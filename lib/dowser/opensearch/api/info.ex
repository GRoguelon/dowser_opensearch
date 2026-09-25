defmodule Dowser.Opensearch.Info do
  @moduledoc """
  The OpenSearch cluster info API — the endpoints tagged `Info` in the
  [OpenSearch OpenAPI specification](https://github.com/opensearch-project/opensearch-api-specification).

  Built on `Dowser.Client`. Neither endpoint takes an OpenSearch attribute at
  all, so both functions only carry the transport options.

  All options are forwarded to `Dowser.Client.request/4`, e.g. `:context`,
  `:params` (query-string parameters), `:format`, `:keys` and `:http_opts`
  (including `:headers`) — plus `:codec`, this package's own, which picks the
  per-field codec for this one request (see `Dowser.Opensearch.Codec`).

  On a 2xx response `info/1` returns `{:ok, body}` with the decoded response
  body. A non-2xx response returns `{:error, %Dowser.Opensearch.Error{}}`; a
  transport, encoding or decoding failure returns `{:error, exception}` from
  `Dowser.Client`. The bang variant returns the body directly or raises the
  error exception.
  """

  alias Dowser.Opensearch.Client
  alias Dowser.Opensearch.Helpers

  ## Typespecs

  @type body :: term()
  @type result :: {:ok, body()} | {:error, Exception.t()}
  @type exists_result :: {:ok, boolean()} | {:error, Exception.t()}

  ## Public functions

  @doc """
  Gets the basic information about the cluster — `GET /`
  ([Cluster info API](https://docs.opensearch.org/latest/api-reference/index-apis/)).

  The response carries the node name, the cluster name and UUID, the
  distribution and version, and the tagline, which makes it the usual way to
  check that a cluster is reachable and to read its version:

      {:ok, info} = Dowser.Opensearch.Info.info()
      info["version"]["distribution"]
      #=> "opensearch"
      info["version"]["number"]
      #=> "2.13.0"

  A cluster running in Elasticsearch compatibility mode reports the
  Elasticsearch version it emulates under `version.number`, with the real one
  in `version.distribution`/`version.build_type` — so read `distribution`
  rather than `number` to tell the two apart.

  ## Options

  Only the transport options listed in the module documentation, e.g.
  `:context` to pick the cluster to query.
  """
  @spec info(keyword()) :: result()
  def info(opts \\ []) do
    "/"
    |> Client.get(opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `info/1`, but returns the body directly or raises the error exception.
  """
  @spec info!(keyword()) :: body()
  def info!(opts \\ []) do
    opts |> info() |> Dowser.unwrap()
  end

  @doc """
  Checks whether the cluster is up — `HEAD /`
  ([Ping API](https://docs.opensearch.org/latest/api-reference/index-apis/)).

  The body-less counterpart of `info/1`: it answers the liveness question
  without transferring or decoding the cluster metadata.

      Dowser.Opensearch.Info.ping?()
      #=> true

  Returns `{:ok, true}` on a 2xx and `{:ok, false}` on a `404`. Note that a
  cluster that cannot be reached at all is a transport failure, not a `false`:
  that comes back as `{:error, exception}`, since "answered no" and "did not
  answer" are different things.

  ## Options

  Only the transport options listed in the module documentation.
  """
  @spec ping(keyword()) :: exists_result()
  def ping(opts \\ []) do
    opts = Helpers.put_default_format(opts, :resp_format, :raw)

    :head
    |> Client.request("/", nil, opts)
    |> Helpers.parse_exists()
  end

  @doc """
  Like `ping/1`, but returns the boolean directly (`404` → `false`) or raises
  the error exception.
  """
  @spec ping?(keyword()) :: boolean()
  def ping?(opts \\ []) do
    opts |> ping() |> Dowser.unwrap()
  end
end
