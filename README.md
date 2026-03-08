# pontoneer


Pontoneer is a Mojo library that provides an extension to the Python extension capabilities
provided by the standard library.

A Mojo library that adds **mapping protocol**, **number protocol**, **sequent protocol**
and **rich comparison** support. This is an expansion of the work 
proposed in [modular/modular#5562](https://github.com/modular/modular/pull/5562).

Without these extensions, a Mojo struct exported to Python can expose
`__getitem__` as a regular method but Python's `obj[key]` syntax won't work —
because the CPython runtime requires the method to be wired into the type's
`tp_slots`.  `pontoneer` provides the wiring.

## Requirements

- [pixi](https://pixi.sh) package manager
- Nightly MAX (`pixi` will install it automatically)

## Getting started

### As a package

To use the published package run the following command:

```bash
pixi add --channel https://prefix.dev/pontoneer --channel https://conda.modular.com/max-nightly pontoneer
```


Or in your `pixi,toml`:

```toml
channels = ["https://prefix.dev/pontoneer", "https://conda.modular.com/max-nightly/", "conda-forge"]

[dependencies]
pontoneer = ">=0.2.0"
```

### From source

```bash
git clone git@github.com:winding-lines/pontoneer.git
cd pontoneer
pixi install
pixi run build          # produces pontoneer.mojopkg
pixi run test-example   # builds and runs the columnar DataFrame example
```

## Usage

```mojo
from std.python.bindings import PythonModuleBuilder
from pontoneer import (
    NotImplementedError,
    RichCompareOps,
    TypeProtocolBuilder,
    MappingProtocolBuilder,
    NumberProtocolBuilder,
)


@export
fn PyInit_mymodule() -> PythonObject:
    try:
        var b = PythonModuleBuilder("mymodule")

        # Use the stdlib builder for regular methods …
        var tb = b.add_type[MyStruct]("MyStruct")
                   .def_init_defaultable[MyStruct]()
                   .def_staticmethod[MyStruct.new]("new")

        # Then add the rich compare Time Protocol slot.
        var tpb = TypeProtocolBuilder(tb)
        _ = tpb.def_richcompare[MyStruct.rich_compare]()

        # And some Mapping Protocol slots.
        var mpb = MappingProtocolBuilder(tb)
        _ = mpb.def_len[MyStruct.py__len__]()
        _ = mpb.def_getitem[MyStruct.py__getitem__]()
        _ = mpb.def_setitem[MyStruct.py__setitem__]()

        return b.finalize()
    except e:
        abort(String("failed to create module: ", e))
```

### Implementing the handlers

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

## Public API

| Symbol | Module |
|--------|--------|
| `PyTypeObjectSlot` | `pontoneer` |
| `NotImplementedError` | `pontoneer` |
| `RichCompareOps` | `pontoneer` |
| `PontoneerTypeBuilder` | `pontoneer` |

## Example

`examples/columnar/` contains a full working extension module — a columnar
`DataFrame` struct that exposes all four protocol slots to Python.

## License

Apache License v2.0 with LLVM Exceptions — see [LICENSE](LICENSE).
