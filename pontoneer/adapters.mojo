# ===----------------------------------------------------------------------=== #
# CPython slot adapter functions introduced in:
# https://github.com/modular/modular/pull/5562
#
# These adapt user-friendly Mojo function signatures to the low-level C ABI
# expected by each CPython type slot.  They are passed to
# PontoneerTypeBuilder.def_method as template parameters.
# ===----------------------------------------------------------------------=== #

from std.ffi import c_int, c_long
from std.memory import OpaquePointer, UnsafePointer
from std.os import abort
from std.python import Python, PythonObject
from std.python._cpython import PyObject, PyObjectPtr, Py_ssize_t, PyType_Slot
from std.python.bindings import PythonTypeBuilder
from std.python.conversions import ConvertibleToPython
from std.utils import Variant

from .utils import NotImplementedError
from .slots import _PySlotIndex


@always_inline
def _unwrap_self[
    T: ImplicitlyDestructible
](py_self: PyObjectPtr) -> UnsafePointer[T, MutAnyOrigin]:
    """Downcast a raw PyObjectPtr to a typed Mojo pointer, aborting on failure.
    """
    try:
        return PythonObject(from_borrowed=py_self).downcast_value_ptr[T]()
    except e:
        abort(
            String("Python method receiver did not have the expected type: ", e)
        )


def _mp_length_wrapper[
    self_type: ImplicitlyDestructible,
    method: def(UnsafePointer[self_type, MutAnyOrigin]) thin raises -> Int,
](py_self: PyObjectPtr) abi("C") -> Py_ssize_t:
    """CPython `lenfunc` adapter for the `mp_length` slot (__len__).

    Parameters:
        self_type: The Mojo struct type whose instances back the Python object.
        method: User function `def(self: UnsafePointer[self_type, MutAnyOrigin]) raises -> Int`.

    Returns:
        Length as `Py_ssize_t`, or -1 with an exception set on error.
    """
    ref cpython = Python().cpython()
    try:
        var result = method(_unwrap_self[self_type](py_self))
        return Py_ssize_t(result)
    except e:
        var error_type = cpython.get_error_global("PyExc_Exception")
        var msg = String(e)
        cpython.PyErr_SetString(
            error_type, msg.as_c_string_slice().unsafe_ptr()
        )
        return Py_ssize_t(-1)


def _mp_subscript_wrapper[
    self_type: ImplicitlyDestructible,
    method: def(
        UnsafePointer[self_type, MutAnyOrigin], PythonObject
    ) thin raises -> PythonObject,
](py_self: PyObjectPtr, key: PyObjectPtr) abi("C") -> PyObjectPtr:
    """CPython `binaryfunc` adapter for the `mp_subscript` slot (__getitem__).

    Parameters:
        self_type: The Mojo struct type whose instances back the Python object.
        method: User function `def(self: UnsafePointer[self_type, MutAnyOrigin], key: PythonObject) raises -> PythonObject`.

    Returns:
        New reference to the result, or null with an exception set on error.
    """
    ref cpython = Python().cpython()
    try:
        var result = method(
            _unwrap_self[self_type](py_self),
            PythonObject(from_borrowed=key),
        )
        return result.steal_data()
    except e:
        var error_type = cpython.get_error_global("PyExc_Exception")
        var msg = String(e)
        cpython.PyErr_SetString(
            error_type, msg.as_c_string_slice().unsafe_ptr()
        )
        return PyObjectPtr()


def _mp_ass_subscript_wrapper[
    self_type: ImplicitlyDestructible,
    method: def(
        UnsafePointer[self_type, MutAnyOrigin],
        PythonObject,
        Variant[PythonObject, Int],
    ) thin raises -> None,
](py_self: PyObjectPtr, key: PyObjectPtr, value: PyObjectPtr) abi("C") -> c_int:
    """CPython `objobjargproc` adapter for the `mp_ass_subscript` slot.

    When `value` is NULL the operation is a deletion (__delitem__); the `method`
    receives `Variant[PythonObject, Int](Int(0))` as the third argument.
    Otherwise the operation is an assignment (__setitem__) and `method` receives
    `Variant[PythonObject, Int](value_object)`.

    Parameters:
        self_type: The Mojo struct type whose instances back the Python object.
        method: User function with signature
            `def(self, key, value: Variant[PythonObject, Int]) raises -> None`.

    Returns:
        0 on success, -1 with an exception set on error.
    """
    comptime PassedValue = Variant[PythonObject, Int]
    ref cpython = Python().cpython()
    try:
        var passed_value = PassedValue(
            PythonObject(from_borrowed=value)
        ) if value else PassedValue(Int(0))
        method(
            _unwrap_self[self_type](py_self),
            PythonObject(from_borrowed=key),
            passed_value,
        )
        return c_int(0)
    except e:
        var error_type = cpython.get_error_global("PyExc_Exception")
        var msg = String(e)
        cpython.PyErr_SetString(
            error_type, msg.as_c_string_slice().unsafe_ptr()
        )
        return c_int(-1)


