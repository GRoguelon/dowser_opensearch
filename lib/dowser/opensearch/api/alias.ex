defmodule Dowser.Opensearch.Alias do
  @moduledoc """
  The OpenSearch alias APIs — the endpoints tagged `Aliases` in the
  [OpenSearch OpenAPI specification](https://github.com/opensearch-project/opensearch-api-specification).

  Built on `Dowser.Client`. Required OpenSearch attributes are positional
  arguments; everything optional lives in `opts`.

  OpenSearch tags these separately from the index APIs, so they live here
  rather than on `Dowser.Opensearch.Index`; the index-target helper they share
  is `Dowser.Opensearch.Target`.

  OpenSearch serves the single-alias endpoints under both `_alias` and
  `_aliases`; these functions use the singular `_alias`, which is the form its
  documentation gives. `update_aliases/2` is the separate `POST /_aliases`
  endpoint, whose plural is not interchangeable.

  ## Shared conventions

    * An *index target* may be `nil` (all indices), a single index/alias/
      data-stream name (string or atom), or a list of them (joined with `,`).
      The write endpoints require one and take it as an argument; the reads
      take it as the `:index` option.
    * Endpoints that accept a request body take it as their first argument,
      required — pass `%{}` to send nothing.
    * `HEAD` existence checks come as a pair where the `?` variant plays the
      bang role: `alias_exists/2` returns `{:ok, boolean()}` or
      `{:error, exception}`, `alias_exists?/2` returns the bare boolean
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

  @type index :: Target.t()
  @type name :: Target.name()
  @type body :: term()
  @type result :: {:ok, body()} | {:error, Exception.t()}
  @type exists_result :: {:ok, boolean()} | {:error, Exception.t()}

  ## Public functions

  @doc """
  Applies several alias actions atomically
  ([Alias API](https://docs.opensearch.org/latest/api-reference/index-apis/alias/)).

  `actions` is the list of actions, sent as `%{actions: actions}`.

  This is the endpoint to use when moving an alias: OpenSearch applies the
  whole list as one atomic step, so a remove-then-add pair never leaves the
  alias pointing at nothing in between.

      Dowser.Opensearch.Alias.update_aliases([
        %{remove: %{index: "posts-v1", alias: "posts"}},
        %{add: %{index: "posts-v2", alias: "posts"}}
      ])
  """
  @spec update_aliases([map()], keyword()) :: result()
  def update_aliases(actions, opts \\ []) when is_list(actions) do
    "/_aliases"
    |> Client.post(%{actions: actions}, opts)
    |> Helpers.parse_result()
  end

  @doc """
  Like `update_aliases/2`, but returns the body directly or raises the error
  exception.
  """
  @spec update_aliases!([map()], keyword()) :: body()
  def update_aliases!(actions, opts \\ []) do
    actions |> update_aliases(opts) |> Dowser.unwrap()
  end

  @doc """
  Creates or updates the alias `name` on one or several indices
  ([Create or update alias API](https://docs.opensearch.org/latest/api-reference/index-apis/alias/)).

  `body` is the request body (e.g. `filter`, `routing`, `is_write_index`); pass
  `%{}` to send nothing.
  """
  @spec put_alias(map(), index(), name(), keyword()) :: result()
  def put_alias(%{} = body, index, name, opts \\ []) do
    with {:ok, name_segment} <- Helpers.required_segment(name, "name"),
         {:ok, path} <- Helpers.required_path(index, "/_alias/" <> name_segment) do
      path
      |> Client.put(body, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `put_alias/4`, but returns the body directly or raises the error
  exception.
  """
  @spec put_alias!(map(), index(), name(), keyword()) :: body()
  def put_alias!(%{} = body, index, name, opts \\ []) do
    body |> put_alias(index, name, opts) |> Dowser.unwrap()
  end

  @doc """
  Deletes the alias `name` from one or several indices
  ([Delete alias API](https://docs.opensearch.org/latest/api-reference/index-apis/delete-alias/)).
  """
  @spec delete_alias(index(), name(), keyword()) :: result()
  def delete_alias(index, name, opts \\ []) do
    with {:ok, name_segment} <- Helpers.required_segment(name, "name"),
         {:ok, path} <- Helpers.required_path(index, "/_alias/" <> name_segment) do
      path
      |> Client.delete(nil, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `delete_alias/3`, but returns the body directly or raises the error
  exception.
  """
  @spec delete_alias!(index(), name(), keyword()) :: body()
  def delete_alias!(index, name, opts \\ []) do
    index |> delete_alias(name, opts) |> Dowser.unwrap()
  end

  @doc """
  Returns one, several, or all aliases
  ([Get alias API](https://docs.opensearch.org/latest/api-reference/index-apis/alias/)).

  ## Options

    * `:index` — index target; absent for all indices.
    * `:name` — restrict the result to one or several alias names, which may
      include wildcards.
  """
  @spec get_alias(keyword()) :: result()
  def get_alias(opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)
    {name, opts} = Keyword.pop(opts, :name)

    with {:ok, suffix} <- optional_suffix("/_alias", name, "name") do
      index
      |> Helpers.path(suffix)
      |> Client.get(opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `get_alias/1`, but returns the body directly or raises the error
  exception.
  """
  @spec get_alias!(keyword()) :: body()
  def get_alias!(opts \\ []) do
    opts |> get_alias() |> Dowser.unwrap()
  end

  @doc """
  Checks whether one or several aliases exist
  ([Alias exists API](https://docs.opensearch.org/latest/api-reference/index-apis/alias-exists/)).

  Returns `{:ok, true}`, `{:ok, false}` or `{:error, exception}`.

  ## Options

    * `:index` — index target; absent for all indices.
  """
  @spec alias_exists(name(), keyword()) :: exists_result()
  def alias_exists(name, opts \\ []) do
    {index, opts} = Keyword.pop(opts, :index)

    with {:ok, name_segment} <- Helpers.required_segment(name, "name") do
      opts = Helpers.put_default_format(opts, :resp_format, :raw)

      :head
      |> Client.request(Helpers.path(index, "/_alias/" <> name_segment), nil, opts)
      |> Helpers.parse_exists()
    end
  end

  @doc """
  Like `alias_exists/2`, but returns the boolean directly (`404` → `false`) or
  raises the error exception.
  """
  @spec alias_exists?(name(), keyword()) :: boolean()
  def alias_exists?(name, opts \\ []) do
    name |> alias_exists(opts) |> Dowser.unwrap()
  end

  ## Repository metadata

  # Index-related functions exposed to `Dowser.Opensearch.Repository`:
  # `{index_spec, arity, kind}` where index_spec is :opts (`:index` option) or
  # {:pos, n} (positional index argument), and kind selects the variants
  # (:pair for `!`, :predicate for `?`).
  #
  # `update_aliases/2` names its indices inside each action rather than in the
  # path, so it cannot be bound to a repository's index.
  @doc false
  def __repository__ do
    [
      put_alias: {{:pos, 1}, 4, :pair},
      delete_alias: {{:pos, 0}, 3, :pair},
      get_alias: {:opts, 1, :pair},
      alias_exists: {:opts, 2, :predicate}
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
end
