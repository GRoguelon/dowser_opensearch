defmodule Dowser.Opensearch.IndexTemplate do
  @moduledoc """
  The OpenSearch index template APIs — the endpoints tagged `Index Templates` in
  the [OpenSearch OpenAPI specification](https://github.com/opensearch-project/opensearch-api-specification).

  Built on `Dowser.Client`. Required OpenSearch attributes are positional
  arguments; everything optional lives in `opts`.

  OpenSearch tags these separately from the index APIs, so they live here
  rather than on `Dowser.Opensearch.Index`.

  ## The three kinds of template

  The tag covers three families, and they are not interchangeable:

    * **Index templates** (`/_index_template`) — the composable kind, which can
      pull shared pieces in through `composed_of`. This is what to use.
    * **Component templates** (`/_component_template`) — the reusable pieces an
      index template composes. They apply nothing on their own.
    * **Legacy templates** (`/_template`) — the pre-composable kind, kept for
      compatibility. `put_template/3` and friends are these; prefer
      `put_index_template/3` for anything new.

  A composable index template always wins over a legacy one matching the same
  pattern, whatever its `order`.

  ## Shared conventions

    * A template `name` is a required path parameter, and may be several names
      (joined with `,`) on the read endpoints.
    * Endpoints that accept a request body take it as their first argument,
      required — pass `%{}` to send nothing.
    * `HEAD` existence checks come as a pair where the `?` variant plays the
      bang role: `index_template_exists/2` returns `{:ok, boolean()}` or
      `{:error, exception}`, `index_template_exists?/2` returns the bare
      boolean (`404` → `false`) and raises on genuine errors.

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
  @type exists_result :: {:ok, boolean()} | {:error, Exception.t()}

  ## Public functions — index templates

  @doc """
  Creates or updates the index template `name`
  ([Create or update index template API](https://docs.opensearch.org/latest/api-reference/index-apis/create-index-template/)).

  `template` is the request body, e.g.
  `%{index_patterns: ["posts-*"], template: %{...}}`.

      %{index_patterns: ["logs-*"], template: %{settings: %{number_of_shards: 1}}}
      |> Dowser.Opensearch.IndexTemplate.put_index_template("logs")
  """
  @spec put_index_template(map(), name(), keyword()) :: result()
  def put_index_template(%{} = template, name, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(name, "name") do
      ("/_index_template/" <> segment)
      |> Client.put(template, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `put_index_template/3`, but returns the body directly or raises the
  error exception.
  """
  @spec put_index_template!(map(), name(), keyword()) :: body()
  def put_index_template!(%{} = template, name, opts \\ []) do
    template |> put_index_template(name, opts) |> Dowser.unwrap()
  end

  @doc """
  Returns one, several, or all index templates
  ([Get index template API](https://docs.opensearch.org/latest/api-reference/index-apis/get-index-template/)).

  ## Options

    * `:name` — restrict the result to one or several template names, which may
      include wildcards; absent for all of them.
  """
  @spec get_index_template(keyword()) :: result()
  def get_index_template(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    with {:ok, path} <- optional_suffix("/_index_template", name, "name") do
      path
      |> Client.get(opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `get_index_template/1`, but returns the body directly or raises the
  error exception.
  """
  @spec get_index_template!(keyword()) :: body()
  def get_index_template!(opts \\ []) do
    opts |> get_index_template() |> Dowser.unwrap()
  end

  @doc """
  Deletes the index template `name`
  ([Delete index template API](https://docs.opensearch.org/latest/api-reference/index-apis/delete-index-template/)).
  """
  @spec delete_index_template(name(), keyword()) :: result()
  def delete_index_template(name, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(name, "name") do
      ("/_index_template/" <> segment)
      |> Client.delete(nil, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `delete_index_template/2`, but returns the body directly or raises the
  error exception.
  """
  @spec delete_index_template!(name(), keyword()) :: body()
  def delete_index_template!(name, opts \\ []) do
    name |> delete_index_template(opts) |> Dowser.unwrap()
  end

  @doc """
  Checks whether the index template `name` exists.

  Returns `{:ok, true}`, `{:ok, false}` or `{:error, exception}`.
  """
  @spec index_template_exists(name(), keyword()) :: exists_result()
  def index_template_exists(name, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(name, "name") do
      exists("/_index_template/" <> segment, opts)
    end
  end

  @doc """
  Like `index_template_exists/2`, but returns the boolean directly
  (`404` → `false`) or raises the error exception.
  """
  @spec index_template_exists?(name(), keyword()) :: boolean()
  def index_template_exists?(name, opts \\ []) do
    name |> index_template_exists(opts) |> Dowser.unwrap()
  end

  @doc """
  Simulates applying the matching index templates to the index `name`
  ([Simulate index API](https://docs.opensearch.org/latest/api-reference/index-apis/simulate-index-template/)).

  `body` is an optional template body to simulate alongside the existing ones;
  pass `%{}` to send nothing. `name` is the *index* name to simulate the
  creation of, not a template name.
  """
  @spec simulate_index_template(map(), name(), keyword()) :: result()
  def simulate_index_template(%{} = body, name, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(name, "name") do
      ("/_index_template/_simulate_index/" <> segment)
      |> Client.post(body, Helpers.put_idempotent(opts, true))
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `simulate_index_template/3`, but returns the body directly or raises
  the error exception.
  """
  @spec simulate_index_template!(map(), name(), keyword()) :: body()
  def simulate_index_template!(%{} = body, name, opts \\ []) do
    body |> simulate_index_template(name, opts) |> Dowser.unwrap()
  end

  @doc """
  Simulates the resolved composition of an index template
  ([Simulate template API](https://docs.opensearch.org/latest/api-reference/index-apis/simulate-index-template/)).

  `body` is a template body to simulate instead of a stored one; pass `%{}` to
  send nothing.

  ## Options

    * `:name` — a stored template to resolve, appended to the path; absent to
      resolve the body alone.
  """
  @spec simulate_template(map(), keyword()) :: result()
  def simulate_template(%{} = body, opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    with {:ok, path} <- optional_suffix("/_index_template/_simulate", name, "name") do
      path
      |> Client.post(body, Helpers.put_idempotent(opts, true))
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `simulate_template/2`, but returns the body directly or raises the
  error exception.
  """
  @spec simulate_template!(map(), keyword()) :: body()
  def simulate_template!(%{} = body, opts \\ []) do
    body |> simulate_template(opts) |> Dowser.unwrap()
  end

  ## Public functions — component templates

  @doc """
  Creates or updates the component template `name`
  ([Create or update component template API](https://docs.opensearch.org/latest/api-reference/index-apis/component-template/)).

  `template` is the request body, e.g. `%{template: %{settings: %{...}}}`. A
  component template applies nothing by itself: name it in an index template's
  `composed_of` to have it take effect.
  """
  @spec put_component_template(map(), name(), keyword()) :: result()
  def put_component_template(%{} = template, name, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(name, "name") do
      ("/_component_template/" <> segment)
      |> Client.put(template, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `put_component_template/3`, but returns the body directly or raises the
  error exception.
  """
  @spec put_component_template!(map(), name(), keyword()) :: body()
  def put_component_template!(%{} = template, name, opts \\ []) do
    template |> put_component_template(name, opts) |> Dowser.unwrap()
  end

  @doc """
  Returns one, several, or all component templates
  ([Get component template API](https://docs.opensearch.org/latest/api-reference/index-apis/component-template/)).

  ## Options

    * `:name` — restrict the result to one or several template names; absent
      for all of them.
  """
  @spec get_component_template(keyword()) :: result()
  def get_component_template(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    with {:ok, path} <- optional_suffix("/_component_template", name, "name") do
      path
      |> Client.get(opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `get_component_template/1`, but returns the body directly or raises the
  error exception.
  """
  @spec get_component_template!(keyword()) :: body()
  def get_component_template!(opts \\ []) do
    opts |> get_component_template() |> Dowser.unwrap()
  end

  @doc """
  Deletes the component template `name`
  ([Delete component template API](https://docs.opensearch.org/latest/api-reference/index-apis/component-template/)).
  """
  @spec delete_component_template(name(), keyword()) :: result()
  def delete_component_template(name, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(name, "name") do
      ("/_component_template/" <> segment)
      |> Client.delete(nil, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `delete_component_template/2`, but returns the body directly or raises
  the error exception.
  """
  @spec delete_component_template!(name(), keyword()) :: body()
  def delete_component_template!(name, opts \\ []) do
    name |> delete_component_template(opts) |> Dowser.unwrap()
  end

  @doc """
  Checks whether the component template `name` exists.

  Returns `{:ok, true}`, `{:ok, false}` or `{:error, exception}`.
  """
  @spec component_template_exists(name(), keyword()) :: exists_result()
  def component_template_exists(name, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(name, "name") do
      exists("/_component_template/" <> segment, opts)
    end
  end

  @doc """
  Like `component_template_exists/2`, but returns the boolean directly
  (`404` → `false`) or raises the error exception.
  """
  @spec component_template_exists?(name(), keyword()) :: boolean()
  def component_template_exists?(name, opts \\ []) do
    name |> component_template_exists(opts) |> Dowser.unwrap()
  end

  ## Public functions — legacy templates

  @doc """
  Creates or updates the legacy index template `name`
  ([Create or update template API](https://docs.opensearch.org/latest/api-reference/index-apis/create-index-template/)).

  `template` is the request body, e.g.
  `%{index_patterns: ["posts-*"], settings: %{...}}`.

  This is the pre-composable `/_template` endpoint; prefer
  `put_index_template/3` for anything new.
  """
  @spec put_template(map(), name(), keyword()) :: result()
  def put_template(%{} = template, name, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(name, "name") do
      ("/_template/" <> segment)
      |> Client.put(template, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `put_template/3`, but returns the body directly or raises the error
  exception.
  """
  @spec put_template!(map(), name(), keyword()) :: body()
  def put_template!(%{} = template, name, opts \\ []) do
    template |> put_template(name, opts) |> Dowser.unwrap()
  end

  @doc """
  Returns one, several, or all legacy index templates
  ([Get template API](https://docs.opensearch.org/latest/api-reference/index-apis/get-index-template/)).

  ## Options

    * `:name` — restrict the result to one or several template names; absent
      for all of them.
  """
  @spec get_template(keyword()) :: result()
  def get_template(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    with {:ok, path} <- optional_suffix("/_template", name, "name") do
      path
      |> Client.get(opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `get_template/1`, but returns the body directly or raises the error
  exception.
  """
  @spec get_template!(keyword()) :: body()
  def get_template!(opts \\ []) do
    opts |> get_template() |> Dowser.unwrap()
  end

  @doc """
  Deletes the legacy index template `name`
  ([Delete template API](https://docs.opensearch.org/latest/api-reference/index-apis/delete-index-template/)).
  """
  @spec delete_template(name(), keyword()) :: result()
  def delete_template(name, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(name, "name") do
      ("/_template/" <> segment)
      |> Client.delete(nil, opts)
      |> Helpers.parse_result()
    end
  end

  @doc """
  Like `delete_template/2`, but returns the body directly or raises the error
  exception.
  """
  @spec delete_template!(name(), keyword()) :: body()
  def delete_template!(name, opts \\ []) do
    name |> delete_template(opts) |> Dowser.unwrap()
  end

  @doc """
  Checks whether the legacy index template `name` exists.

  Returns `{:ok, true}`, `{:ok, false}` or `{:error, exception}`.
  """
  @spec template_exists(name(), keyword()) :: exists_result()
  def template_exists(name, opts \\ []) do
    with {:ok, segment} <- Helpers.required_segment(name, "name") do
      exists("/_template/" <> segment, opts)
    end
  end

  @doc """
  Like `template_exists/2`, but returns the boolean directly (`404` → `false`)
  or raises the error exception.
  """
  @spec template_exists?(name(), keyword()) :: boolean()
  def template_exists?(name, opts \\ []) do
    name |> template_exists(opts) |> Dowser.unwrap()
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

  # HEAD responses have no body, so the response format defaults to :raw.
  @spec exists(String.t(), keyword()) :: exists_result()
  defp exists(path, opts) do
    opts = Helpers.put_default_format(opts, :resp_format, :raw)

    :head
    |> Client.request(path, nil, opts)
    |> Helpers.parse_exists()
  end
end
