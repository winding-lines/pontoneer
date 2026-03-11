# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.2] - 2026-03-11

### Changed
- All four protocol builders (`TypeProtocolBuilder`, `MappingProtocolBuilder`, `NumberProtocolBuilder`, `SequenceProtocolBuilder`) now take a `self_type` compile-time parameter (e.g. `MappingProtocolBuilder[DataFrame](tb)`).
- Handler functions registered via `def_len`, `def_getitem`, `def_richcompare`, etc. now receive `UnsafePointer[T, MutAnyOrigin]` as their first argument instead of a raw `PythonObject`, eliminating the per-method `downcast_value_ptr` / `_get_self_ptr` boilerplate.
- Added internal `_unwrap_self[T]` helper in `adapters.mojo` that performs the typed downcast and aborts with a clear message on type mismatch.

## 0.3.0

Release under the modular-community channel.

## 0.2.3

Build debug.

## 0.2.2

Build debug.

## [0.2.1] - 2026-03-08

### Added
- Focused integration tests for all four protocol builders: mapping, number, sequence, and type protocol (`tests/`)
- `pixi run test-all` task and per-protocol `test-*` / `build-test-*` tasks

### Changed
- Builder method chains now use parenthesised multi-line style, consistent with the Mojo formatter

## [0.2.0] - 2026-03-08

### Changed
- Renamed internal modules: `protocols.mojo` → `utils.mojo`, `protocol_adapters.mojo` → `adapters.mojo`, `protocol_type_builder.mojo` → `builders.mojo`
- Replaced `PontoneerTypeBuilder` with four focused builders: `TypeProtocolBuilder`, `MappingProtocolBuilder`, `NumberProtocolBuilder`, `SequenceProtocolBuilder`

## [0.1.1] - 2026-03-07

Fix pixi.lock and debug prefix.dev release process.

## [0.1.0] - 2026-03-07

### Added
- `PyTypeObjectSlot` tag struct with slot constants: `mp_length`, `mp_getitem`, `mp_setitem`, `tp_richcompare`
- `NotImplementedError` — raise from a rich compare handler to return `Py_NotImplemented`
- `RichCompareOps` constants: `Py_LT`, `Py_LE`, `Py_EQ`, `Py_NE`, `Py_GT`, `Py_GE`
- `PontoneerTypeBuilder` — wraps `PythonTypeBuilder` and adds `def_method` overloads for all four protocol slots
- Columnar DataFrame example demonstrating all four slots (`examples/columnar/`)
