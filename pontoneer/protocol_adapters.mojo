# ===----------------------------------------------------------------------=== #
# CPython slot adapter functions introduced in:
# https://github.com/modular/modular/pull/5562
#
# These adapt user-friendly Mojo function signatures to the low-level C ABI
# expected by each CPython type slot.  They are passed to
# PontoneerTypeBuilder.def_method as template parameters.
# ===----------------------------------------------------------------------=== #

from std.ffi import c_int, c_long
from std.python import Python, PythonObject
from std.python._cpython import PyObject, PyObjectPtr, Py_ssize_t
from std.utils import Variant

from .protocols import NotImplementedError


fn _mp_length_wrapper[
    method: fn(PythonObject) raises -> Int
](py_self: PyObjectPtr) -> Py_ssize_t:
    """CPython `lenfunc` adapter for the `mp_length` slot (__len__).

    Parameters:
        method: User function `fn(self: PythonObject) raises -> Int`.

    Returns:
        Length as `Py_ssize_t`, or -1 with an exception set on error.
    """
    ref cpython = Python().cpython()
    try:
        var result = method(PythonObject(from_borrowed=py_self))
        return Py_ssize_t(result)
    except e:
        var error_type = cpython.get_error_global("PyExc_Exception")
        var msg = String(e)
        cpython.PyErr_SetString(
            error_type, msg.as_c_string_slice().unsafe_ptr()
        )
        return Py_ssize_t(-1)