def _unaryfunc_wrapper[
    self_type: ImplicitlyDestructible,
    method: def(
        UnsafePointer[self_type, MutAnyOrigin]
    ) thin raises -> PythonObject,
](py_self: PyObjectPtr) abi("C") -> PyObjectPtr:
    """CPython `unaryfunc` adapter for unary nb_ slots (__neg__, __abs__, etc.).

    Parameters:
        self_type: The Mojo struct type whose instances back the Python object.
        method: User function `def(self: UnsafePointer[self_type, MutAnyOrigin]) raises -> PythonObject`.

    Returns:
        New reference to the result, or null with an exception set on error.
    """
    ref cpython = Python().cpython()
    try:
        var result = method(_unwrap_self[self_type](py_self))
        return result.steal_data()
    except e:
        var error_type = cpython.get_error_global("PyExc_Exception")
        var msg = String(e)
        cpython.PyErr_SetString(
            error_type, msg.as_c_string_slice().unsafe_ptr()
        )
        return PyObjectPtr()


def _binaryfunc_wrapper[
    self_type: ImplicitlyDestructible,
    method: def(
        UnsafePointer[self_type, MutAnyOrigin], PythonObject
    ) thin raises -> PythonObject,
](lhs: PyObjectPtr, rhs: PyObjectPtr) abi("C") -> PyObjectPtr:
    """CPython `binaryfunc` adapter for binary nb_ slots (__add__, __mul__, etc.).

    If `method` raises `NotImplementedError` (by name), the wrapper returns
    `Py_NotImplemented`, signalling Python to try the reflected operation.

    Parameters:
        self_type: The Mojo struct type whose instances back the Python object.
        method: User function
            `def(self: UnsafePointer[self_type, MutAnyOrigin], other: PythonObject) raises -> PythonObject`.

    Returns:
        New reference to the result, `Py_NotImplemented`, or null on error.
    """
    ref cpython = Python().cpython()
    try:
        var result = method(
            _unwrap_self[self_type](lhs),
            PythonObject(from_borrowed=rhs),
        )
        return result.steal_data()
    except e:
        var msg = String(e)
        if NotImplementedError.name == msg:
            var not_implemented = cpython.lib.call[
                "Py_GetConstantBorrowed", PyObjectPtr
            ](4)
            return cpython.Py_NewRef(not_implemented)
        var error_type = cpython.get_error_global("PyExc_Exception")
        cpython.PyErr_SetString(
            error_type, msg.as_c_string_slice().unsafe_ptr()
        )
        return PyObjectPtr()


def _ternaryfunc_wrapper[
    self_type: ImplicitlyDestructible,
    method: def(
        UnsafePointer[self_type, MutAnyOrigin], PythonObject, PythonObject
    ) thin raises -> PythonObject,
](py_self: PyObjectPtr, other: PyObjectPtr, mod: PyObjectPtr) abi(
    "C"
) -> PyObjectPtr:
    """CPython `ternaryfunc` adapter for nb_power / nb_inplace_power (__pow__).

    If `method` raises `NotImplementedError` (by name), the wrapper returns
    `Py_NotImplemented`, signalling Python to try the reflected operation.

    Parameters:
        self_type: The Mojo struct type whose instances back the Python object.
        method: User function
            `def(self, other, mod: PythonObject) raises -> PythonObject`
            where `mod` is typically `None` unless the three-argument form
            `pow(base, exp, mod)` is used.

    Returns:
        New reference to the result, `Py_NotImplemented`, or null on error.
    """
    ref cpython = Python().cpython()
    try:
        var result = method(
            _unwrap_self[self_type](py_self),
            PythonObject(from_borrowed=other),
            PythonObject(from_borrowed=mod),
        )
        return result.steal_data()
    except e:
        var msg = String(e)
        if NotImplementedError.name == msg:
            var not_implemented = cpython.lib.call[
                "Py_GetConstantBorrowed", PyObjectPtr
            ](4)
            return cpython.Py_NewRef(not_implemented)
        var error_type = cpython.get_error_global("PyExc_Exception")
        cpython.PyErr_SetString(
            error_type, msg.as_c_string_slice().unsafe_ptr()
        )
        return PyObjectPtr()


