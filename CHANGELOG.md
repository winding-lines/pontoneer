# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-08-11

Pontoneer 1.0 targets stable Mojo 1.0.0 from the `https://conda.modular.com/max/`
channel (previously: nightly builds from `max-nightly`).

### Changed
- **Breaking:** handler signatures now use `Pointer[T, MutAnyOrigin]` instead of
  the removed `UnsafePointer[T, MutAnyOrigin]` for pointer-receiver methods,
  following the stdlib rename. Value-receiver handlers are unchanged.
- **Breaking:** `BufferInfo.buf` is now stored as `Pointer[UInt8, MutUntrackedOrigin]`
  (the constructor still accepts any mutable-origin pointer).
- The precompiled library is now built with `mojo precompile` and named
  `pontoneer.mojoc` (previously `mojo package` / `pontoneer.mojopkg`).
- Protocol builders store their `PythonTypeBuilder` pointer with
  `MutUntrackedOrigin` (struct fields may no longer expose `MutAnyOrigin`).
- Error paths in the slot adapters now use the stdlib's `raise_python_exception`
  / `_set_python_error` helpers instead of hand-rolled `PyErr_SetString` calls.
- `PyType_Slot` construction updated to the 1.0 fieldwise form via the stdlib's
  `_fn_ptr_as_opaque` helper.
- The buffer protocol's shape/strides/format scratch block is allocated with
  `unsafe_alloc[UInt8]` and nullable `Py_buffer` pointer fields are modeled as
  `OptionalPointer` (assigning `None` for NULL).
- `PyInit_*` exports in the examples and tests declare `abi("C")` explicitly, as
  required by Mojo 1.0.
- Release tooling (`tools/bump-mojo.sh`, `tools/tag-release.sh`) now accepts
  stable Mojo versions in addition to nightly `.devN` versions.
- Internal reorganization (non-breaking): `builders.mojo` was split into per-protocol modules — `type_protocol.mojo` (`TypeProtocolBuilder`), `number.mojo` (`NumberProtocolBuilder`), `mapping.mojo` (`MappingProtocolBuilder`), and `sequence.mojo` (`SequenceProtocolBuilder`) — to mirror the file organization of the upstream stdlib PR https://github.com/modular/modular/pull/6453. `builders.mojo` is now a thin re-export shim, so the `from pontoneer.builders import ...` path still works.
- The slot-index constants (`_PySlotIndex`) moved to a new internal `slots.mojo` module; the shared `_install_`/`_lift_`/`_conv_` slot-installation helpers moved into `adapters.mojo`. Both are internal and not re-exported. The public API (`from pontoneer import ...`) is unchanged.

## [0.6.2] - 2026-03-22

### Changed
- Replaced all `fn` keyword occurrences with `def` across the library and tests, following the Mojo nightly deprecation of `fn` in favour of `def`.
- Release workflow now appends the Mojo compiler date to the version string (`x.y.z-YYYYMMDD`), making the exact nightly dependency explicit in every release artifact.

## [0.6.0] - 2026-03-15

### Changed
- `rich_compare` handlers in the columnar example and type-protocol test converted from `@staticmethod` + `UnsafePointer[Self, MutAnyOrigin]` to plain value-receiver methods (`def rich_compare(self, ...)`), demonstrating the existing value-receiver overload of `TypeProtocolBuilder.def_richcompare`.
- Call-count tracking in the columnar example moved from a `Dict[String, Int]` field on `DataFrame` to a process-global `_Global` dict, keeping the struct layout lean and avoiding copies on every method call.

## [0.5.0] - 2026-03-14

### Added
- `BufferProtocolBuilder[T]` — installs `bf_getbuffer` and `bf_releasebuffer` slots, enabling zero-copy access to Mojo struct internals from `memoryview`, `numpy.frombuffer`, `bytes()`, and any other buffer consumer.
- `BufferInfo` — user-friendly struct returned by the `bf_getbuffer` handler, describing a 1D C-contiguous buffer (`buf`, `nitems`, `itemsize`, `format`, `readonly`).
- Both symbols are exported from the top-level `pontoneer` package and documented in the new `docs/api/buffer.md` reference page.

## [0.4.0] - 2026-03-13

### Added
- `MappingProtocolBuilder.def_setitem` now accepts a `mut`-receiver handler (`fn(mut self, key: PythonObject, value: Variant[PythonObject, Int]) raises -> None`), allowing mutations to persist without a raw `UnsafePointer`.
- `SequenceProtocolBuilder.def_setitem` likewise accepts a `mut`-receiver handler (`fn(mut self, index: Int, value: Variant[PythonObject, Int]) raises -> None`).
- `NumberProtocolBuilder` in-place operators (`def_iadd`, `def_isub`, `def_imul`, `def_ifloordiv`, `def_imod`, `def_imul`, `def_ior`, `def_iand`, `def_ixor`, `def_ilshift`, `def_irshift`, `def_itruediv`, `def_imatmul`, `def_ipow`) now accept `mut`-receiver handlers.

### Removed
- Value-receiver overloads for all in-place (`def_i*`) methods in `NumberProtocolBuilder` — a copy-based receiver cannot persist mutations, making those overloads incorrect for in-place semantics.

### Changed
- `examples/columnar` mapping protocol handlers (`py__len__`, `py__getitem__`, `py__setitem__`) converted from `@staticmethod` + `UnsafePointer` to regular `self` / `mut self` methods.

## [0.3.5] - 2026-03-11

### Added
- All protocol builder `def_*` methods that return `PythonObject` now also accept handler functions that return any type satisfying `ConvertibleToPython & ImplicitlyCopyable`. The correct overload is resolved at compile time with no runtime overhead.

## [0.3.4] - 2026-03-11

### Added
- All protocol builder `def_*` methods now accept value-receiver handler functions (e.g. `fn(self: MyStruct) -> Int`) in addition to the existing pointer-receiver (`UnsafePointer[T, MutAnyOrigin]`) overloads. Both raising and non-raising value-receiver handlers are accepted via a single overload (Mojo coerces `fn(T) -> R` to `fn(T) raises -> R` automatically for value types).

## [0.3.3] - 2026-03-11

### Added
- Protocol builder `def_*` methods now accept non-raising handler functions (e.g. `fn(...) -> T` without `raises`), in addition to the existing raising overloads. The correct overload is selected automatically at compile time with no runtime overhead.

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
