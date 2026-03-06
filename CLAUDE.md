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
├── __init__.mojo               # Public API: 4 exports (see below)
├── protocols.mojo              # PyTypeObjectSlot, NotImplementedError, RichCompareOps
├── protocol_adapters.mojo      # Internal C-ABI adapters (_mp_length_wrapper, etc.)
└── protocol_type_builder.mojo  # PontoneerTypeBuilder
examples/columnar/
├── mojo_module.mojo            # DataFrame example (Mojo extension module)
└── test_module.py              # Python integration test
```

## Public API (`from pontoneer import …`)

| Symbol | Description |
|---|---|
| `PyTypeObjectSlot` | Tag struct with constants: `mp_length`, `mp_getitem`, `mp_setitem`, `tp_richcompare` |
| `NotImplementedError` | Raise from a rich compare handler to return `Py_NotImplemented` to Python |
| `RichCompareOps` | Constants `Py_LT=0` … `Py_GE=5` for use inside rich compare handlers |
| `PontoneerTypeBuilder` | Wraps `PythonTypeBuilder`; adds `def_method` overloads for the four protocol slots |

## Design decisions

- **`protocol_adapters.mojo` is internal** — the `_`-prefixed wrapper functions are
  not re-exported from `__init__.mojo`; they are only used by `protocol_type_builder.mojo`.
- **`PontoneerTypeBuilder` consumes a `PythonTypeBuilder`** via `owned`. Chain regular
  stdlib builder methods first, then pass ownership: `PontoneerTypeBuilder(tb^)`.
- **`_insert_slot` dependency** — `PontoneerTypeBuilder` calls
  `PythonTypeBuilder._insert_slot`, which is convention-private (underscore) but
  accessible in nightly Mojo. If a future compiler enforces visibility, the builder
  will need updating.
- **`where` clause dispatch** — `def_method` overloads are distinguished by
  `where slot.is_mp_length()` / `.is_mp_getitem()` etc., matching the PR's approach.

## Usage pattern

```mojo
from pontoneer import PyTypeObjectSlot, NotImplementedError, RichCompareOps, PontoneerTypeBuilder

var tb = b.add_type[MyStruct]("MyStruct")
           .def_init_defaultable[MyStruct]()
           .def_staticmethod[MyStruct.new]("new")

_ = PontoneerTypeBuilder(tb^)
        .def_method[MyStruct.py__len__,     PyTypeObjectSlot.mp_length]()
        .def_method[MyStruct.py__getitem__,  PyTypeObjectSlot.mp_getitem]()
        .def_method[MyStruct.py__setitem__,  PyTypeObjectSlot.mp_setitem]()
        .def_method[MyStruct.rich_compare,   PyTypeObjectSlot.tp_richcompare]()
```