def _inquiry_wrapper[
    self_type: ImplicitlyDestructible,
    method: def(UnsafePointer[self_type, MutAnyOrigin]) thin raises -> Bool,
](py_self: PyObjectPtr) abi("C") -> c_int:
    """CPython `inquiry` adapter for the `nb_bool` slot (__bool__).

    Parameters:
        self_type: The Mojo struct type whose instances back the Python object.
        method: User function `def(self: UnsafePointer[self_type, MutAnyOrigin]) raises -> Bool`.

    Returns:
        1 for True, 0 for False, -1 with an exception set on error.
    """
    ref cpython = Python().cpython()
    try:
        var result = method(_unwrap_self[self_type](py_self))
        return c_int(1) if result else c_int(0)
    except e:
        var error_type = cpython.get_error_global("PyExc_Exception")
        var msg = String(e)
        cpython.PyErr_SetString(
            error_type, msg.as_c_string_slice().unsafe_ptr()
        )
        return c_int(-1)


def _ssizeargfunc_wrapper[
    self_type: ImplicitlyDestructible,
    method: def(
        UnsafePointer[self_type, MutAnyOrigin], Int
    ) thin raises -> PythonObject,
](py_self: PyObjectPtr, index: Py_ssize_t) abi("C") -> PyObjectPtr:
    """CPython `ssizeargfunc` adapter for sq_item, sq_repeat, sq_inplace_repeat.

    Parameters:
        self_type: The Mojo struct type whose instances back the Python object.
        method: User function `def(self: UnsafePointer[self_type, MutAnyOrigin], index: Int) raises -> PythonObject`.

    Returns:
        New reference to the result, or null with an exception set on error.
    """
    ref cpython = Python().cpython()
    try:
        var result = method(_unwrap_self[self_type](py_self), Int(index))
        return result.steal_data()
    except e:
        var error_type = cpython.get_error_global("PyExc_Exception")
        var msg = String(e)
        cpython.PyErr_SetString(
            error_type, msg.as_c_string_slice().unsafe_ptr()
        )
        return PyObjectPtr()


def _ssizeobjargproc_wrapper[
    self_type: ImplicitlyDestructible,
    method: def(
        UnsafePointer[self_type, MutAnyOrigin], Int, Variant[PythonObject, Int]
    ) thin raises -> None,
](py_self: PyObjectPtr, index: Py_ssize_t, value: PyObjectPtr) abi(
    "C"
) -> c_int:
    """CPython `ssizeobjargproc` adapter for the `sq_ass_item` slot.

    When `value` is NULL the operation is a deletion; the `method` receives
    `Variant[PythonObject, Int](Int(0))` as the third argument.  Otherwise
    the operation is an assignment and `method` receives the value object.

    Parameters:
        self_type: The Mojo struct type whose instances back the Python object.
        method: User function with signature
            `def(self, index: Int, value: Variant[PythonObject, Int]) raises -> None`.

    Returns:
        0 on success, -1 with an exception set on error.
    """
    comptime PassedValue = Variant[PythonObject, Int]
    ref cpython = Python().cpython()
    try:
        var passed_value = PassedValue(
            PythonObject(from_borrowed=value)
        ) if value else PassedValue(Int(0))
        method(_unwrap_self[self_type](py_self), Int(index), passed_value)
        return c_int(0)
    except e:
        var error_type = cpython.get_error_global("PyExc_Exception")
        var msg = String(e)
        cpython.PyErr_SetString(
            error_type, msg.as_c_string_slice().unsafe_ptr()
        )
        return c_int(-1)


