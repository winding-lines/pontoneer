# pontoneer

`Pontoneer` is a Mojo library that enhances the Python extension capabilities
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
pontoneer = ">=0.5.0"
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


struct MyStruct(Defaultable, Movable):
    var data: List[Float64]

    fn __init__(out self):
        self.data = []

    fn py__len__(self) raises -> Int:
        return len(self.data)

    fn py__getitem__(self, key: PythonObject) raises -> PythonObject:
        return PythonObject(self.data[Int(py=key)])

    fn py__setitem__(
        mut self, key: PythonObject, value: Variant[PythonObject, Int]
    ) raises -> None:
        if value.isa[PythonObject]():
            self.data[Int(py=key)] = Float64(py=value[PythonObject])
        else:
            _ = self.data.pop(Int(py=key))

    fn rich_compare(
        self, other: PythonObject, op: Int
    ) raises -> Bool:
        var other_ptr = other.downcast_value_ptr[Self]()
        if op == RichCompareOps.Py_EQ:
            return len(self.data) == len(other_ptr[].data)
        raise NotImplementedError()

    fn py__neg__(self) raises -> PythonObject:
        var result = List[Float64](capacity=len(self.data))
        for v in self.data:
            result.append(-v)
        var out = MyStruct()
        out.data = result^
        return PythonObject(alloc=out^)

    fn py__add__(self, other: PythonObject) raises -> PythonObject:
        try:
            var other_ptr = other.downcast_value_ptr[Self]()
            var result = MyStruct()
            for v in self.data:
                result.data.append(v)
            for v in other_ptr[].data:
                result.data.append(v)
            return PythonObject(alloc=result^)
        except:
            raise NotImplementedError()


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

Handlers can be written as regular methods on `self` (value-receiver) or as
`@staticmethod` functions taking `UnsafePointer[T, MutAnyOrigin]`.
The value-receiver style is shown below.

| Slot | Value-receiver signature |
|------|--------------------------|
| `mp_length` | `fn py__len__(self) raises -> Int` |
| `mp_getitem` | `fn py__getitem__(self, key: PythonObject) raises -> PythonObject` |
| `mp_setitem` | `fn py__setitem__(mut self, key: PythonObject, value: Variant[PythonObject, Int]) raises -> None` |
| `tp_richcompare` | `fn rich_compare(self, other: PythonObject, op: Int) raises -> Bool` |

For `mp_setitem`, `value` is `Variant[PythonObject, Int](Int(0))` when Python
calls `del obj[key]`, and `Variant[PythonObject, Int](val)` for `obj[key] = val`.

For `tp_richcompare`, compare `op` against `RichCompareOps.Py_LT` … `Py_GE`.
Raise `NotImplementedError()` to return Python's `NotImplemented` singleton
(triggering the reflected operation on the other operand).
