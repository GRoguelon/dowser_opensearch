defmodule Dowser.Opensearch.DataStream do
  @moduledoc """
  The OpenSearch data stream APIs — every endpoint tagged `Data Streams` in the
  [OpenSearch OpenAPI specification](https://github.com/opensearch-project/opensearch-api-specification).

  Built on `Dowser.Client`. Required OpenSearch attributes are positional
  arguments; everything optional lives in `opts`.

  A data stream is an append-only, time-series abstraction over a set of hidden
  backing indices. Creating one needs a matching index template with a
  `data_stream` section already in place — see
  `Dowser.Opensearch.IndexTemplate.put_index_template/3` — because the template
  is what tells OpenSearch how to build the backing indices. Rolling a stream
  over to a fresh backing index is `Dowser.Opensearch.Index.rollover/3`.

  ## Shared conventions

    * A stream `name` is a required path parameter where an endpoint takes one,
      and may be several names (joined with `,`) or a wildcard on the reads.
    * `modify/2` takes its action list as the first argument.

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

  @type name :: Target.name()
  @type body :: term()
  @type result :: {:ok, body()} | {:error, Exception.t()}

  ## Public functions

  @doc """
  Creates the data stream `name`
  ([Create data stream API](https://docs.opensearch.org/latest/api-reference/data-stream/create-data-stream/)).

  The endpoint takes no request body: everything about the stream comes from
  the index template whose `index_patterns` match `name`, so that template has
  to exist first.
  """
  @spec create_data_stream(name(), keyword()) :: result()
  def create_data_stream(name, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(name, "name") do
      ("/_data_stream/" <> segment)
      |> Client.put(nil, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `create_data_stream/2`, but returns the body directly or raises the
  error exception.
  """
  @spec create_data_stream!(name(), keyword()) :: body()
  def create_data_stream!(name, opts \\ []) do
    name |> create_data_stream(opts) |> Dowser.unwrap()
  end

  @doc """
  Returns one, several, or all data streams
  ([Get data stream API](https://docs.opensearch.org/latest/api-reference/data-stream/get-data-stream/)).

  ## Options

    * `:name` — restrict the result to one or several stream names, which may
      include wildcards; absent for all of them.
  """
  @spec get_data_stream(keyword()) :: result()
  def get_data_stream(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    with {:ok, path} <- optional_suffix("/_data_stream", name, "name") do
      path
      |> Client.get(opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `get_data_stream/1`, but returns the body directly or raises the error
  exception.
  """
  @spec get_data_stream!(keyword()) :: body()
  def get_data_stream!(opts \\ []) do
    opts |> get_data_stream() |> Dowser.unwrap()
  end

  @doc """
  Deletes one or several data streams, and their backing indices with them
  ([Delete data stream API](https://docs.opensearch.org/latest/api-reference/data-stream/delete-data-stream/)).
  """
  @spec delete_data_stream(name(), keyword()) :: result()
  def delete_data_stream(name, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(name, "name") do
      ("/_data_stream/" <> segment)
      |> Client.delete(nil, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `delete_data_stream/2`, but returns the body directly or raises the
  error exception.
  """
  @spec delete_data_stream!(name(), keyword()) :: body()
  def delete_data_stream!(name, opts \\ []) do
    name |> delete_data_stream(opts) |> Dowser.unwrap()
  end

  @doc """
  Returns statistics for one, several, or all data streams
  ([Data stream stats API](https://docs.opensearch.org/latest/api-reference/data-stream/data-stream-stats/)).

  ## Options

    * `:name` — restrict the result to one or several stream names; absent for
      all of them.
  """
  @spec data_streams_stats(keyword()) :: result()
  def data_streams_stats(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    with {:ok, base} <- optional_suffix("/_data_stream", name, "name") do
      (base <> "/_stats")
      |> Client.get(opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `data_streams_stats/1`, but returns the body directly or raises the
  error exception.
  """
  @spec data_streams_stats!(keyword()) :: body()
  def data_streams_stats!(opts \\ []) do
    opts |> data_streams_stats() |> Dowser.unwrap()
  end

  @doc """
  Changes which backing indices belong to which data streams
  ([Modify data streams API](https://docs.opensearch.org/latest/api-reference/data-stream/)).

  `actions` is the list of actions, sent as `%{actions: actions}` and applied
  atomically, so a backing index never belongs to two streams or to none in
  between:

      Dowser.Opensearch.DataStream.modify([
        %{remove_backing_index: %{data_stream: "logs", index: ".ds-logs-000001"}},
        %{add_backing_index: %{data_stream: "logs-archive", index: ".ds-logs-000001"}}
      ])
  """
  @spec modify([map()], keyword()) :: result()
  def modify(actions, opts \\ []) when is_list(actions) do
    "/_data_stream/_modify"
    |> Client.post(%{actions: actions}, opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `modify/2`, but returns the body directly or raises the error exception.
  """
  @spec modify!([map()], keyword()) :: body()
  def modify!(actions, opts \\ []) do
    actions |> modify(opts) |> Dowser.unwrap()
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
end
