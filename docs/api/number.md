# NumberProtocolBuilder[T]

```mojo
struct NumberProtocolBuilder[self_type: ImplicitlyDestructible]
```

Installs CPython number protocol slots on a `PythonTypeBuilder`.

Construct directly from a `PythonTypeBuilder`. All methods return `Self` for chaining.

Non-in-place methods have three overloads: pointer+raising, pointer+non-raising,
and value+raising. In-place methods (`def_i*`) have two overloads: pointer+raising
and mut+raising — value-receiver overloads are omitted because copies cannot
persist mutations.

---

## Unary operators

### def_neg[method]()

Installs `nb_negative` — called by `-obj`.

See: [PyNumberMethods.nb_negative](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_negative)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin]) raises -> PythonObject`

### def_pos[method]()

Installs `nb_positive` — called by `+obj`.

See: [PyNumberMethods.nb_positive](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_positive)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin]) raises -> PythonObject`

### def_abs[method]()

Installs `nb_absolute` — called by `abs(obj)`.

See: [PyNumberMethods.nb_absolute](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_absolute)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin]) raises -> PythonObject`

### def_invert[method]()

Installs `nb_invert` — called by `~obj`.

See: [PyNumberMethods.nb_invert](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_invert)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin]) raises -> PythonObject`

### def_bool[method]()

Installs `nb_bool` — called by `bool(obj)`.

See: [PyNumberMethods.nb_bool](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_bool)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin]) raises -> Bool`

### def_int[method]()

Installs `nb_int` — called by `int(obj)`.

See: [PyNumberMethods.nb_int](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_int)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin]) raises -> PythonObject`

### def_float[method]()

Installs `nb_float` — called by `float(obj)`.

See: [PyNumberMethods.nb_float](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_float)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin]) raises -> PythonObject`

### def_index[method]()

Installs `nb_index` — called by `operator.index(obj)` and when `obj` is used as a list index.

See: [PyNumberMethods.nb_index](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_index)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin]) raises -> PythonObject`

---

## Binary operators

### def_add[method]()

Installs `nb_add` — called by `obj + other`.

See: [PyNumberMethods.nb_add](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_add)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject`

### def_sub[method]()

Installs `nb_subtract` — called by `obj - other`.

See: [PyNumberMethods.nb_subtract](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_subtract)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject`

### def_mul[method]()

Installs `nb_multiply` — called by `obj * other`.

See: [PyNumberMethods.nb_multiply](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_multiply)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject`

### def_truediv[method]()

Installs `nb_true_divide` — called by `obj / other`.

See: [PyNumberMethods.nb_true_divide](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_true_divide)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject`

### def_floordiv[method]()

Installs `nb_floor_divide` — called by `obj // other`.

See: [PyNumberMethods.nb_floor_divide](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_floor_divide)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject`

### def_mod[method]()

Installs `nb_remainder` — called by `obj % other`.

See: [PyNumberMethods.nb_remainder](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_remainder)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject`

### def_lshift[method]()

Installs `nb_lshift` — called by `obj << other`.

See: [PyNumberMethods.nb_lshift](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_lshift)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject`

### def_rshift[method]()

Installs `nb_rshift` — called by `obj >> other`.

See: [PyNumberMethods.nb_rshift](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_rshift)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject`

### def_and[method]()

Installs `nb_and` — called by `obj & other`.

See: [PyNumberMethods.nb_and](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_and)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject`

### def_or[method]()

Installs `nb_or` — called by `obj | other`.

See: [PyNumberMethods.nb_or](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_or)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject`

### def_xor[method]()

Installs `nb_xor` — called by `obj ^ other`.

See: [PyNumberMethods.nb_xor](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_xor)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject`

### def_divmod[method]()

Installs `nb_divmod` — called by `divmod(obj, other)`.

See: [PyNumberMethods.nb_divmod](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_divmod)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject`

### def_matmul[method]()

Installs `nb_matrix_multiply` — called by `obj @ other`.

See: [PyNumberMethods.nb_matrix_multiply](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_matrix_multiply)

Handler signature: `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject`

---

## Ternary operators

### def_pow[method]()

Installs `nb_power` — called by `obj ** exp` or `pow(obj, exp, mod)`.

`mod` is `None` unless the three-argument form `pow(base, exp, mod)` was called.
Raise `NotImplementedError()` to return `Py_NotImplemented`.

