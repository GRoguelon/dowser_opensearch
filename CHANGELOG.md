# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The transport foundation: `Dowser.Opensearch.Client`, `Dowser.Opensearch.Error`,
  `Dowser.Opensearch.MappingError` and `Dowser.Opensearch.Target`.
- The type-casting layer: `Dowser.Opensearch.Codec` and its field codecs
  (`Binary`, `Date`, `DateRange`, `GeoPoint`, `IP`, `Range`), the `Mappable`
  traversal, and `Dowser.Opensearch.MappingCacher`. OpenSearch's `flat_object`
  is treated as opaque alongside Elasticsearch's `flattened`.
- Bulk payload handling: `Dowser.Opensearch.Bulk` and
  `Dowser.Opensearch.BulkError`, which report a bulk request's per-item
  failures.
