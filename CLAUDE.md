# pontoneer

Mojo library that backports the mapping protocol and rich comparison protocol
extensions proposed in https://github.com/modular/modular/pull/5562, allowing
Mojo Python extension modules to support `[]`, `len()`, and comparison operators
without waiting for the PR to land in the stdlib.

## Target environment

- Nightly MAX via pixi (`https://conda.modular.com/max-nightly/`)
- `pixi run build` — packages the library to `pontoneer.mojopkg`
- `pixi run test-example` — builds and runs the columnar DataFrame example

## Package structure

```
pontoneer/
├── __init__.mojo               # Public API: 6 exports (see below)
├── utils.mojo                  # NotImplementedError, RichCompareOps
├── adapters.mojo               # Internal C-ABI adapters (_mp_length_wrapper, etc.)
└── builders.mojo               # TypeProtocolBuilder, NumberProtocolBuilder,
│                               #   MappingProtocolBuilder, SequenceProtocolBuilder
examples/columnar/
├── mojo_module.mojo            # DataFrame example (Mojo extension module)
└── test_module.py              # Python integration test
```

## Public API (`from pontoneer import …`)

| Symbol | Description |
|---|---|
| `NotImplementedError` | Raise from a rich compare or binary handler to return `Py_NotImplemented` to Python |
| `RichCompareOps` | Constants `Py_LT=0` … `Py_GE=5` for use inside rich compare handlers |
| `TypeProtocolBuilder` | Installs `tp_richcompare` via `def_richcompare[method]()`; handlers receive `UnsafePointer[T, MutAnyOrigin]` as `self` |
| `NumberProtocolBuilder` | Installs nb_ slots: `def_neg`, `def_add`, `def_bool`, `def_pow`, etc.; handlers receive `UnsafePointer[T, MutAnyOrigin]` as `self` |
| `MappingProtocolBuilder` | Installs mp_ slots: `def_len`, `def_getitem`, `def_setitem`; handlers receive `UnsafePointer[T, MutAnyOrigin]` as `self` |
| `SequenceProtocolBuilder` | Installs sq_ slots: `def_len`, `def_getitem`, `def_setitem`, `def_contains`, `def_concat`, `def_repeat`, `def_iconcat`, `def_irepeat`; handlers receive `UnsafePointer[T, MutAnyOrigin]` as `self` |

## Documentation

When making public API changes, update both:
- `docs/api.md` — reference documentation for all builder methods and overloads
- `docs/index.md` — Quick Start example and Handler Signatures table

When bumping the version, keep the minimum version constraint in sync across:
- `README.md` — installation snippet
- `docs/index.md` — installation snippet

## Design decisions

- **Four specialized builders** replace a single monolithic builder. Each takes
  `mut inner: PythonTypeBuilder` and stores an `UnsafePointer` into it. The caller
  must ensure the `PythonTypeBuilder` (owned by the module builder) outlives the
  protocol builder, which is naturally satisfied within a single `PyInit_*` function.
- **`adapters.mojo` is internal** — the `_`-prefixed wrapper functions are not
  re-exported from `__init__.mojo`; they are only used by `builders.mojo`.
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