def _objobjproc_wrapper[
    self_type: ImplicitlyDestructible,
    method: def(
        UnsafePointer[self_type, MutAnyOrigin], PythonObject
    ) thin raises -> Bool,
](py_self: PyObjectPtr, other: PyObjectPtr) abi("C") -> c_int:
    """CPython `objobjproc` adapter for the `sq_contains` slot (__contains__).

    Parameters:
        self_type: The Mojo struct type whose instances back the Python object.
        method: User function `def(self: UnsafePointer[self_type, MutAnyOrigin], item: PythonObject) raises -> Bool`.

    Returns:
        1 if contained, 0 if not, -1 with an exception set on error.
    """
    ref cpython = Python().cpython()
    try:
        var result = method(
            _unwrap_self[self_type](py_self),
            PythonObject(from_borrowed=other),
        )
        return c_int(1) if result else c_int(0)
    except e:
        var error_type = cpython.get_error_global("PyExc_Exception")
        var msg = String(e)
        cpython.PyErr_SetString(
            error_type, msg.as_c_string_slice().unsafe_ptr()
        )
        return c_int(-1)


def _richcompare_wrapper[
    self_type: ImplicitlyDestructible,
    method: def(
        UnsafePointer[self_type, MutAnyOrigin], PythonObject, Int
    ) thin raises -> Bool,
](py_self: PyObjectPtr, py_other: PyObjectPtr, op: c_int) abi(
    "C"
) -> PyObjectPtr:
    """CPython `richcmpfunc` adapter for the `tp_richcompare` slot.

    If `method` raises `NotImplementedError` (by name), the wrapper returns
    `Py_NotImplemented`, signalling Python to try the reflected operation.
    Any other exception sets a Python exception and returns null.

    Parameters:
        self_type: The Mojo struct type whose instances back the Python object.
        method: User function
            `def(self, other: PythonObject, op: Int) raises -> Bool`
            where `op` is one of `RichCompareOps.Py_LT` … `Py_GE`.

    Returns:
        `Py_True`/`Py_False`, `Py_NotImplemented`, or null on error.
    """
    ref cpython = Python().cpython()
    try:
        var result = method(
            _unwrap_self[self_type](py_self),
            PythonObject(from_borrowed=py_other),
            Int(op),
        )
        return cpython.PyBool_FromLong(c_long(Int(result)))
    except e:
        # Mojo lacks multiple except branches; dispatch on the error name.
        var msg = String(e)
        if NotImplementedError.name == msg:
            # Py_CONSTANT_NOT_IMPLEMENTED = 4 (CPython 3.13+ stable ABI)
            var not_implemented = cpython.lib.call[
                "Py_GetConstantBorrowed", PyObjectPtr
            ](4)
            return cpython.Py_NewRef(not_implemented)
        var error_type = cpython.get_error_global("PyExc_Exception")
        cpython.PyErr_SetString(
            error_type, msg.as_c_string_slice().unsafe_ptr()
        )
        return PyObjectPtr()


# ===----------------------------------------------------------------------=== #
# Slot-install helpers and calling-convention lift/conversion wrappers.
#
# These adapt user handler signatures (pointer-, value-, or mut-receiver;
# raising or non-raising; PythonObject- or ConvertibleToPython-returning) to
# the raising pointer-receiver shape the C-ABI adapters expect, and insert the
# resulting C function pointer into a PythonTypeBuilder slot.  Shared by all
# four protocol builders.  Internal: not re-exported from `__init__.mojo`.
# ===----------------------------------------------------------------------=== #


def _install_unary[
    self_type: ImplicitlyDestructible,
    method: def(
        UnsafePointer[self_type, MutAnyOrigin]
    ) thin raises -> PythonObject,
    slot: Int32,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `unaryfunc` slot into the builder pointed to by `ptr`."""
    comptime _unaryfunc = def(PyObjectPtr) thin abi("C") -> PyObjectPtr
    var fn_ptr: _unaryfunc = _unaryfunc_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(slot, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr))
    )


def _install_binary[
    self_type: ImplicitlyDestructible,
    method: def(
        UnsafePointer[self_type, MutAnyOrigin], PythonObject
    ) thin raises -> PythonObject,
    slot: Int32,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `binaryfunc` slot into the builder pointed to by `ptr`."""
    comptime _binaryfunc = def(PyObjectPtr, PyObjectPtr) thin abi(
        "C"
    ) -> PyObjectPtr
    var fn_ptr: _binaryfunc = _binaryfunc_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(slot, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr))
    )


