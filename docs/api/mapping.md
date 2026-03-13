# MappingProtocolBuilder[T]

```mojo
struct MappingProtocolBuilder[self_type: ImplicitlyDestructible]
```

Installs CPython mapping protocol slots on a `PythonTypeBuilder`.

Construct directly from a `PythonTypeBuilder`. All methods return `Self` for chaining.

## def_len()

Installs `mp_length` — called by `len(obj)`.

See: [PyMappingMethods.mp_length](https://docs.python.org/3/c-api/typeobj.html#c.PyMappingMethods.mp_length)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin]) raises -> Int` |
| Pointer / non-raising | `fn(self: UnsafePointer[T, MutAnyOrigin]) -> Int` |
| Value / raising | `fn(self: T) raises -> Int` |

## def_getitem()

Installs `mp_subscript` — called by `obj[key]`.

See: [PyMappingMethods.mp_subscript](https://docs.python.org/3/c-api/typeobj.html#c.PyMappingMethods.mp_subscript)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], key: PythonObject) raises -> PythonObject` |
| Pointer / non-raising | `fn(self: UnsafePointer[T, MutAnyOrigin], key: PythonObject) -> PythonObject` |
| Value / raising | `fn(self: T, key: PythonObject) raises -> PythonObject` |

## def_setitem()

Installs `mp_ass_subscript` — called by `obj[key] = val` or `del obj[key]`.

`value` is `Variant[PythonObject, Int](Int(0))` for deletion and
`Variant[PythonObject, Int](val)` for assignment.

See: [PyMappingMethods.mp_ass_subscript](https://docs.python.org/3/c-api/typeobj.html#c.PyMappingMethods.mp_ass_subscript)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], key: PythonObject, value: Variant[PythonObject, Int]) raises -> None` |
| Mut / raising | `fn(mut self: T, key: PythonObject, value: Variant[PythonObject, Int]) raises -> None` |