See: [PyNumberMethods.nb_power](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_power)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], exp: PythonObject, mod: PythonObject) raises -> PythonObject` |
| Pointer / non-raising | `fn(self: UnsafePointer[T, MutAnyOrigin], exp: PythonObject, mod: PythonObject) -> PythonObject` |
| Value / raising | `fn(self: T, exp: PythonObject, mod: PythonObject) raises -> PythonObject` |

---

## In-place binary operators

Each in-place method has two overloads: pointer+raising and mut+raising.

### def_iadd[method]()

Installs `nb_inplace_add` — called by `obj += other`.

See: [PyNumberMethods.nb_inplace_add](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_add)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject` |
| Mut / raising | `fn(mut self: T, other: PythonObject) raises -> PythonObject` |

### def_isub[method]()

Installs `nb_inplace_subtract` — called by `obj -= other`.

See: [PyNumberMethods.nb_inplace_subtract](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_subtract)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject` |
| Mut / raising | `fn(mut self: T, other: PythonObject) raises -> PythonObject` |

### def_imul[method]()

Installs `nb_inplace_multiply` — called by `obj *= other`.

See: [PyNumberMethods.nb_inplace_multiply](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_multiply)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject` |
| Mut / raising | `fn(mut self: T, other: PythonObject) raises -> PythonObject` |

### def_itruediv[method]()

Installs `nb_inplace_true_divide` — called by `obj /= other`.

See: [PyNumberMethods.nb_inplace_true_divide](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_true_divide)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject` |
| Mut / raising | `fn(mut self: T, other: PythonObject) raises -> PythonObject` |

### def_ifloordiv[method]()

Installs `nb_inplace_floor_divide` — called by `obj //= other`.

See: [PyNumberMethods.nb_inplace_floor_divide](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_floor_divide)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject` |
| Mut / raising | `fn(mut self: T, other: PythonObject) raises -> PythonObject` |

### def_imod[method]()

Installs `nb_inplace_remainder` — called by `obj %= other`.

See: [PyNumberMethods.nb_inplace_remainder](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_remainder)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject` |
| Mut / raising | `fn(mut self: T, other: PythonObject) raises -> PythonObject` |

### def_ilshift[method]()

Installs `nb_inplace_lshift` — called by `obj <<= other`.

See: [PyNumberMethods.nb_inplace_lshift](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_lshift)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject` |
| Mut / raising | `fn(mut self: T, other: PythonObject) raises -> PythonObject` |

### def_irshift[method]()

Installs `nb_inplace_rshift` — called by `obj >>= other`.

See: [PyNumberMethods.nb_inplace_rshift](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_rshift)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject` |
| Mut / raising | `fn(mut self: T, other: PythonObject) raises -> PythonObject` |

### def_iand[method]()

Installs `nb_inplace_and` — called by `obj &= other`.

See: [PyNumberMethods.nb_inplace_and](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_and)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject` |
| Mut / raising | `fn(mut self: T, other: PythonObject) raises -> PythonObject` |

### def_ior[method]()

Installs `nb_inplace_or` — called by `obj |= other`.

See: [PyNumberMethods.nb_inplace_or](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_or)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject` |
| Mut / raising | `fn(mut self: T, other: PythonObject) raises -> PythonObject` |

### def_ixor[method]()

Installs `nb_inplace_xor` — called by `obj ^= other`.

See: [PyNumberMethods.nb_inplace_xor](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_xor)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject` |
| Mut / raising | `fn(mut self: T, other: PythonObject) raises -> PythonObject` |

### def_imatmul[method]()

Installs `nb_inplace_matrix_multiply` — called by `obj @= other`.

See: [PyNumberMethods.nb_inplace_matrix_multiply](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_matrix_multiply)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> PythonObject` |
| Mut / raising | `fn(mut self: T, other: PythonObject) raises -> PythonObject` |

---

## In-place ternary operators

### def_ipow[method]()

Installs `nb_inplace_power` — called by `obj **= exp`.

See: [PyNumberMethods.nb_inplace_power](https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_power)

| Overload | Handler signature |
|----------|-------------------|
| Pointer / raising | `fn(self: UnsafePointer[T, MutAnyOrigin], exp: PythonObject, mod: PythonObject) raises -> PythonObject` |
| Mut / raising | `fn(mut self: T, exp: PythonObject, mod: PythonObject) raises -> PythonObject` |