def _install_ternary[
    self_type: ImplicitlyDestructible,
    method: def(
        UnsafePointer[self_type, MutAnyOrigin], PythonObject, PythonObject
    ) thin raises -> PythonObject,
    slot: Int32,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `ternaryfunc` slot into the builder pointed to by `ptr`."""
    comptime _ternaryfunc = def(PyObjectPtr, PyObjectPtr, PyObjectPtr) thin abi(
        "C"
    ) -> PyObjectPtr
    var fn_ptr: _ternaryfunc = _ternaryfunc_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(slot, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr))
    )


def _install_inquiry[
    self_type: ImplicitlyDestructible,
    method: def(UnsafePointer[self_type, MutAnyOrigin]) thin raises -> Bool,
    slot: Int32,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert an `inquiry` slot into the builder pointed to by `ptr`."""
    comptime _inquiry = def(PyObjectPtr) thin abi("C") -> c_int
    var fn_ptr: _inquiry = _inquiry_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(slot, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr))
    )


def _install_richcompare[
    self_type: ImplicitlyDestructible,
    method: def(
        UnsafePointer[self_type, MutAnyOrigin], PythonObject, Int
    ) thin raises -> Bool,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `richcmpfunc` slot (`tp_richcompare`) into the builder pointed to by `ptr`.
    """
    # Assign to a typed variable first so the compiler concretizes the
    # parameterized function into a plain C function pointer before rebind.
    comptime _richcmpfunc = def(PyObjectPtr, PyObjectPtr, c_int) thin abi(
        "C"
    ) -> PyObjectPtr
    var fn_ptr: _richcmpfunc = _richcompare_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(
            _PySlotIndex.tp_richcompare,
            rebind[OpaquePointer[MutAnyOrigin]](fn_ptr),
        )
    )


def _install_lenfunc[
    self_type: ImplicitlyDestructible,
    method: def(UnsafePointer[self_type, MutAnyOrigin]) thin raises -> Int,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `lenfunc` slot (`mp_length`) into the builder pointed to by `ptr`.
    """
    comptime _lenfunc = def(PyObjectPtr) thin abi("C") -> Py_ssize_t
    var fn_ptr: _lenfunc = _mp_length_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(
            _PySlotIndex.mp_length, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr)
        )
    )


def _install_mp_getitem[
    self_type: ImplicitlyDestructible,
    method: def(
        UnsafePointer[self_type, MutAnyOrigin], PythonObject
    ) thin raises -> PythonObject,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `binaryfunc` slot (`mp_subscript`) into the builder pointed to by `ptr`.
    """
    comptime _binaryfunc = def(PyObjectPtr, PyObjectPtr) thin abi(
        "C"
    ) -> PyObjectPtr
    var fn_ptr: _binaryfunc = _mp_subscript_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(
            _PySlotIndex.mp_getitem, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr)
        )
    )


def _install_objobjargproc[
    self_type: ImplicitlyDestructible,
    method: def(
        UnsafePointer[self_type, MutAnyOrigin],
        PythonObject,
        Variant[PythonObject, Int],
    ) thin raises -> None,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert an `objobjargproc` slot (`mp_ass_subscript`) into the builder pointed to by `ptr`.
    """
    comptime _objobjargproc = def(
        PyObjectPtr, PyObjectPtr, PyObjectPtr
    ) thin abi("C") -> c_int
    var fn_ptr: _objobjargproc = _mp_ass_subscript_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(
            _PySlotIndex.mp_setitem, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr)
        )
    )


def _install_ssizeargfunc[
    self_type: ImplicitlyDestructible,
    method: def(
        UnsafePointer[self_type, MutAnyOrigin], Int
    ) thin raises -> PythonObject,
    slot: Int32,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `ssizeargfunc` slot into the builder pointed to by `ptr`."""
    comptime _ssizeargfunc = def(PyObjectPtr, Py_ssize_t) thin abi(
        "C"
    ) -> PyObjectPtr
    var fn_ptr: _ssizeargfunc = _ssizeargfunc_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(slot, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr))
    )


def _install_ssizeobjargproc[
    self_type: ImplicitlyDestructible,
    method: def(
        UnsafePointer[self_type, MutAnyOrigin], Int, Variant[PythonObject, Int]
    ) thin raises -> None,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert the `ssizeobjargproc` slot (`sq_ass_item`) into the builder pointed to by `ptr`.
    """
    comptime _ssizeobjargproc = def(
        PyObjectPtr, Py_ssize_t, PyObjectPtr
    ) thin abi("C") -> c_int
    var fn_ptr: _ssizeobjargproc = _ssizeobjargproc_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(
            _PySlotIndex.sq_ass_item,
            rebind[OpaquePointer[MutAnyOrigin]](fn_ptr),
        )
    )


