# API Reference

All public symbols are importable from the top-level `pontoneer` package:

```mojo
from pontoneer import (
    NotImplementedError,
    RichCompareOps,
    TypeProtocolBuilder,
    NumberProtocolBuilder,
    MappingProtocolBuilder,
    SequenceProtocolBuilder,
)
```

---

## `NotImplementedError`

```mojo
struct NotImplementedError(TrivialRegisterPassable, Writable)
```

Raise this from a rich compare or binary handler to signal Python's `NotImplemented`.

When caught by the internal wrapper, this causes the wrapper to return
`Py_NotImplemented` to Python rather than setting an exception, allowing Python
to try the reflected operation on the other operand.

**Example:**

```mojo
@staticmethod
fn rich_compare(
    self_ptr: PythonObject, other: PythonObject, op: Int
) raises -> Bool:
    if op == RichCompareOps.Py_EQ:
        ...
    raise NotImplementedError()
```

---

## `RichCompareOps`

```mojo
struct RichCompareOps
```

Constants for the `op` argument passed to `tp_richcompare` handlers.

| Constant | Value | Python operator |
|----------|-------|-----------------|
| `Py_LT`  | `0`   | `<`             |
| `Py_LE`  | `1`   | `<=`            |
| `Py_EQ`  | `2`   | `==`            |
| `Py_NE`  | `3`   | `!=`            |
| `Py_GT`  | `4`   | `>`             |
| `Py_GE`  | `5`   | `>=`            |

---

## `TypeProtocolBuilder[T]`

```mojo
struct TypeProtocolBuilder[self_type: ImplicitlyDestructible]
```

Wraps a `PythonTypeBuilder` reference and installs CPython type protocol slots.

Handlers receive `UnsafePointer[T, MutAnyOrigin]` as `self`.

### `def_richcompare[method]()`

Installs `tp_richcompare`. Three overloads are available:

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject, op: Int) raises -> Bool` |
| Pointer / non-raising | `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject, op: Int) -> Bool` |
| Value / raising | `fn(self: T, other: PythonObject, op: Int) raises -> Bool` |

---

## `MappingProtocolBuilder[T]`

See the dedicated [MappingProtocolBuilder reference](api/mapping.md) for per-method documentation.

---

## `SequenceProtocolBuilder[T]`

See the dedicated [SequenceProtocolBuilder reference](api/sequence.md) for per-method documentation.

---

## `NumberProtocolBuilder[T]`

See the dedicated [NumberProtocolBuilder reference](api/number.md) for per-method documentation.
