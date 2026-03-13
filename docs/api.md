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

```mojo
struct MappingProtocolBuilder[self_type: ImplicitlyDestructible]
```

Installs CPython mapping protocol slots (`mp_length`, `mp_subscript`, `mp_ass_subscript`).

All methods return `Self` so calls can be chained.

### `def_len[method]()`

Installs `mp_length` (`len(obj)`).

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin]) raises -> Int`

### `def_getitem[method]()`

Installs `mp_subscript` (`obj[key]`).

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin], key: PythonObject) raises -> PythonObject`

### `def_setitem[method]()`

Installs `mp_ass_subscript` (`obj[key] = val` / `del obj[key]`).

`value` is `Variant[PythonObject, Int](Int(0))` for `del obj[key]` and
`Variant[PythonObject, Int](val)` for `obj[key] = val`.

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], key: PythonObject, value: Variant[PythonObject, Int]) raises` |
| Mut / raising | `fn(mut self: T, key: PythonObject, value: Variant[PythonObject, Int]) raises` |

---

## `SequenceProtocolBuilder[T]`

```mojo
struct SequenceProtocolBuilder[self_type: ImplicitlyDestructible]
```

Installs CPython sequence protocol slots.

All methods return `Self` for chaining.

| Method | Slot | Python operation |
|--------|------|-----------------|
| `def_len[method]()` | `sq_length` | `len(obj)` |
| `def_getitem[method]()` | `sq_item` | `obj[i]` |
| `def_setitem[method]()` | `sq_ass_item` | `obj[i] = val` / `del obj[i]` — pointer or `mut`-receiver overloads |
| `def_contains[method]()` | `sq_contains` | `x in obj` |
| `def_concat[method]()` | `sq_concat` | `obj + other` |
| `def_repeat[method]()` | `sq_repeat` | `obj * n` |
| `def_iconcat[method]()` | `sq_inplace_concat` | `obj += other` |
| `def_irepeat[method]()` | `sq_inplace_repeat` | `obj *= n` |

---

## `NumberProtocolBuilder[T]`

```mojo
struct NumberProtocolBuilder[self_type: ImplicitlyDestructible]
```

Installs CPython number protocol slots.

All methods return `Self` for chaining.

### Unary operators

| Method | Slot | Python operation |
|--------|------|-----------------|
| `def_abs[method]()` | `nb_absolute` | `abs(obj)` |
| `def_neg[method]()` | `nb_negative` | `-obj` |
| `def_pos[method]()` | `nb_positive` | `+obj` |
| `def_invert[method]()` | `nb_invert` | `~obj` |
| `def_bool[method]()` | `nb_bool` | `bool(obj)` |
| `def_int[method]()` | `nb_int` | `int(obj)` |
| `def_float[method]()` | `nb_float` | `float(obj)` |
| `def_index[method]()` | `nb_index` | `operator.index(obj)` |

### Binary operators

| Method | Slot | Python operation |
|--------|------|-----------------|
| `def_add[method]()` | `nb_add` | `obj + other` |
| `def_sub[method]()` | `nb_subtract` | `obj - other` |
| `def_mul[method]()` | `nb_multiply` | `obj * other` |
| `def_truediv[method]()` | `nb_true_divide` | `obj / other` |
| `def_floordiv[method]()` | `nb_floor_divide` | `obj // other` |
| `def_mod[method]()` | `nb_remainder` | `obj % other` |
| `def_lshift[method]()` | `nb_lshift` | `obj << other` |
| `def_rshift[method]()` | `nb_rshift` | `obj >> other` |
| `def_and[method]()` | `nb_and` | `obj & other` |
| `def_or[method]()` | `nb_or` | `obj \| other` |
| `def_xor[method]()` | `nb_xor` | `obj ^ other` |
| `def_divmod[method]()` | `nb_divmod` | `divmod(obj, other)` |

### Ternary operators

| Method | Slot | Python operation |
|--------|------|-----------------|
| `def_pow[method]()` | `nb_power` | `obj ** exp [% mod]` |

### In-place binary operators

| Method | Slot | Python operation |
|--------|------|-----------------|
| `def_iadd[method]()` | `nb_inplace_add` | `obj += other` |
| `def_isub[method]()` | `nb_inplace_subtract` | `obj -= other` |
| `def_imul[method]()` | `nb_inplace_multiply` | `obj *= other` |
| `def_itruediv[method]()` | `nb_inplace_true_divide` | `obj /= other` |
| `def_ifloordiv[method]()` | `nb_inplace_floor_divide` | `obj //= other` |
| `def_imod[method]()` | `nb_inplace_remainder` | `obj %= other` |
| `def_ilshift[method]()` | `nb_inplace_lshift` | `obj <<= other` |
| `def_irshift[method]()` | `nb_inplace_rshift` | `obj >>= other` |
| `def_iand[method]()` | `nb_inplace_and` | `obj &= other` |
| `def_ior[method]()` | `nb_inplace_or` | `obj \|= other` |
| `def_ixor[method]()` | `nb_inplace_xor` | `obj ^= other` |
| `def_ipow[method]()` | `nb_inplace_power` | `obj **= exp` |

Non-in-place methods (`def_add`, `def_sub`, etc.) have three overloads: pointer+raising, pointer+non-raising, and value+raising.

In-place methods (`def_iadd`, `def_isub`, etc.) have two overloads: pointer+raising and mut+raising. Value-receiver overloads are intentionally absent — a copy-based receiver cannot persist mutations.
