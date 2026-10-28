# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-10-27

The modules are renamed from `Dowser.Opensearch.*` to `Dowser.OpenSearch.*`,
following OpenSearch's own spelling. The package stays `dowser_opensearch`, and
the API itself is unchanged.

### Changed

- **Breaking:** every module moved from `Dowser.Opensearch.*` to
  `Dowser.OpenSearch.*`; update the aliases and calls in your code. The
  application name, its `config :dowser_opensearch, ...` keys and the
  `[:dowser_opensearch, :mapping, :failure]` telemetry event are unchanged.

## [0.1.0] - 2026-09-26

The first release: an Elixir client for the OpenSearch API, built on
`Dowser.Client` and modelled on
[`dowser_elasticsearch`](https://hex.pm/packages/dowser_elasticsearch).

### Added — API modules

One module per tag of the [OpenSearch OpenAPI
specification](https://github.com/opensearch-project/opensearch-api-specification),
each covering the common operations of its tag:

- `Dowser.OpenSearch.Alias` — the atomic `update_aliases/2` plus the
  single-alias put/delete/get/exists set.
- `Dowser.OpenSearch.Cat` — all 24 CAT endpoints, including the OpenSearch-only
  `cluster_manager`, `pit_segments` and `segment_replication`.
- `Dowser.OpenSearch.Cluster` — health, state, stats, settings, reroute,
  allocation explain, and the OpenSearch-only weighted routing and decommission
  awareness.
- `Dowser.OpenSearch.DanglingIndices` — list, import and delete.
- `Dowser.OpenSearch.DataStream` — create, get, delete, stats and modify.
- `Dowser.OpenSearch.Document` — single-document CRUD, the exists/source pairs,
  bulk, multi-get and term vectors.
- `Dowser.OpenSearch.Index` — index lifecycle, the resize trio, rollover, the
  maintenance endpoints, the monitoring reads and `resolve_index/2`.
- `Dowser.OpenSearch.IndexSettings` — get and update.
- `Dowser.OpenSearch.IndexStateManagement` — the ISM policy endpoints and
  `refresh_search_analyzers/2`.
- `Dowser.OpenSearch.IndexTemplate` — composable index templates, component
  templates and the legacy `/_template` endpoints.
- `Dowser.OpenSearch.Info` — `info/1` and the `ping/1` pair.
- `Dowser.OpenSearch.List` — OpenSearch's paginated counterpart to CAT indices
  and shards.
- `Dowser.OpenSearch.Mappings` — put, get and get-field.
- `Dowser.OpenSearch.Reindex` — `_reindex`, the two by-query operations and
  their `_rethrottle` endpoints.
- `Dowser.OpenSearch.Search` — search, msearch, count, explain, field caps,
  search shards, validate query, the template endpoints, scroll and
  point-in-time.

### Added — supporting layer

- The transport foundation: `Dowser.OpenSearch.Client`,
  `Dowser.OpenSearch.Error`, `Dowser.OpenSearch.MappingError` and
  `Dowser.OpenSearch.Target`.
- The type-casting layer: `Dowser.OpenSearch.Codec` and its field codecs
  (`Binary`, `Date`, `DateRange`, `GeoPoint`, `IP`, `Range`), the `Mappable`
  traversal and `Dowser.OpenSearch.MappingCacher`.
- Bulk payload handling: `Dowser.OpenSearch.Bulk` and
  `Dowser.OpenSearch.BulkError`, which report a bulk request's per-item
  failures.
- `Dowser.OpenSearch.Repository` — binds the index-related API functions to a
  fixed or computed index.
- `Dowser.OpenSearch.Streamer` — walks a search as a lazy `Stream` over a point
  in time, with `stream_slices/4` for the parallel case.

### Notes for `dowser_elasticsearch` users

The API surface follows the same conventions, but OpenSearch is not
Elasticsearch and a few things differ on purpose:

- **Finer-grained modules.** Elasticsearch tags index management, mappings,
  settings, aliases and templates alike as `indices`; OpenSearch splits them,
  so each gets its own module. The index-target helper they share moved from
  the indices module to `Dowser.OpenSearch.Target`.
- **`Dowser.OpenSearch.Streamer` requires a `sort`.** Elasticsearch has a
  `_shard_doc` sort field made for tiebreaking a point-in-time walk, which its
  streamer appends for you. OpenSearch forked before that existed and never
  added it, and `search_after` on a non-unique final key silently skips or
  repeats documents — so the sort is the caller's to give, and a missing one
  raises rather than producing a walk that loses rows.
- **Point-in-time lives elsewhere.** `/_search/point_in_time` rather than
  `/_pit`, and the id is named `pit_id`; a delete wants it as an array, so
  `delete_pit/2` wraps a single id.
- **By-query operations are `Reindex`, not `Document`.** OpenSearch tags
  `_delete_by_query`, `_update_by_query` and `_reindex` together.
- **`validate_query` is a search endpoint** here, where Elasticsearch tags it
  `indices`.
- **No `remove_block`.** OpenSearch has no endpoint for it; clear the
  corresponding `index.blocks.*` setting instead.
- **`flat_object`** is treated as opaque alongside Elasticsearch's `flattened`,
  so its keys never reach the atom table.
