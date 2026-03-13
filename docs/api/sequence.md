# SequenceProtocolBuilder[T]

```mojo
struct SequenceProtocolBuilder[self_type: ImplicitlyDestructible]
```

Installs CPython sequence protocol slots on a `PythonTypeBuilder`.

Construct directly from a `PythonTypeBuilder`. All methods return `Self` for chaining.

Each `def_*` method has three overloads unless noted: pointer+raising,
pointer+non-raising, and value+raising. `def_setitem` additionally has a
mut+raising overload (value-receiver omitted — mutations on a copy don't persist).

## def_len()

Installs `sq_length` — called by `len(obj)`.

See: [PySequenceMethods.sq_length](https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_length)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin]) raises -> Int` |
| Pointer / non-raising | `fn(self: UnsafePointer[T, MutAnyOrigin]) -> Int` |
| Value / raising | `fn(self: T) raises -> Int` |

## def_getitem()

Installs `sq_item` — called by `obj[i]` (integer index).

See: [PySequenceMethods.sq_item](https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_item)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], index: Int) raises -> PythonObject` |
| Pointer / non-raising | `fn(self: UnsafePointer[T, MutAnyOrigin], index: Int) -> PythonObject` |
| Value / raising | `fn(self: T, index: Int) raises -> PythonObject` |

## def_setitem()

Installs `sq_ass_item` — called by `obj[i] = val` or `del obj[i]`.

`value` is `Variant[PythonObject, Int](Int(0))` for deletion and
`Variant[PythonObject, Int](val)` for assignment.

See: [PySequenceMethods.sq_ass_item](https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_ass_item)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], index: Int, value: Variant[PythonObject, Int]) raises -> None` |
| Mut / raising | `fn(mut self: T, index: Int, value: Variant[PythonObject, Int]) raises -> None` |

## def_contains()

Installs `sq_contains` — called by `item in obj`.

See: [PySequenceMethods.sq_contains](https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_contains)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], item: PythonObject) raises -> Bool` |
| Pointer / non-raising | `fn(self: UnsafePointer[T, MutAnyOrigin], item: PythonObject) -> Bool` |
| Value / raising | `fn(self: T, item: PythonObject) raises -> Bool` |

## def_concat()

Installs `sq_concat` — called by `obj + other`.

See: [PySequenceMethods.sq_concat](https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_concat)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject` |
| Pointer / non-raising | `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) -> PythonObject` |
| Value / raising | `fn(self: T, other: PythonObject) raises -> PythonObject` |

## def_repeat()

Installs `sq_repeat` — called by `obj * n`.

See: [PySequenceMethods.sq_repeat](https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_repeat)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], count: Int) raises -> PythonObject` |
| Pointer / non-raising | `fn(self: UnsafePointer[T, MutAnyOrigin], count: Int) -> PythonObject` |
| Value / raising | `fn(self: T, count: Int) raises -> PythonObject` |

## def_iconcat()

Installs `sq_inplace_concat` — called by `obj += other`.

See: [PySequenceMethods.sq_inplace_concat](https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_inplace_concat)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject` |
| Pointer / non-raising | `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) -> PythonObject` |
| Value / raising | `fn(self: T, other: PythonObject) raises -> PythonObject` |

## def_irepeat()

Installs `sq_inplace_repeat` — called by `obj *= n`.

See: [PySequenceMethods.sq_inplace_repeat](https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_inplace_repeat)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], count: Int) raises -> PythonObject` |
| Pointer / non-raising | `fn(self: UnsafePointer[T, MutAnyOrigin], count: Int) -> PythonObject` |
| Value / raising | `fn(self: T, count: Int) raises -> PythonObject` |