def _install_objobjproc[
    self_type: ImplicitlyDestructible,
    method: def(
        UnsafePointer[self_type, MutAnyOrigin], PythonObject
    ) thin raises -> Bool,
    slot: Int32,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert an `objobjproc` slot into the builder pointed to by `ptr`."""
    comptime _objobjproc = def(PyObjectPtr, PyObjectPtr) thin abi("C") -> c_int
    var fn_ptr: _objobjproc = _objobjproc_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(slot, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr))
    )


# ===----------------------------------------------------------------------=== #
# Non-raising → raising lift helpers
#
# Each wraps a non-raising user function in a raising function so the same
# _install_* / adapter infrastructure can be used for both calling conventions.
# ===----------------------------------------------------------------------=== #


def _lift_to_int[
    T: ImplicitlyDestructible,
    method: def(UnsafePointer[T, MutAnyOrigin]) thin -> Int,
](ptr: UnsafePointer[T, MutAnyOrigin]) raises -> Int:
    return method(ptr)


def _lift_to_obj[
    T: ImplicitlyDestructible,
    method: def(UnsafePointer[T, MutAnyOrigin]) thin -> PythonObject,
](ptr: UnsafePointer[T, MutAnyOrigin]) raises -> PythonObject:
    return method(ptr)


def _lift_to_bool[
    T: ImplicitlyDestructible,
    method: def(UnsafePointer[T, MutAnyOrigin]) thin -> Bool,
](ptr: UnsafePointer[T, MutAnyOrigin]) raises -> Bool:
    return method(ptr)


def _lift_obj_to_obj[
    T: ImplicitlyDestructible,
    method: def(
        UnsafePointer[T, MutAnyOrigin], PythonObject
    ) thin -> PythonObject,
](
    ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject
) raises -> PythonObject:
    return method(ptr, other)


def _lift_obj_to_bool[
    T: ImplicitlyDestructible,
    method: def(UnsafePointer[T, MutAnyOrigin], PythonObject) thin -> Bool,
](ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> Bool:
    return method(ptr, other)


def _lift_obj_var_to_none[
    T: ImplicitlyDestructible,
    method: def(
        UnsafePointer[T, MutAnyOrigin], PythonObject, Variant[PythonObject, Int]
    ) thin -> None,
](
    ptr: UnsafePointer[T, MutAnyOrigin],
    key: PythonObject,
    val: Variant[PythonObject, Int],
) raises -> None:
    method(ptr, key, val)


def _lift_int_to_obj[
    T: ImplicitlyDestructible,
    method: def(UnsafePointer[T, MutAnyOrigin], Int) thin -> PythonObject,
](ptr: UnsafePointer[T, MutAnyOrigin], index: Int) raises -> PythonObject:
    return method(ptr, index)


def _lift_int_var_to_none[
    T: ImplicitlyDestructible,
    method: def(
        UnsafePointer[T, MutAnyOrigin], Int, Variant[PythonObject, Int]
    ) thin -> None,
](
    ptr: UnsafePointer[T, MutAnyOrigin],
    index: Int,
    val: Variant[PythonObject, Int],
) raises -> None:
    method(ptr, index, val)


def _lift_obj_int_to_bool[
    T: ImplicitlyDestructible,
    method: def(UnsafePointer[T, MutAnyOrigin], PythonObject, Int) thin -> Bool,
](
    ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject, op: Int
) raises -> Bool:
    return method(ptr, other, op)


def _lift_obj_obj_to_obj[
    T: ImplicitlyDestructible,
    method: def(
        UnsafePointer[T, MutAnyOrigin], PythonObject, PythonObject
    ) thin -> PythonObject,
](
    ptr: UnsafePointer[T, MutAnyOrigin], a: PythonObject, b: PythonObject
) raises -> PythonObject:
    return method(ptr, a, b)


# ===----------------------------------------------------------------------=== #
# Value-receiver → pointer-receiver lift helpers
#
# These wrap user functions that take `T` by value (typical struct methods)
# into the `def(UnsafePointer[T, MutAnyOrigin]) raises -> R` shape expected
# by the _install_* helpers.
#
# Unlike pointer-receiver functions, Mojo coerces def(T) -> R to match
# def(T) raises -> R at the call site, so a single raising wrapper covers
# both raising and non-raising value-receiver methods.
# ===----------------------------------------------------------------------=== #


def _lift_val_to_int[
    T: ImplicitlyDestructible,
    method: def(T) thin raises -> Int,
](ptr: UnsafePointer[T, MutAnyOrigin]) raises -> Int:
    return method(ptr[])


def _lift_val_to_obj[
    T: ImplicitlyDestructible,
    method: def(T) thin raises -> PythonObject,
](ptr: UnsafePointer[T, MutAnyOrigin]) raises -> PythonObject:
    return method(ptr[])


def _lift_val_to_bool[
    T: ImplicitlyDestructible,
    method: def(T) thin raises -> Bool,
](ptr: UnsafePointer[T, MutAnyOrigin]) raises -> Bool:
    return method(ptr[])


def _lift_val_obj_to_obj[
    T: ImplicitlyDestructible,
    method: def(T, PythonObject) thin raises -> PythonObject,
](
    ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject
) raises -> PythonObject:
    return method(ptr[], other)


def _lift_val_obj_to_bool[
    T: ImplicitlyDestructible,
    method: def(T, PythonObject) thin raises -> Bool,
](ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> Bool:
    return method(ptr[], other)


def _lift_val_obj_var_to_none[
    T: ImplicitlyDestructible,
    method: def(
        T, PythonObject, Variant[PythonObject, Int]
    ) thin raises -> None,
](
    ptr: UnsafePointer[T, MutAnyOrigin],
    key: PythonObject,
    val: Variant[PythonObject, Int],
) raises -> None:
    method(ptr[], key, val)


def _lift_mut_obj_var_to_none[
    T: ImplicitlyDestructible,
    method: def(
        mut T, PythonObject, Variant[PythonObject, Int]
    ) thin raises -> None,
](
    ptr: UnsafePointer[T, MutAnyOrigin],
    key: PythonObject,
    val: Variant[PythonObject, Int],
) raises -> None:
    method(ptr[], key, val)


def _lift_val_int_to_obj[
    T: ImplicitlyDestructible,
    method: def(T, Int) thin raises -> PythonObject,
](ptr: UnsafePointer[T, MutAnyOrigin], index: Int) raises -> PythonObject:
    return method(ptr[], index)


def _lift_val_int_var_to_none[
    T: ImplicitlyDestructible,
    method: def(T, Int, Variant[PythonObject, Int]) thin raises -> None,
](
    ptr: UnsafePointer[T, MutAnyOrigin],
    index: Int,
    val: Variant[PythonObject, Int],
) raises -> None:
    method(ptr[], index, val)


def _lift_mut_int_var_to_none[
    T: ImplicitlyDestructible,
    method: def(mut T, Int, Variant[PythonObject, Int]) thin raises -> None,
](
    ptr: UnsafePointer[T, MutAnyOrigin],
    index: Int,
    val: Variant[PythonObject, Int],
) raises -> None:
    method(ptr[], index, val)


def _lift_val_obj_int_to_bool[
    T: ImplicitlyDestructible,
    method: def(T, PythonObject, Int) thin raises -> Bool,
](
    ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject, op: Int
) raises -> Bool:
    return method(ptr[], other, op)


def _lift_val_obj_obj_to_obj[
    T: ImplicitlyDestructible,
    method: def(T, PythonObject, PythonObject) thin raises -> PythonObject,
](
    ptr: UnsafePointer[T, MutAnyOrigin], a: PythonObject, b: PythonObject
) raises -> PythonObject:
    return method(ptr[], a, b)


def _lift_mut_obj_to_obj[
    T: ImplicitlyDestructible,
    method: def(mut T, PythonObject) thin raises -> PythonObject,
](
    ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject
) raises -> PythonObject:
    return method(ptr[], other)


def _lift_mut_obj_obj_to_obj[
    T: ImplicitlyDestructible,
    method: def(mut T, PythonObject, PythonObject) thin raises -> PythonObject,
](
    ptr: UnsafePointer[T, MutAnyOrigin], a: PythonObject, b: PythonObject
) raises -> PythonObject:
    return method(ptr[], a, b)


# ===----------------------------------------------------------------------=== #
# ConvertibleToPython return-type lift helpers
#
# These adapt user functions whose return type R satisfies ConvertibleToPython
# (instead of returning PythonObject directly) by calling .to_python_object().
# Three variants per C-ABI argument shape:
#   _conv_ptr_r_*   — ptr-receiver, raising    def(ptr, ...) raises -> R
#   _conv_ptr_nr_*  — ptr-receiver, non-raising def(ptr, ...) -> R
#   _conv_val_r_*   — value-receiver, raising   def(T, ...) raises -> R
#                     (Mojo coerces def(T)->R to def(T) raises->R for value types,
#                      so this single overload also covers non-raising methods.)
# ===----------------------------------------------------------------------=== #

comptime _CPython = ConvertibleToPython & ImplicitlyCopyable


def _conv_ptr_r_unary[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: def(UnsafePointer[T, MutAnyOrigin]) thin raises -> R,
](ptr: UnsafePointer[T, MutAnyOrigin]) raises -> PythonObject:
    return method(ptr).to_python_object()


def _conv_ptr_nr_unary[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: def(UnsafePointer[T, MutAnyOrigin]) thin -> R,
](ptr: UnsafePointer[T, MutAnyOrigin]) raises -> PythonObject:
    return method(ptr).to_python_object()


def _conv_val_r_unary[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: def(T) thin raises -> R,
](ptr: UnsafePointer[T, MutAnyOrigin]) raises -> PythonObject:
    return method(ptr[]).to_python_object()


def _conv_ptr_r_binary[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: def(UnsafePointer[T, MutAnyOrigin], PythonObject) thin raises -> R,
](
    ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject
) raises -> PythonObject:
    return method(ptr, other).to_python_object()


def _conv_ptr_nr_binary[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: def(UnsafePointer[T, MutAnyOrigin], PythonObject) thin -> R,
](
    ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject
) raises -> PythonObject:
    return method(ptr, other).to_python_object()


def _conv_val_r_binary[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: def(T, PythonObject) thin raises -> R,
](
    ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject
) raises -> PythonObject:
    return method(ptr[], other).to_python_object()


def _conv_ptr_r_int_arg[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: def(UnsafePointer[T, MutAnyOrigin], Int) thin raises -> R,
](ptr: UnsafePointer[T, MutAnyOrigin], index: Int) raises -> PythonObject:
    return method(ptr, index).to_python_object()


def _conv_ptr_nr_int_arg[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: def(UnsafePointer[T, MutAnyOrigin], Int) thin -> R,
](ptr: UnsafePointer[T, MutAnyOrigin], index: Int) raises -> PythonObject:
    return method(ptr, index).to_python_object()


def _conv_val_r_int_arg[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: def(T, Int) thin raises -> R,
](ptr: UnsafePointer[T, MutAnyOrigin], index: Int) raises -> PythonObject:
    return method(ptr[], index).to_python_object()


def _conv_ptr_r_ternary[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: def(
        UnsafePointer[T, MutAnyOrigin], PythonObject, PythonObject
    ) thin raises -> R,
](
    ptr: UnsafePointer[T, MutAnyOrigin], a: PythonObject, b: PythonObject
) raises -> PythonObject:
    return method(ptr, a, b).to_python_object()


def _conv_ptr_nr_ternary[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: def(
        UnsafePointer[T, MutAnyOrigin], PythonObject, PythonObject
    ) thin -> R,
](
    ptr: UnsafePointer[T, MutAnyOrigin], a: PythonObject, b: PythonObject
) raises -> PythonObject:
    return method(ptr, a, b).to_python_object()


def _conv_val_r_ternary[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: def(T, PythonObject, PythonObject) thin raises -> R,
](
    ptr: UnsafePointer[T, MutAnyOrigin], a: PythonObject, b: PythonObject
) raises -> PythonObject:
    return method(ptr[], a, b).to_python_object()
