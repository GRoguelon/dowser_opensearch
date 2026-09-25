defmodule Dowser.Opensearch.Target do
  @moduledoc """
  The index-target helper shared by every API module.

  An *index target* names what an endpoint acts on: nothing at all (every
  index), a single index, alias or data stream, or several of them. OpenSearch
  spells all of those as one path segment, so `segment/1` is what turns the
  Elixir-side shapes into that segment.

  In `dowser_elasticsearch` this helper lives on the indices module, because
  Elasticsearch tags index management, mappings, settings, aliases and
  templates alike as `indices`. OpenSearch splits them into separate tags — and
  therefore separate modules here — so the helper they all need has a module of
  its own.
  """

  ## Typespecs

  @typedoc "No index (all), a single index, or several indices."
  @type t :: nil | String.t() | atom() | [String.t() | atom()]

  @typedoc "A path parameter: a single name, or several (joined with `,`)."
  @type name :: String.t() | atom() | [String.t() | atom()]

  ## Public functions

  @doc """
  Encodes an index target into a comma-separated, URL-encoded path segment.

  Returns `nil` when the target is empty (`nil`, `""` or `[]`), so callers can
  choose between `/_search` and `/posts/_search`.

  ## Examples

      iex> Dowser.Opensearch.Target.segment(nil)
      nil

      iex> Dowser.Opensearch.Target.segment("posts")
      "posts"

      iex> Dowser.Opensearch.Target.segment(["posts", "my comments"])
      "posts,my%20comments"
  """
  @spec segment(t()) :: String.t() | nil
  def segment(index) when index in [nil, "", []] do
    nil
  end

  def segment(index) when is_atom(index) do
    index
    |> Atom.to_string()
    |> URI.encode()
  end

  def segment(index) when is_binary(index) do
    URI.encode(index)
  end

  def segment(indices) when is_list(indices) do
    Enum.map_join(indices, ",", fn
      index when is_atom(index) and not is_nil(index) ->
        index
        |> Atom.to_string()
        |> URI.encode()

      index when is_binary(index) ->
        URI.encode(index)
    end)
  end
end
