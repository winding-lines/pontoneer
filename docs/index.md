# pontoneer

`Pontoneer` is a Mojo library that provides an extension to the Python extension capabilities
provided by the standard library. `Pontoneer` adds support for:

- **mapping protocol** — `obj[key]`, `len(obj)`, `obj[key] = val`
- **number protocol** — arithmetic operators, `abs()`, `bool()`, etc.
- **sequence protocol** — indexed access, `in` operator, concatenation, repetition
- **rich comparison** — `==`, `!=`, `<`, `<=`, `>`, `>=`

This is an expansion of the work proposed in [modular/modular#5562](https://github.com/modular/modular/pull/5562).

Without these extensions, a Mojo struct exported to Python can expose
`__getitem__` as a regular method but Python's `obj[key]` syntax won't work —
because the CPython runtime requires the method to be wired into the type's
`tp_slots`. `pontoneer` provides the wiring.

## Requirements

- [pixi](https://pixi.sh) package manager
- Nightly MAX (`pixi` will install it automatically)

## Installation

### As a package

```bash
pixi add --channel https://prefix.dev/pontoneer --channel https://conda.modular.com/max-nightly pontoneer
```

Or in your `pixi.toml`:

```toml
channels = ["https://prefix.dev/pontoneer", "https://conda.modular.com/max-nightly/", "conda-forge"]

[dependencies]
pontoneer = ">=0.3.0"
```

### From source

```bash
git clone git@github.com:winding-lines/pontoneer.git
cd pontoneer
pixi install
pixi run build          # produces pontoneer.mojopkg
pixi run test-example   # builds and runs the columnar DataFrame example
```

## Quick start

```mojo
from std.python.bindings import PythonModuleBuilder
from pontoneer import (
    NotImplementedError,
    RichCompareOps,
    TypeProtocolBuilder,
    MappingProtocolBuilder,
    NumberProtocolBuilder,
    SequenceProtocolBuilder,
)


@export
fn PyInit_mymodule() -> PythonObject:
    try:
        var b = PythonModuleBuilder("mymodule")

        var tb = b.add_type[MyStruct]("MyStruct")
                   .def_init_defaultable[MyStruct]()

        # Rich comparison
        TypeProtocolBuilder[MyStruct](tb).def_richcompare[MyStruct.rich_compare]()

        # Mapping protocol: obj[key], len(obj), obj[key] = val
        MappingProtocolBuilder[MyStruct](tb)
            .def_len[MyStruct.py__len__]()
            .def_getitem[MyStruct.py__getitem__]()
            .def_setitem[MyStruct.py__setitem__]()

        # Number protocol: arithmetic and unary operators
        NumberProtocolBuilder[MyStruct](tb)
            .def_neg[MyStruct.py__neg__]()
            .def_add[MyStruct.py__add__]()

        return b.finalize()
    except e:
        abort(String("failed to create module: ", e))
```

## Handler signatures

| Slot | Required signature |
|------|--------------------|
| `mp_length` | `fn(py_self: PythonObject) raises -> Int` |
| `mp_getitem` | `fn(py_self: PythonObject, key: PythonObject) raises -> PythonObject` |
| `mp_setitem` | `fn(py_self: PythonObject, key: PythonObject, value: Variant[PythonObject, Int]) raises -> None` |
| `tp_richcompare` | `fn(py_self: PythonObject, other: PythonObject, op: Int) raises -> Bool` |

For `mp_setitem`, `value` is `Variant[PythonObject, Int](Int(0))` when Python
calls `del obj[key]`, and `Variant[PythonObject, Int](val)` for `obj[key] = val`.

For `tp_richcompare`, compare `op` against `RichCompareOps.Py_LT` … `Py_GE`.
Raise `NotImplementedError()` to return Python's `NotImplemented` singleton
(triggering the reflected operation on the other operand).
