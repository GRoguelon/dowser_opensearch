# Dowser.Opensearch

[![Hex.pm](https://img.shields.io/hexpm/v/dowser_opensearch.svg)](https://hex.pm/packages/dowser_opensearch)

An Elixir client for the [OpenSearch](https://opensearch.org) API, built on top
of [`Dowser.Client`](https://hex.pm/packages/dowser_client).

The library follows the [OpenSearch OpenAPI
specification](https://github.com/opensearch-project/opensearch-api-specification):
each of its tags maps to one module, and each endpoint to one function named
after the operation.

## Installation

Add `dowser_opensearch` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dowser_opensearch, "~> 0.1.0"}
  ]
end
```

Point it at a cluster through a `Dowser.Client` context:

```elixir
config :dowser_client,
  contexts: [
    default: [endpoint: "http://localhost:9200"]
  ]
```

## Usage

Every API function is reached through its own module — there are no shortcuts on
the top-level Dowser.Opensearch namespace:

```elixir
{:ok, info} = Dowser.Opensearch.Info.info()
info["version"]["distribution"]
#=> "opensearch"
```

Each function comes in two variants: the plain one returns `{:ok, body}` or
`{:error, exception}`, and the bang one returns the body directly or raises:

```elixir
Dowser.Opensearch.Search.search!(%{query: %{match_all: %{}}}, index: "posts")
```

Required OpenSearch attributes are positional arguments; everything optional —
including the transport options forwarded to `Dowser.Client` — lives in the
trailing keyword list. A request body is always the first argument, so calls
pipe:

```elixir
%{query: %{term: %{"status" => "published"}}}
|> Dowser.Opensearch.Search.search(index: "posts", params: [size: 50])
```

`HEAD` checks come as a pair where the `?` variant plays the bang role:

```elixir
Dowser.Opensearch.Index.index_exists("posts")   #=> {:ok, true}
Dowser.Opensearch.Index.index_exists?("posts")  #=> true
```

## Modules

| Module                                   | Tag                    |
| ---------------------------------------- | ---------------------- |
| `Dowser.Opensearch.Alias`                | Aliases                |
| `Dowser.Opensearch.Cat`                  | CAT                    |
| `Dowser.Opensearch.Cluster`              | Cluster                |
| `Dowser.Opensearch.DanglingIndices`      | Dangling Indices       |
| `Dowser.Opensearch.DataStream`           | Data Streams           |
| `Dowser.Opensearch.Document`             | Document               |
| `Dowser.Opensearch.Index`                | Index                  |
| `Dowser.Opensearch.IndexSettings`        | Index Settings         |
| `Dowser.Opensearch.IndexStateManagement` | Index State Management |
| `Dowser.Opensearch.IndexTemplate`        | Index Templates        |
| `Dowser.Opensearch.Info`                 | Info                   |
| `Dowser.Opensearch.List`                 | List                   |
| `Dowser.Opensearch.Mappings`             | Mappings               |
| `Dowser.Opensearch.Reindex`              | Reindex                |
| `Dowser.Opensearch.Search`               | Search                 |

## Type casting

Wire `Dowser.Opensearch.Codec` in as the decoder and encoder, and documents are
cast against their own index mapping — dates become `DateTime`, IPs become
`:inet` tuples, and so on:

```elixir
config :dowser_client,
  contexts: [
    default: [
      endpoint: "http://localhost:9200",
      decoder: Dowser.Opensearch.Codec,
      encoder: Dowser.Opensearch.Codec
    ]
  ]
```

```elixir
Dowser.Opensearch.Document.get!("posts", "1")["_source"]["published_at"]
#=> ~U[2026-08-11 00:00:00.000Z]
```

Mappings are fetched and cached by `Dowser.Opensearch.MappingCacher`.

## Streaming

`Dowser.Opensearch.Streamer` walks more documents than fit in one response,
over a point in time:

```elixir
%{query: %{match_all: %{}}, sort: [%{"_id" => "asc"}]}
|> Dowser.Opensearch.Streamer.stream(index: "posts")
|> Stream.map(& &1["_source"])
|> Enum.each(&process/1)
```

The `sort` is required and its last key must be unique per document —
OpenSearch has no `_shard_doc` to supply a tiebreaker, and `search_after` on a
non-unique key silently skips rows. See the module documentation.

## Repositories

`Dowser.Opensearch.Repository` binds the index-related functions to a fixed or
computed index:

```elixir
defmodule Posts do
  use Dowser.Opensearch.Repository, index: "posts", only: [search: [:search], document: [:get]]
end

Posts.search!(%{query: %{match_all: %{}}})   # searches /posts/_search
Posts.get_doc!("1")                          # GETs /posts/_doc/1
```

## Documentation

The full API reference is on
[HexDocs](https://hexdocs.pm/dowser_opensearch).

## License

MIT — see
[LICENSE.txt](https://github.com/GRoguelon/dowser_opensearch/blob/main/LICENSE.txt).