fn _mp_subscript_wrapper[
    method: fn(PythonObject, PythonObject) raises -> PythonObject
](py_self: PyObjectPtr, key: PyObjectPtr) -> PyObjectPtr:
    """CPython `binaryfunc` adapter for the `mp_subscript` slot (__getitem__).

    Parameters:
        method: User function `fn(self: PythonObject, key: PythonObject) raises -> PythonObject`.

    Returns:
        New reference to the result, or null with an exception set on error.
    """
    ref cpython = Python().cpython()
    try:
        var result = method(
            PythonObject(from_borrowed=py_self),
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


fn _mp_ass_subscript_wrapper[
    method: fn(
        PythonObject, PythonObject, Variant[PythonObject, Int]
    ) raises -> None
](py_self: PyObjectPtr, key: PyObjectPtr, value: PyObjectPtr) -> c_int:
    """CPython `objobjargproc` adapter for the `mp_ass_subscript` slot.

    When `value` is NULL the operation is a deletion (__delitem__); the `method`
    receives `Variant[PythonObject, Int](Int(0))` as the third argument.
    Otherwise the operation is an assignment (__setitem__) and `method` receives
    `Variant[PythonObject, Int](value_object)`.

    Parameters:
        method: User function with signature
            `fn(self, key, value: Variant[PythonObject, Int]) raises -> None`.

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
            PythonObject(from_borrowed=py_self),
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


fn _unaryfunc_wrapper[
    method: fn(PythonObject) raises -> PythonObject
](py_self: PyObjectPtr) -> PyObjectPtr:
    """CPython `unaryfunc` adapter for unary nb_ slots (__neg__, __abs__, etc.).

    Parameters:
        method: User function `fn(self: PythonObject) raises -> PythonObject`.

    Returns:
        New reference to the result, or null with an exception set on error.
    """
    ref cpython = Python().cpython()
    try:
        var result = method(PythonObject(from_borrowed=py_self))
        return result.steal_data()
    except e:
        var error_type = cpython.get_error_global("PyExc_Exception")
        var msg = String(e)
        cpython.PyErr_SetString(
            error_type, msg.as_c_string_slice().unsafe_ptr()
        )
        return PyObjectPtr()


fn _binaryfunc_wrapper[
    method: fn(PythonObject, PythonObject) raises -> PythonObject
](lhs: PyObjectPtr, rhs: PyObjectPtr) -> PyObjectPtr:
    """CPython `binaryfunc` adapter for binary nb_ slots (__add__, __mul__, etc.).

    If `method` raises `NotImplementedError` (by name), the wrapper returns
    `Py_NotImplemented`, signalling Python to try the reflected operation.

    Parameters:
        method: User function
            `fn(self: PythonObject, other: PythonObject) raises -> PythonObject`.

    Returns:
        New reference to the result, `Py_NotImplemented`, or null on error.
    """
    ref cpython = Python().cpython()
    try:
        var result = method(
            PythonObject(from_borrowed=lhs),
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


fn _ternaryfunc_wrapper[
    method: fn(PythonObject, PythonObject, PythonObject) raises -> PythonObject
](py_self: PyObjectPtr, other: PyObjectPtr, mod: PyObjectPtr) -> PyObjectPtr:
    """CPython `ternaryfunc` adapter for nb_power / nb_inplace_power (__pow__).

    If `method` raises `NotImplementedError` (by name), the wrapper returns
    `Py_NotImplemented`, signalling Python to try the reflected operation.

    Parameters:
        method: User function
            `fn(self, other, mod: PythonObject) raises -> PythonObject`
            where `mod` is typically `None` unless the three-argument form
            `pow(base, exp, mod)` is used.

    Returns:
        New reference to the result, `Py_NotImplemented`, or null on error.
    """
    ref cpython = Python().cpython()
    try:
        var result = method(
            PythonObject(from_borrowed=py_self),
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


fn _inquiry_wrapper[
    method: fn(PythonObject) raises -> Bool
](py_self: PyObjectPtr) -> c_int:
    """CPython `inquiry` adapter for the `nb_bool` slot (__bool__).

    Parameters:
        method: User function `fn(self: PythonObject) raises -> Bool`.

    Returns:
        1 for True, 0 for False, -1 with an exception set on error.
    """
    ref cpython = Python().cpython()
    try:
        var result = method(PythonObject(from_borrowed=py_self))
        return c_int(1) if result else c_int(0)
    except e:
        var error_type = cpython.get_error_global("PyExc_Exception")
        var msg = String(e)
        cpython.PyErr_SetString(
            error_type, msg.as_c_string_slice().unsafe_ptr()
        )
        return c_int(-1)


fn _ssizeargfunc_wrapper[
    method: fn(PythonObject, Int) raises -> PythonObject
](py_self: PyObjectPtr, index: Py_ssize_t) -> PyObjectPtr:
    """CPython `ssizeargfunc` adapter for sq_item, sq_repeat, sq_inplace_repeat.

    Parameters:
        method: User function `fn(self: PythonObject, index: Int) raises -> PythonObject`.

    Returns:
        New reference to the result, or null with an exception set on error.
    """
    ref cpython = Python().cpython()
    try:
        var result = method(PythonObject(from_borrowed=py_self), Int(index))
        return result.steal_data()
    except e:
        var error_type = cpython.get_error_global("PyExc_Exception")
        var msg = String(e)
        cpython.PyErr_SetString(
            error_type, msg.as_c_string_slice().unsafe_ptr()
        )
        return PyObjectPtr()


fn _ssizeobjargproc_wrapper[
    method: fn(PythonObject, Int, Variant[PythonObject, Int]) raises -> None
](py_self: PyObjectPtr, index: Py_ssize_t, value: PyObjectPtr) -> c_int:
    """CPython `ssizeobjargproc` adapter for the `sq_ass_item` slot.

    When `value` is NULL the operation is a deletion; the `method` receives
    `Variant[PythonObject, Int](Int(0))` as the third argument.  Otherwise
    the operation is an assignment and `method` receives the value object.

    Parameters:
        method: User function with signature
            `fn(self, index: Int, value: Variant[PythonObject, Int]) raises -> None`.

    Returns:
        0 on success, -1 with an exception set on error.
    """
    comptime PassedValue = Variant[PythonObject, Int]
    ref cpython = Python().cpython()
    try:
        var passed_value = PassedValue(
            PythonObject(from_borrowed=value)
        ) if value else PassedValue(Int(0))
        method(PythonObject(from_borrowed=py_self), Int(index), passed_value)
        return c_int(0)
    except e:
        var error_type = cpython.get_error_global("PyExc_Exception")
        var msg = String(e)
        cpython.PyErr_SetString(
            error_type, msg.as_c_string_slice().unsafe_ptr()
        )
        return c_int(-1)


fn _objobjproc_wrapper[
    method: fn(PythonObject, PythonObject) raises -> Bool
](py_self: PyObjectPtr, other: PyObjectPtr) -> c_int:
    """CPython `objobjproc` adapter for the `sq_contains` slot (__contains__).

    Parameters:
        method: User function `fn(self: PythonObject, item: PythonObject) raises -> Bool`.

    Returns:
        1 if contained, 0 if not, -1 with an exception set on error.
    """
    ref cpython = Python().cpython()
    try:
        var result = method(
            PythonObject(from_borrowed=py_self),
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


fn _richcompare_wrapper[
    method: fn(PythonObject, PythonObject, Int) raises -> Bool
](py_self: PyObjectPtr, py_other: PyObjectPtr, op: c_int) -> PyObjectPtr:
    """CPython `richcmpfunc` adapter for the `tp_richcompare` slot.

    If `method` raises `NotImplementedError` (by name), the wrapper returns
    `Py_NotImplemented`, signalling Python to try the reflected operation.
    Any other exception sets a Python exception and returns null.

    Parameters:
        method: User function
            `fn(self, other: PythonObject, op: Int) raises -> Bool`
            where `op` is one of `RichCompareOps.Py_LT` … `Py_GE`.

    Returns:
        `Py_True`/`Py_False`, `Py_NotImplemented`, or null on error.
    """
    ref cpython = Python().cpython()
    try:
        var result = method(
            PythonObject(from_borrowed=py_self),
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
