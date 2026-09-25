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

## Usage

Every API function is reached through its own module — there are no shortcuts on
the top-level `Dowser.Opensearch`:

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

## Documentation

The full API reference is on
[HexDocs](https://hexdocs.pm/dowser_opensearch).

## License

MIT — see [LICENSE.txt](LICENSE.txt).
