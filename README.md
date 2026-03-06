# pontoneer

A Mojo library that adds **mapping protocol** and **rich comparison** support
to Python extension modules written in Mojo, backporting the extensions
proposed in [modular/modular#5562](https://github.com/modular/modular/pull/5562).

Without these extensions, a Mojo struct exported to Python can expose
`__getitem__` as a regular method but Python's `obj[key]` syntax won't work —
because the CPython runtime requires the method to be wired into the type's
`tp_slots`.  `pontoneer` provides the wiring.

## Requirements

- [pixi](https://pixi.sh) package manager
- Nightly MAX (`pixi` will install it automatically)

## Getting started

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
    PyTypeObjectSlot,
    NotImplementedError,
    RichCompareOps,
    PontoneerTypeBuilder,
)

@export
fn PyInit_mymodule() -> PythonObject:
    try:
        var b = PythonModuleBuilder("mymodule")

        # Use the stdlib builder for regular methods …
        var tb = b.add_type[MyStruct]("MyStruct")
                   .def_init_defaultable[MyStruct]()
                   .def_staticmethod[MyStruct.new]("new")

        # … then hand ownership to PontoneerTypeBuilder for protocol slots.
        _ = PontoneerTypeBuilder(tb^)
                .def_method[MyStruct.py__len__,     PyTypeObjectSlot.mp_length]()
                .def_method[MyStruct.py__getitem__,  PyTypeObjectSlot.mp_getitem]()
                .def_method[MyStruct.py__setitem__,  PyTypeObjectSlot.mp_setitem]()
                .def_method[MyStruct.rich_compare,   PyTypeObjectSlot.tp_richcompare]()

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
