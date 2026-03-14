# `BufferProtocolBuilder[T]`

```mojo
struct BufferProtocolBuilder[self_type: ImplicitlyDestructible]
```

Wraps a `PythonTypeBuilder` reference and installs CPython buffer protocol slots (`bf_getbuffer` / `bf_releasebuffer`), enabling zero-copy access from `memoryview`, `numpy.frombuffer`, `bytes()`, and any other buffer consumer.

Only **1-D C-contiguous buffers** are supported.

---

## Constructor

```mojo
def __init__(out self, mut inner: PythonTypeBuilder)
```

Takes a mutable reference to the `PythonTypeBuilder` returned by `b.add_type[T](...)`. Both the module builder and the protocol builder must remain alive for the duration of the `PyInit_*` function — which is naturally satisfied when used within a single function body.

---

## Methods

### `def_getbuffer[method]()`

```mojo
def def_getbuffer[
    method: fn(UnsafePointer[T, MutAnyOrigin], Int32) raises -> BufferInfo
](mut self) -> ref[self] Self
```

Installs `bf_getbuffer`.  Called by Python whenever a consumer requests a buffer view (e.g. `memoryview(obj)`, `numpy.frombuffer(obj)`, `bytes(obj)`).

| Parameter | Description |
|-----------|-------------|
| `method`  | Static method `fn(self_ptr, flags) raises -> BufferInfo` |

The `flags` argument is the bitmask passed by the consumer:

| Flag constant | Value | Meaning |
|---------------|-------|---------|
| `PyBUF_WRITABLE` | `0x0001` | Consumer needs write access |
| `PyBUF_FORMAT`   | `0x0004` | Consumer needs the format string |
| `PyBUF_ND`       | `0x0008` | Consumer needs shape |
| `PyBUF_STRIDES`  | `0x0018` | Consumer needs strides |

Raise any `Error` from `method` to propagate a Python `BufferError` to the consumer.

See: <https://docs.python.org/3/c-api/typeobj.html#c.PyBufferProcs.bf_getbuffer>

### `def_releasebuffer()`

```mojo
def def_releasebuffer(mut self) -> ref[self] Self
```

Installs the default `bf_releasebuffer` implementation, which frees the shape/strides/format block that `def_getbuffer` allocates per view.

Always call `def_releasebuffer()` after `def_getbuffer()`.

See: <https://docs.python.org/3/c-api/typeobj.html#c.PyBufferProcs.bf_releasebuffer>

---

## `BufferInfo`

```mojo
struct BufferInfo
```

User-friendly buffer descriptor returned by the `bf_getbuffer` handler.

| Field | Type | Description |
|-------|------|-------------|
| `buf` | `UnsafePointer[UInt8, MutAnyOrigin]` | Pointer to the first byte of data |
| `nitems` | `Int` | Number of elements |
| `itemsize` | `Int` | Bytes per element |
| `format` | `String` | Python struct format code (`"d"`, `"f"`, `"i"`, `"B"`, …) |
| `readonly` | `Bool` | `True` if the buffer is read-only (default `True`) |

The `buf` pointer must remain valid until the matching `bf_releasebuffer` is called.  Do **not** resize the backing allocation while a buffer view is active.

---

## Full example

```mojo
from pontoneer import BufferProtocolBuilder, BufferInfo

struct FloatBuffer(Defaultable, Movable, Writable):
    var data: List[Float64]

    fn __init__(out self):
        self.data = []

    @staticmethod
    fn get_buffer(
        self_ptr: UnsafePointer[Self, MutAnyOrigin], flags: Int32
    ) raises -> BufferInfo:
        return BufferInfo(
            buf=rebind[UnsafePointer[UInt8, MutAnyOrigin]](
                self_ptr[].data.unsafe_ptr()
            ),
            nitems=len(self_ptr[].data),
            itemsize=8,   # sizeof(Float64)
            format="d",   # C double
            readonly=True,
        )

    fn write_to(self, mut writer: Some[Writer]):
        writer.write("FloatBuffer(len=", len(self.data), ")")

# In PyInit_*:
ref tb = b.add_type[FloatBuffer]("FloatBuffer")
    .def_init_defaultable[FloatBuffer]()
BufferProtocolBuilder[FloatBuffer](tb)
    .def_getbuffer[FloatBuffer.get_buffer]()
    .def_releasebuffer()
```

Python side:

```python
import numpy as np
buf = FloatBuffer()
# ... populate buf ...
arr = np.frombuffer(buf, dtype=np.float64)
mv  = memoryview(buf)
```

---

## Handler signature table

| Slot | Handler signature |
|------|-------------------|
| `bf_getbuffer` | `fn(self_ptr: UnsafePointer[T, MutAnyOrigin], flags: Int32) raises -> BufferInfo` |

---

## Common format codes

| Format | C type | `itemsize` |
|--------|--------|-----------|
| `"b"` | `signed char` | 1 |
| `"B"` | `unsigned char` | 1 |
| `"h"` | `short` | 2 |
| `"H"` | `unsigned short` | 2 |
| `"i"` | `int` | 4 |
| `"I"` | `unsigned int` | 4 |
| `"l"` | `long` | 4 or 8 |
| `"q"` | `long long` | 8 |
| `"f"` | `float` | 4 |
| `"d"` | `double` | 8 |

See the full list in the [Python struct documentation](https://docs.python.org/3/library/struct.html#format-characters).
