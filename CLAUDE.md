# pontoneer

Mojo library that backports the mapping protocol and rich comparison protocol
extensions proposed in https://github.com/modular/modular/pull/5562, allowing
Mojo Python extension modules to support `[]`, `len()`, and comparison operators
without waiting for the PR to land in the stdlib.

## Target environment

- Mojo 1.0 stable via pixi (`https://conda.modular.com/max/`)
- `pixi run build` — packages the library to `pontoneer.mojoc`
- `pixi run --environment test test-example` — builds and runs the columnar DataFrame example
- `pixi run --environment test test-all` — runs all tests

## Package structure

```
pontoneer/
├── __init__.mojo               # Public API: 8 exports (see below)
├── utils.mojo                  # NotImplementedError, RichCompareOps
├── slots.mojo                  # Internal: _PySlotIndex slot-index constants
├── adapters.mojo               # Internal: C-ABI adapters (_mp_length_wrapper, etc.)
│                               #   + shared _install_/_lift_/_conv_ slot helpers
├── type_protocol.mojo          # TypeProtocolBuilder
├── number.mojo                 # NumberProtocolBuilder
├── mapping.mojo                # MappingProtocolBuilder
├── sequence.mojo               # SequenceProtocolBuilder
├── buffer.mojo                 # BufferProtocolBuilder, BufferInfo
└── builders.mojo               # Thin re-export shim for the four builders above
examples/columnar/
├── mojo_module.mojo            # DataFrame example (Mojo extension module)
└── test_module.py              # Python integration test
```

This mirrors the per-protocol file organization of the upstream stdlib PR
https://github.com/modular/modular/pull/6453.

## Public API (`from pontoneer import …`)

| Symbol | Description |
|---|---|
| `NotImplementedError` | Raise from a rich compare or binary handler to return `Py_NotImplemented` to Python |
| `RichCompareOps` | Constants `Py_LT=0` … `Py_GE=5` for use inside rich compare handlers |
| `TypeProtocolBuilder` | Installs `tp_richcompare` via `def_richcompare[method]()`; handlers receive `Pointer[T, MutAnyOrigin]` as `self` |
| `NumberProtocolBuilder` | Installs nb_ slots: `def_neg`, `def_add`, `def_bool`, `def_pow`, etc.; handlers receive `Pointer[T, MutAnyOrigin]` as `self` |
| `MappingProtocolBuilder` | Installs mp_ slots: `def_len`, `def_getitem`, `def_setitem`; handlers receive `Pointer[T, MutAnyOrigin]` as `self` |
| `SequenceProtocolBuilder` | Installs sq_ slots: `def_len`, `def_getitem`, `def_setitem`, `def_contains`, `def_concat`, `def_repeat`, `def_iconcat`, `def_irepeat`; handlers receive `Pointer[T, MutAnyOrigin]` as `self` |

## Documentation

When making public API changes, update both:
- `docs/api.md` — reference documentation for all builder methods and overloads
- `docs/index.md` — Quick Start example and Handler Signatures table

When bumping the version, update `shelf.toml` — it is the version published to
[Mojo Shelf](https://mojoshelf.org/tins/pontoneer), which `README.md` and
`docs/index.md` both point at instead of pinning a version inline.

## Design decisions

- **Four specialized builders** replace a single monolithic builder, each in its
  own per-protocol module (`type_protocol.mojo`, `number.mojo`, `mapping.mojo`,
  `sequence.mojo`). Each takes
  `mut inner: PythonTypeBuilder` and stores a `Pointer` into it. The caller
  must ensure the `PythonTypeBuilder` (owned by the module builder) outlives the
  protocol builder, which is naturally satisfied within a single `PyInit_*` function.
  `builders.mojo` is a thin re-export shim preserving the historical import path.
- **`adapters.mojo` and `slots.mojo` are internal** — the `_`-prefixed wrapper
  functions, the shared `_install_`/`_lift_`/`_conv_` slot helpers (in
  `adapters.mojo`), and the `_PySlotIndex` constants (in `slots.mojo`) are not
  re-exported from `__init__.mojo`; they are only used by the per-protocol builders.
- **`_insert_slot` dependency** — all builders call `PythonTypeBuilder._insert_slot`,
  which is convention-private (underscore) but accessible in nightly Mojo. If a future
  compiler enforces visibility, the builders will need updating.
- **`NotImplementedError` dispatch** — binary and ternary nb_ wrappers, and the
  `tp_richcompare` wrapper, check the error message string against
  `NotImplementedError.name` to return `Py_NotImplemented` instead of setting
  a Python exception.

## Usage pattern

```mojo
from pontoneer import (
    NotImplementedError, RichCompareOps,
    TypeProtocolBuilder, MappingProtocolBuilder,
    NumberProtocolBuilder, SequenceProtocolBuilder,
)

ref tb = b.add_type[MyStruct]("MyStruct")
           .def_init_defaultable[MyStruct]()
           .def_staticmethod[MyStruct.new]("new")

TypeProtocolBuilder[MyStruct](tb).def_richcompare[MyStruct.rich_compare]()
MappingProtocolBuilder[MyStruct](tb)
    .def_len[MyStruct.py__len__]()
    .def_getitem[MyStruct.py__getitem__]()
    .def_setitem[MyStruct.py__setitem__]()
NumberProtocolBuilder[MyStruct](tb)
    .def_neg[MyStruct.py__neg__]()
    .def_add[MyStruct.py__add__]()
```
