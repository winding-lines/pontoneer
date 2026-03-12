# ===----------------------------------------------------------------------=== #
# TypeProtocolBuilder — extends PythonTypeBuilder with mapping protocol and
# rich comparison slots, as proposed in:
# https://github.com/modular/modular/pull/5562
#
# NOTE: This relies on PythonTypeBuilder._insert_slot being accessible.
# The leading underscore is a naming convention; Mojo does not enforce
# module-level visibility, so the call compiles on nightly MAX.
# ===----------------------------------------------------------------------=== #

from std.ffi import c_int
from std.memory import OpaquePointer, UnsafePointer
from std.python import PythonObject
from std.python._cpython import PyObjectPtr, Py_ssize_t, PyType_Slot
from std.python.bindings import PythonTypeBuilder
from std.python.conversions import ConvertibleToPython
from std.utils import Variant

from .utils import NotImplementedError
from .adapters import (
    _mp_length_wrapper,
    _mp_subscript_wrapper,
    _mp_ass_subscript_wrapper,
    _richcompare_wrapper,
    _unaryfunc_wrapper,
    _binaryfunc_wrapper,
    _ternaryfunc_wrapper,
    _inquiry_wrapper,
    _ssizeargfunc_wrapper,
    _ssizeobjargproc_wrapper,
    _objobjproc_wrapper,
)


# CPython type slot indices — do not renumber; these are part of the stable ABI.
# ref: https://github.com/python/cpython/blob/main/Include/typeslots.h
struct _PySlotIndex:
    # Buffer protocol
    comptime bf_getbuffer = Int32(1)
    comptime bf_releasebuffer = Int32(2)
    # Mapping protocol
    comptime mp_setitem = Int32(3)  # mp_ass_subscript
    comptime mp_length = Int32(4)
    comptime mp_getitem = Int32(5)  # mp_subscript
    # Number protocol
    comptime nb_absolute = Int32(6)
    comptime nb_add = Int32(7)
    comptime nb_and = Int32(8)
    comptime nb_bool = Int32(9)
    comptime nb_divmod = Int32(10)
    comptime nb_float = Int32(11)
    comptime nb_floor_divide = Int32(12)
    comptime nb_index = Int32(13)
    comptime nb_inplace_add = Int32(14)
    comptime nb_inplace_and = Int32(15)
    comptime nb_inplace_floor_divide = Int32(16)
    comptime nb_inplace_lshift = Int32(17)
    comptime nb_inplace_multiply = Int32(18)
    comptime nb_inplace_or = Int32(19)
    comptime nb_inplace_power = Int32(20)
    comptime nb_inplace_remainder = Int32(21)
    comptime nb_inplace_rshift = Int32(22)
    comptime nb_inplace_subtract = Int32(23)
    comptime nb_inplace_true_divide = Int32(24)
    comptime nb_inplace_xor = Int32(25)
    comptime nb_int = Int32(26)
    comptime nb_invert = Int32(27)
    comptime nb_lshift = Int32(28)
    comptime nb_multiply = Int32(29)
    comptime nb_negative = Int32(30)
    comptime nb_or = Int32(31)
    comptime nb_positive = Int32(32)
    comptime nb_power = Int32(33)
    comptime nb_remainder = Int32(34)
    comptime nb_rshift = Int32(35)
    comptime nb_subtract = Int32(36)
    comptime nb_true_divide = Int32(37)
    comptime nb_xor = Int32(38)
    # Sequence protocol
    comptime sq_ass_item = Int32(39)
    comptime sq_concat = Int32(40)
    comptime sq_contains = Int32(41)
    comptime sq_inplace_concat = Int32(42)
    comptime sq_inplace_repeat = Int32(43)
    comptime sq_item = Int32(44)
    comptime sq_length = Int32(45)
    comptime sq_repeat = Int32(46)
    # Type protocol
    comptime tp_alloc = Int32(47)
    comptime tp_base = Int32(48)
    comptime tp_bases = Int32(49)
    comptime tp_call = Int32(50)
    comptime tp_clear = Int32(51)
    comptime tp_dealloc = Int32(52)
    comptime tp_del = Int32(53)
    comptime tp_descr_get = Int32(54)
    comptime tp_descr_set = Int32(55)
    comptime tp_doc = Int32(56)
    comptime tp_getattr = Int32(57)
    comptime tp_getattro = Int32(58)
    comptime tp_hash = Int32(59)
    comptime tp_init = Int32(60)
    comptime tp_is_gc = Int32(61)
    comptime tp_iter = Int32(62)
    comptime tp_iternext = Int32(63)
    comptime tp_methods = Int32(64)
    comptime tp_new = Int32(65)
    comptime tp_repr = Int32(66)
    comptime tp_richcompare = Int32(67)
    comptime tp_setattr = Int32(68)
    comptime tp_setattro = Int32(69)
    comptime tp_str = Int32(70)
    comptime tp_traverse = Int32(71)
    comptime tp_members = Int32(72)
    comptime tp_getset = Int32(73)
    comptime tp_free = Int32(74)
    comptime nb_matrix_multiply = Int32(75)
    comptime nb_inplace_matrix_multiply = Int32(76)
    # Async protocol (Python 3.5+)
    comptime am_await = Int32(77)
    comptime am_aiter = Int32(78)
    comptime am_anext = Int32(79)
    comptime tp_finalize = Int32(80)  # Python 3.5+
    comptime am_send = Int32(81)  # Python 3.10+
    comptime tp_vectorcall = Int32(82)  # Python 3.14+
    comptime tp_token = Int32(83)  # Python 3.14+


struct TypeProtocolBuilder[self_type: ImplicitlyDestructible]:
    """Wraps a `PythonTypeBuilder` reference and installs CPython type protocol slots.

    `TypeProtocolBuilder` holds a pointer to a `PythonTypeBuilder` that is
    owned by the enclosing `PythonModuleBuilder`.  The caller must ensure the
    module builder (and its type_builders list) outlives this object, which is
    naturally satisfied when both are used within the same `PyInit_*` function.

    Usage:
        ```mojo
        ref tb = b.add_type[MyStruct]("MyStruct")
            .def_init_defaultable[MyStruct]()
            .def_staticmethod[MyStruct.new]("new")
        TypeProtocolBuilder[MyStruct](tb).def_richcompare[MyStruct.rich_compare]()
        MappingProtocolBuilder[MyStruct](tb)
            .def_len[MyStruct.py__len__]()
            .def_getitem[MyStruct.py__getitem__]()
            .def_setitem[MyStruct.py__setitem__]()
        NumberProtocolBuilder[MyStruct](tb).def_neg[MyStruct.py__neg__]()
        ```
    """

    # Unsafe pointer into the module builder's type_builders list.
    # The pointed-to builder must outlive this TypeProtocolBuilder.
    var _ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]

    fn __init__(out self, mut inner: PythonTypeBuilder):
        var ptr = UnsafePointer(to=inner)
        self._ptr = ptr

    # ------------------------------------------------------------------
    # Type Protocol — tp_richcompare (__lt__, __eq__, etc.)
    # ------------------------------------------------------------------

    fn def_richcompare[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject, Int
        ) raises -> Bool
    ](mut self) -> ref[self] Self:
        """Install rich comparison via the `tp_richcompare` slot.

        Called by `obj < other`, `obj == other`, etc.

        Raise `NotImplementedError()` from `method` to return
        `Py_NotImplemented` to Python (triggering the reflected operation).

        Parameters:
            method: Static method with signature
                `fn(self_ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject, op: Int) raises -> Bool`
                where `op` is one of `RichCompareOps.Py_LT` … `Py_GE`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyTypeObject.tp_richcompare
        """
        _install_richcompare[Self.self_type, method](self._ptr)
        return self

    fn def_richcompare[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject, Int
        ) -> Bool
    ](mut self) -> ref[self] Self:
        """Install rich comparison via the `tp_richcompare` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyTypeObject.tp_richcompare
        """
        _install_richcompare[
            Self.self_type, _lift_obj_int_to_bool[Self.self_type, method]
        ](self._ptr)
        return self

    fn def_richcompare[
        method: fn(Self.self_type, PythonObject, Int) raises -> Bool
    ](mut self) -> ref[self] Self:
        """Install rich comparison via the `tp_richcompare` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyTypeObject.tp_richcompare
        """
        _install_richcompare[
            Self.self_type, _lift_val_obj_int_to_bool[Self.self_type, method]
        ](self._ptr)
        return self


# ===----------------------------------------------------------------------=== #
# Slot-install helpers — free functions usable by any builder
# ===----------------------------------------------------------------------=== #


fn _install_unary[
    self_type: ImplicitlyDestructible,
    method: fn(UnsafePointer[self_type, MutAnyOrigin]) raises -> PythonObject,
    slot: Int32,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `unaryfunc` slot into the builder pointed to by `ptr`."""
    comptime _unaryfunc = fn(PyObjectPtr) -> PyObjectPtr
    var fn_ptr: _unaryfunc = _unaryfunc_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(slot, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr))
    )


fn _install_binary[
    self_type: ImplicitlyDestructible,
    method: fn(
        UnsafePointer[self_type, MutAnyOrigin], PythonObject
    ) raises -> PythonObject,
    slot: Int32,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `binaryfunc` slot into the builder pointed to by `ptr`."""
    comptime _binaryfunc = fn(PyObjectPtr, PyObjectPtr) -> PyObjectPtr
    var fn_ptr: _binaryfunc = _binaryfunc_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(slot, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr))
    )


fn _install_ternary[
    self_type: ImplicitlyDestructible,
    method: fn(
        UnsafePointer[self_type, MutAnyOrigin], PythonObject, PythonObject
    ) raises -> PythonObject,
    slot: Int32,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `ternaryfunc` slot into the builder pointed to by `ptr`."""
    comptime _ternaryfunc = fn(
        PyObjectPtr, PyObjectPtr, PyObjectPtr
    ) -> PyObjectPtr
    var fn_ptr: _ternaryfunc = _ternaryfunc_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(slot, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr))
    )


fn _install_inquiry[
    self_type: ImplicitlyDestructible,
    method: fn(UnsafePointer[self_type, MutAnyOrigin]) raises -> Bool,
    slot: Int32,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert an `inquiry` slot into the builder pointed to by `ptr`."""
    comptime _inquiry = fn(PyObjectPtr) -> c_int
    var fn_ptr: _inquiry = _inquiry_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(slot, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr))
    )


fn _install_richcompare[
    self_type: ImplicitlyDestructible,
    method: fn(
        UnsafePointer[self_type, MutAnyOrigin], PythonObject, Int
    ) raises -> Bool,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `richcmpfunc` slot (`tp_richcompare`) into the builder pointed to by `ptr`.
    """
    # Assign to a typed variable first so the compiler concretizes the
    # parameterized function into a plain C function pointer before rebind.
    comptime _richcmpfunc = fn(PyObjectPtr, PyObjectPtr, c_int) -> PyObjectPtr
    var fn_ptr: _richcmpfunc = _richcompare_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(
            _PySlotIndex.tp_richcompare,
            rebind[OpaquePointer[MutAnyOrigin]](fn_ptr),
        )
    )


fn _install_lenfunc[
    self_type: ImplicitlyDestructible,
    method: fn(UnsafePointer[self_type, MutAnyOrigin]) raises -> Int,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `lenfunc` slot (`mp_length`) into the builder pointed to by `ptr`.
    """
    comptime _lenfunc = fn(PyObjectPtr) -> Py_ssize_t
    var fn_ptr: _lenfunc = _mp_length_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(
            _PySlotIndex.mp_length, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr)
        )
    )


fn _install_mp_getitem[
    self_type: ImplicitlyDestructible,
    method: fn(
        UnsafePointer[self_type, MutAnyOrigin], PythonObject
    ) raises -> PythonObject,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `binaryfunc` slot (`mp_subscript`) into the builder pointed to by `ptr`.
    """
    comptime _binaryfunc = fn(PyObjectPtr, PyObjectPtr) -> PyObjectPtr
    var fn_ptr: _binaryfunc = _mp_subscript_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(
            _PySlotIndex.mp_getitem, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr)
        )
    )


fn _install_objobjargproc[
    self_type: ImplicitlyDestructible,
    method: fn(
        UnsafePointer[self_type, MutAnyOrigin],
        PythonObject,
        Variant[PythonObject, Int],
    ) raises -> None,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert an `objobjargproc` slot (`mp_ass_subscript`) into the builder pointed to by `ptr`.
    """
    comptime _objobjargproc = fn(PyObjectPtr, PyObjectPtr, PyObjectPtr) -> c_int
    var fn_ptr: _objobjargproc = _mp_ass_subscript_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(
            _PySlotIndex.mp_setitem, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr)
        )
    )


fn _install_ssizeargfunc[
    self_type: ImplicitlyDestructible,
    method: fn(
        UnsafePointer[self_type, MutAnyOrigin], Int
    ) raises -> PythonObject,
    slot: Int32,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `ssizeargfunc` slot into the builder pointed to by `ptr`."""
    comptime _ssizeargfunc = fn(PyObjectPtr, Py_ssize_t) -> PyObjectPtr
    var fn_ptr: _ssizeargfunc = _ssizeargfunc_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(slot, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr))
    )


fn _install_ssizeobjargproc[
    self_type: ImplicitlyDestructible,
    method: fn(
        UnsafePointer[self_type, MutAnyOrigin], Int, Variant[PythonObject, Int]
    ) raises -> None,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert the `ssizeobjargproc` slot (`sq_ass_item`) into the builder pointed to by `ptr`.
    """
    comptime _ssizeobjargproc = fn(
        PyObjectPtr, Py_ssize_t, PyObjectPtr
    ) -> c_int
    var fn_ptr: _ssizeobjargproc = _ssizeobjargproc_wrapper[self_type, method]
    ptr[]._insert_slot(
        PyType_Slot(
            _PySlotIndex.sq_ass_item,
            rebind[OpaquePointer[MutAnyOrigin]](fn_ptr),
        )
    )


fn _install_objobjproc[
    self_type: ImplicitlyDestructible,
    method: fn(
        UnsafePointer[self_type, MutAnyOrigin], PythonObject
    ) raises -> Bool,
    slot: Int32,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert an `objobjproc` slot into the builder pointed to by `ptr`."""
    comptime _objobjproc = fn(PyObjectPtr, PyObjectPtr) -> c_int
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


fn _lift_to_int[
    T: ImplicitlyDestructible,
    method: fn(UnsafePointer[T, MutAnyOrigin]) -> Int,
](ptr: UnsafePointer[T, MutAnyOrigin]) raises -> Int:
    return method(ptr)


fn _lift_to_obj[
    T: ImplicitlyDestructible,
    method: fn(UnsafePointer[T, MutAnyOrigin]) -> PythonObject,
](ptr: UnsafePointer[T, MutAnyOrigin]) raises -> PythonObject:
    return method(ptr)


fn _lift_to_bool[
    T: ImplicitlyDestructible,
    method: fn(UnsafePointer[T, MutAnyOrigin]) -> Bool,
](ptr: UnsafePointer[T, MutAnyOrigin]) raises -> Bool:
    return method(ptr)


fn _lift_obj_to_obj[
    T: ImplicitlyDestructible,
    method: fn(UnsafePointer[T, MutAnyOrigin], PythonObject) -> PythonObject,
](
    ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject
) raises -> PythonObject:
    return method(ptr, other)


fn _lift_obj_to_bool[
    T: ImplicitlyDestructible,
    method: fn(UnsafePointer[T, MutAnyOrigin], PythonObject) -> Bool,
](ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> Bool:
    return method(ptr, other)


fn _lift_obj_var_to_none[
    T: ImplicitlyDestructible,
    method: fn(
        UnsafePointer[T, MutAnyOrigin], PythonObject, Variant[PythonObject, Int]
    ) -> None,
](
    ptr: UnsafePointer[T, MutAnyOrigin],
    key: PythonObject,
    val: Variant[PythonObject, Int],
) raises -> None:
    method(ptr, key, val)


fn _lift_int_to_obj[
    T: ImplicitlyDestructible,
    method: fn(UnsafePointer[T, MutAnyOrigin], Int) -> PythonObject,
](ptr: UnsafePointer[T, MutAnyOrigin], index: Int) raises -> PythonObject:
    return method(ptr, index)


fn _lift_int_var_to_none[
    T: ImplicitlyDestructible,
    method: fn(
        UnsafePointer[T, MutAnyOrigin], Int, Variant[PythonObject, Int]
    ) -> None,
](
    ptr: UnsafePointer[T, MutAnyOrigin],
    index: Int,
    val: Variant[PythonObject, Int],
) raises -> None:
    method(ptr, index, val)


fn _lift_obj_int_to_bool[
    T: ImplicitlyDestructible,
    method: fn(UnsafePointer[T, MutAnyOrigin], PythonObject, Int) -> Bool,
](
    ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject, op: Int
) raises -> Bool:
    return method(ptr, other, op)


fn _lift_obj_obj_to_obj[
    T: ImplicitlyDestructible,
    method: fn(
        UnsafePointer[T, MutAnyOrigin], PythonObject, PythonObject
    ) -> PythonObject,
](
    ptr: UnsafePointer[T, MutAnyOrigin], a: PythonObject, b: PythonObject
) raises -> PythonObject:
    return method(ptr, a, b)


# ===----------------------------------------------------------------------=== #
# Value-receiver → pointer-receiver lift helpers
#
# These wrap user functions that take `T` by value (typical struct methods)
# into the `fn(UnsafePointer[T, MutAnyOrigin]) raises -> R` shape expected
# by the _install_* helpers.
#
# Unlike pointer-receiver functions, Mojo coerces fn(T) -> R to match
# fn(T) raises -> R at the call site, so a single raising wrapper covers
# both raising and non-raising value-receiver methods.
# ===----------------------------------------------------------------------=== #


fn _lift_val_to_int[
    T: ImplicitlyDestructible,
    method: fn(T) raises -> Int,
](ptr: UnsafePointer[T, MutAnyOrigin]) raises -> Int:
    return method(ptr[])


fn _lift_val_to_obj[
    T: ImplicitlyDestructible,
    method: fn(T) raises -> PythonObject,
](ptr: UnsafePointer[T, MutAnyOrigin]) raises -> PythonObject:
    return method(ptr[])


fn _lift_val_to_bool[
    T: ImplicitlyDestructible,
    method: fn(T) raises -> Bool,
](ptr: UnsafePointer[T, MutAnyOrigin]) raises -> Bool:
    return method(ptr[])


fn _lift_val_obj_to_obj[
    T: ImplicitlyDestructible,
    method: fn(T, PythonObject) raises -> PythonObject,
](
    ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject
) raises -> PythonObject:
    return method(ptr[], other)


fn _lift_val_obj_to_bool[
    T: ImplicitlyDestructible,
    method: fn(T, PythonObject) raises -> Bool,
](ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject) raises -> Bool:
    return method(ptr[], other)


fn _lift_val_obj_var_to_none[
    T: ImplicitlyDestructible,
    method: fn(T, PythonObject, Variant[PythonObject, Int]) raises -> None,
](
    ptr: UnsafePointer[T, MutAnyOrigin],
    key: PythonObject,
    val: Variant[PythonObject, Int],
) raises -> None:
    method(ptr[], key, val)


fn _lift_val_int_to_obj[
    T: ImplicitlyDestructible,
    method: fn(T, Int) raises -> PythonObject,
](ptr: UnsafePointer[T, MutAnyOrigin], index: Int) raises -> PythonObject:
    return method(ptr[], index)


fn _lift_val_int_var_to_none[
    T: ImplicitlyDestructible,
    method: fn(T, Int, Variant[PythonObject, Int]) raises -> None,
](
    ptr: UnsafePointer[T, MutAnyOrigin],
    index: Int,
    val: Variant[PythonObject, Int],
) raises -> None:
    method(ptr[], index, val)


fn _lift_val_obj_int_to_bool[
    T: ImplicitlyDestructible,
    method: fn(T, PythonObject, Int) raises -> Bool,
](
    ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject, op: Int
) raises -> Bool:
    return method(ptr[], other, op)


fn _lift_val_obj_obj_to_obj[
    T: ImplicitlyDestructible,
    method: fn(T, PythonObject, PythonObject) raises -> PythonObject,
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
#   _conv_ptr_r_*   — ptr-receiver, raising    fn(ptr, ...) raises -> R
#   _conv_ptr_nr_*  — ptr-receiver, non-raising fn(ptr, ...) -> R
#   _conv_val_r_*   — value-receiver, raising   fn(T, ...) raises -> R
#                     (Mojo coerces fn(T)->R to fn(T) raises->R for value types,
#                      so this single overload also covers non-raising methods.)
# ===----------------------------------------------------------------------=== #

comptime _CPython = ConvertibleToPython & ImplicitlyCopyable


fn _conv_ptr_r_unary[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: fn(UnsafePointer[T, MutAnyOrigin]) raises -> R,
](ptr: UnsafePointer[T, MutAnyOrigin]) raises -> PythonObject:
    return method(ptr).to_python_object()


fn _conv_ptr_nr_unary[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: fn(UnsafePointer[T, MutAnyOrigin]) -> R,
](ptr: UnsafePointer[T, MutAnyOrigin]) raises -> PythonObject:
    return method(ptr).to_python_object()


fn _conv_val_r_unary[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: fn(T) raises -> R,
](ptr: UnsafePointer[T, MutAnyOrigin]) raises -> PythonObject:
    return method(ptr[]).to_python_object()


fn _conv_ptr_r_binary[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: fn(UnsafePointer[T, MutAnyOrigin], PythonObject) raises -> R,
](
    ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject
) raises -> PythonObject:
    return method(ptr, other).to_python_object()


fn _conv_ptr_nr_binary[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: fn(UnsafePointer[T, MutAnyOrigin], PythonObject) -> R,
](
    ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject
) raises -> PythonObject:
    return method(ptr, other).to_python_object()


fn _conv_val_r_binary[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: fn(T, PythonObject) raises -> R,
](
    ptr: UnsafePointer[T, MutAnyOrigin], other: PythonObject
) raises -> PythonObject:
    return method(ptr[], other).to_python_object()


fn _conv_ptr_r_int_arg[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: fn(UnsafePointer[T, MutAnyOrigin], Int) raises -> R,
](ptr: UnsafePointer[T, MutAnyOrigin], index: Int) raises -> PythonObject:
    return method(ptr, index).to_python_object()


fn _conv_ptr_nr_int_arg[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: fn(UnsafePointer[T, MutAnyOrigin], Int) -> R,
](ptr: UnsafePointer[T, MutAnyOrigin], index: Int) raises -> PythonObject:
    return method(ptr, index).to_python_object()


fn _conv_val_r_int_arg[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: fn(T, Int) raises -> R,
](ptr: UnsafePointer[T, MutAnyOrigin], index: Int) raises -> PythonObject:
    return method(ptr[], index).to_python_object()


fn _conv_ptr_r_ternary[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: fn(
        UnsafePointer[T, MutAnyOrigin], PythonObject, PythonObject
    ) raises -> R,
](
    ptr: UnsafePointer[T, MutAnyOrigin], a: PythonObject, b: PythonObject
) raises -> PythonObject:
    return method(ptr, a, b).to_python_object()


fn _conv_ptr_nr_ternary[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: fn(UnsafePointer[T, MutAnyOrigin], PythonObject, PythonObject) -> R,
](
    ptr: UnsafePointer[T, MutAnyOrigin], a: PythonObject, b: PythonObject
) raises -> PythonObject:
    return method(ptr, a, b).to_python_object()


fn _conv_val_r_ternary[
    T: ImplicitlyDestructible,
    R: _CPython,
    method: fn(T, PythonObject, PythonObject) raises -> R,
](
    ptr: UnsafePointer[T, MutAnyOrigin], a: PythonObject, b: PythonObject
) raises -> PythonObject:
    return method(ptr[], a, b).to_python_object()


# ===----------------------------------------------------------------------=== #
# NumberProtocolBuilder
# ===----------------------------------------------------------------------=== #


struct NumberProtocolBuilder[self_type: ImplicitlyDestructible]:
    """Installs CPython number protocol slots on a `PythonTypeBuilder`.

    Construct directly from a `PythonTypeBuilder`.  Each method is named after the
    corresponding Python dunder and accepts only the matching function signature.
    Handler functions receive `UnsafePointer[T, MutAnyOrigin]` as their first
    argument instead of a raw `PythonObject`.

    Binary methods (`def_add`, `def_mul`, etc.) and ternary methods (`def_pow`,
    `def_ipow`) support `NotImplementedError`: raise it from your handler to
    return `Py_NotImplemented` to Python, triggering the reflected operation.

    Usage:
        ```mojo
        var npb = NumberProtocolBuilder[MyStruct](tb)
        npb.def_neg[MyStruct.py__neg__]()
           .def_bool[MyStruct.py__bool__]()
           .def_add[MyStruct.py__add__]()
           .def_pow[MyStruct.py__pow__]()
        ```
    """

    var _ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]

    fn __init__(out self, mut inner: PythonTypeBuilder):
        self._ptr = UnsafePointer(to=inner)

    fn __init__(
        out self,
        ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin],
    ):
        self._ptr = ptr

    # ------------------------------------------------------------------
    # Unary slots — C type: unaryfunc  fn(PyObject *) -> PyObject *
    # ------------------------------------------------------------------

    fn def_abs[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin]
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__abs__` via the `nb_absolute` slot.

        Called by `abs(obj)`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_absolute
        """
        _install_unary[Self.self_type, method, _PySlotIndex.nb_absolute](
            self._ptr
        )
        return self

    fn def_float[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin]
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__float__` via the `nb_float` slot.

        Called by `float(obj)`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_float
        """
        _install_unary[Self.self_type, method, _PySlotIndex.nb_float](self._ptr)
        return self

    fn def_index[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin]
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__index__` via the `nb_index` slot.

        Called by `operator.index(obj)`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_index
        """
        _install_unary[Self.self_type, method, _PySlotIndex.nb_index](self._ptr)
        return self

    fn def_int[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin]
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__int__` via the `nb_int` slot.

        Called by `int(obj)`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_int
        """
        _install_unary[Self.self_type, method, _PySlotIndex.nb_int](self._ptr)
        return self

    fn def_invert[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin]
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__invert__` via the `nb_invert` slot.

        Called by `~obj`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_invert
        """
        _install_unary[Self.self_type, method, _PySlotIndex.nb_invert](
            self._ptr
        )
        return self

    fn def_neg[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin]
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__neg__` via the `nb_negative` slot.

        Called by `-obj`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_negative
        """
        _install_unary[Self.self_type, method, _PySlotIndex.nb_negative](
            self._ptr
        )
        return self

    fn def_pos[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin]
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__pos__` via the `nb_positive` slot.

        Called by `+obj`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_positive
        """
        _install_unary[Self.self_type, method, _PySlotIndex.nb_positive](
            self._ptr
        )
        return self

    # Non-raising unary overloads

    fn def_abs[
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__abs__` via the `nb_absolute` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_absolute
        """
        _install_unary[
            Self.self_type,
            _lift_to_obj[Self.self_type, method],
            _PySlotIndex.nb_absolute,
        ](self._ptr)
        return self

    fn def_float[
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__float__` via the `nb_float` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_float
        """
        _install_unary[
            Self.self_type,
            _lift_to_obj[Self.self_type, method],
            _PySlotIndex.nb_float,
        ](self._ptr)
        return self

    fn def_index[
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__index__` via the `nb_index` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_index
        """
        _install_unary[
            Self.self_type,
            _lift_to_obj[Self.self_type, method],
            _PySlotIndex.nb_index,
        ](self._ptr)
        return self

    fn def_int[
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__int__` via the `nb_int` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_int
        """
        _install_unary[
            Self.self_type,
            _lift_to_obj[Self.self_type, method],
            _PySlotIndex.nb_int,
        ](self._ptr)
        return self

    fn def_invert[
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__invert__` via the `nb_invert` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_invert
        """
        _install_unary[
            Self.self_type,
            _lift_to_obj[Self.self_type, method],
            _PySlotIndex.nb_invert,
        ](self._ptr)
        return self

    fn def_neg[
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__neg__` via the `nb_negative` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_negative
        """
        _install_unary[
            Self.self_type,
            _lift_to_obj[Self.self_type, method],
            _PySlotIndex.nb_negative,
        ](self._ptr)
        return self

    fn def_pos[
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__pos__` via the `nb_positive` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_positive
        """
        _install_unary[
            Self.self_type,
            _lift_to_obj[Self.self_type, method],
            _PySlotIndex.nb_positive,
        ](self._ptr)
        return self

    # Value-receiver unary overloads

    fn def_abs[
        method: fn(Self.self_type) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__abs__` via the `nb_absolute` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_absolute
        """
        _install_unary[
            Self.self_type,
            _lift_val_to_obj[Self.self_type, method],
            _PySlotIndex.nb_absolute,
        ](self._ptr)
        return self

    fn def_float[
        method: fn(Self.self_type) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__float__` via the `nb_float` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_float
        """
        _install_unary[
            Self.self_type,
            _lift_val_to_obj[Self.self_type, method],
            _PySlotIndex.nb_float,
        ](self._ptr)
        return self

    fn def_index[
        method: fn(Self.self_type) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__index__` via the `nb_index` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_index
        """
        _install_unary[
            Self.self_type,
            _lift_val_to_obj[Self.self_type, method],
            _PySlotIndex.nb_index,
        ](self._ptr)
        return self

    fn def_int[
        method: fn(Self.self_type) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__int__` via the `nb_int` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_int
        """
        _install_unary[
            Self.self_type,
            _lift_val_to_obj[Self.self_type, method],
            _PySlotIndex.nb_int,
        ](self._ptr)
        return self

    fn def_invert[
        method: fn(Self.self_type) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__invert__` via the `nb_invert` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_invert
        """
        _install_unary[
            Self.self_type,
            _lift_val_to_obj[Self.self_type, method],
            _PySlotIndex.nb_invert,
        ](self._ptr)
        return self

    fn def_neg[
        method: fn(Self.self_type) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__neg__` via the `nb_negative` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_negative
        """
        _install_unary[
            Self.self_type,
            _lift_val_to_obj[Self.self_type, method],
            _PySlotIndex.nb_negative,
        ](self._ptr)
        return self

    fn def_pos[
        method: fn(Self.self_type) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__pos__` via the `nb_positive` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_positive
        """
        _install_unary[
            Self.self_type,
            _lift_val_to_obj[Self.self_type, method],
            _PySlotIndex.nb_positive,
        ](self._ptr)
        return self

    # ------------------------------------------------------------------
    # Bool slot — C type: inquiry  int(*)(PyObject *)
    # ------------------------------------------------------------------

    fn def_bool[
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) raises -> Bool
    ](mut self) -> ref[self] Self:
        """Install `__bool__` via the `nb_bool` slot.

        Called by `bool(obj)`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_bool
        """
        _install_inquiry[Self.self_type, method, _PySlotIndex.nb_bool](
            self._ptr
        )
        return self

    fn def_bool[
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) -> Bool
    ](mut self) -> ref[self] Self:
        """Install `__bool__` via the `nb_bool` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_bool
        """
        _install_inquiry[
            Self.self_type,
            _lift_to_bool[Self.self_type, method],
            _PySlotIndex.nb_bool,
        ](self._ptr)
        return self

    fn def_bool[
        method: fn(Self.self_type) raises -> Bool
    ](mut self) -> ref[self] Self:
        """Install `__bool__` via the `nb_bool` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_bool
        """
        _install_inquiry[
            Self.self_type,
            _lift_val_to_bool[Self.self_type, method],
            _PySlotIndex.nb_bool,
        ](self._ptr)
        return self

    # ------------------------------------------------------------------
    # Binary slots — C type: binaryfunc  fn(PyObject *, PyObject *) -> PyObject *
    # Raise NotImplementedError() to return Py_NotImplemented.
    # ------------------------------------------------------------------

    fn def_add[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__add__` via the `nb_add` slot.

        Called by `obj + other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_add
        """
        _install_binary[Self.self_type, method, _PySlotIndex.nb_add](self._ptr)
        return self

    fn def_and[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__and__` via the `nb_and` slot.

        Called by `obj & other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_and
        """
        _install_binary[Self.self_type, method, _PySlotIndex.nb_and](self._ptr)
        return self

    fn def_divmod[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__divmod__` via the `nb_divmod` slot.

        Called by `divmod(obj, other)`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_divmod
        """
        _install_binary[Self.self_type, method, _PySlotIndex.nb_divmod](
            self._ptr
        )
        return self

    fn def_floordiv[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__floordiv__` via the `nb_floor_divide` slot.

        Called by `obj // other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_floor_divide
        """
        _install_binary[Self.self_type, method, _PySlotIndex.nb_floor_divide](
            self._ptr
        )
        return self

    fn def_lshift[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__lshift__` via the `nb_lshift` slot.

        Called by `obj << other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_lshift
        """
        _install_binary[Self.self_type, method, _PySlotIndex.nb_lshift](
            self._ptr
        )
        return self

    fn def_matmul[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__matmul__` via the `nb_matrix_multiply` slot.

        Called by `obj @ other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_matrix_multiply
        """
        _install_binary[
            Self.self_type, method, _PySlotIndex.nb_matrix_multiply
        ](self._ptr)
        return self

    fn def_mod[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__mod__` via the `nb_remainder` slot.

        Called by `obj % other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_remainder
        """
        _install_binary[Self.self_type, method, _PySlotIndex.nb_remainder](
            self._ptr
        )
        return self

    fn def_mul[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__mul__` via the `nb_multiply` slot.

        Called by `obj * other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_multiply
        """
        _install_binary[Self.self_type, method, _PySlotIndex.nb_multiply](
            self._ptr
        )
        return self

    fn def_or[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__or__` via the `nb_or` slot.

        Called by `obj | other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_or
        """
        _install_binary[Self.self_type, method, _PySlotIndex.nb_or](self._ptr)
        return self

    fn def_rshift[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__rshift__` via the `nb_rshift` slot.

        Called by `obj >> other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_rshift
        """
        _install_binary[Self.self_type, method, _PySlotIndex.nb_rshift](
            self._ptr
        )
        return self

    fn def_sub[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__sub__` via the `nb_subtract` slot.

        Called by `obj - other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_subtract
        """
        _install_binary[Self.self_type, method, _PySlotIndex.nb_subtract](
            self._ptr
        )
        return self

    fn def_truediv[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__truediv__` via the `nb_true_divide` slot.

        Called by `obj / other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_true_divide
        """
        _install_binary[Self.self_type, method, _PySlotIndex.nb_true_divide](
            self._ptr
        )
        return self

    fn def_xor[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__xor__` via the `nb_xor` slot.

        Called by `obj ^ other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_xor
        """
        _install_binary[Self.self_type, method, _PySlotIndex.nb_xor](self._ptr)
        return self

    # In-place binary slots

    fn def_iadd[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__iadd__` via the `nb_inplace_add` slot.

        Called by `obj += other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_add
        """
        _install_binary[Self.self_type, method, _PySlotIndex.nb_inplace_add](
            self._ptr
        )
        return self

    fn def_iand[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__iand__` via the `nb_inplace_and` slot.

        Called by `obj &= other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_and
        """
        _install_binary[Self.self_type, method, _PySlotIndex.nb_inplace_and](
            self._ptr
        )
        return self

    fn def_ifloordiv[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ifloordiv__` via the `nb_inplace_floor_divide` slot.

        Called by `obj //= other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_floor_divide
        """
        _install_binary[
            Self.self_type, method, _PySlotIndex.nb_inplace_floor_divide
        ](self._ptr)
        return self

    fn def_ilshift[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ilshift__` via the `nb_inplace_lshift` slot.

        Called by `obj <<= other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_lshift
        """
        _install_binary[Self.self_type, method, _PySlotIndex.nb_inplace_lshift](
            self._ptr
        )
        return self

    fn def_imatmul[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__imatmul__` via the `nb_inplace_matrix_multiply` slot.

        Called by `obj @= other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_matrix_multiply
        """
        _install_binary[
            Self.self_type, method, _PySlotIndex.nb_inplace_matrix_multiply
        ](self._ptr)
        return self

    fn def_imod[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__imod__` via the `nb_inplace_remainder` slot.

        Called by `obj %= other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_remainder
        """
        _install_binary[
            Self.self_type, method, _PySlotIndex.nb_inplace_remainder
        ](self._ptr)
        return self

    fn def_imul[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__imul__` via the `nb_inplace_multiply` slot.

        Called by `obj *= other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_multiply
        """
        _install_binary[
            Self.self_type, method, _PySlotIndex.nb_inplace_multiply
        ](self._ptr)
        return self

    fn def_ior[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ior__` via the `nb_inplace_or` slot.

        Called by `obj |= other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_or
        """
        _install_binary[Self.self_type, method, _PySlotIndex.nb_inplace_or](
            self._ptr
        )
        return self

    fn def_irshift[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__irshift__` via the `nb_inplace_rshift` slot.

        Called by `obj >>= other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_rshift
        """
        _install_binary[Self.self_type, method, _PySlotIndex.nb_inplace_rshift](
            self._ptr
        )
        return self

    fn def_isub[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__isub__` via the `nb_inplace_subtract` slot.

        Called by `obj -= other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_subtract
        """
        _install_binary[
            Self.self_type, method, _PySlotIndex.nb_inplace_subtract
        ](self._ptr)
        return self

    fn def_itruediv[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__itruediv__` via the `nb_inplace_true_divide` slot.

        Called by `obj /= other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_true_divide
        """
        _install_binary[
            Self.self_type, method, _PySlotIndex.nb_inplace_true_divide
        ](self._ptr)
        return self

    fn def_ixor[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ixor__` via the `nb_inplace_xor` slot.

        Called by `obj ^= other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_xor
        """
        _install_binary[Self.self_type, method, _PySlotIndex.nb_inplace_xor](
            self._ptr
        )
        return self

    # Non-raising binary overloads

    fn def_add[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__add__` via the `nb_add` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_add
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_add,
        ](self._ptr)
        return self

    fn def_and[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__and__` via the `nb_and` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_and
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_and,
        ](self._ptr)
        return self

    fn def_divmod[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__divmod__` via the `nb_divmod` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_divmod
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_divmod,
        ](self._ptr)
        return self

    fn def_floordiv[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__floordiv__` via the `nb_floor_divide` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_floor_divide
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_floor_divide,
        ](self._ptr)
        return self

    fn def_lshift[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__lshift__` via the `nb_lshift` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_lshift
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_lshift,
        ](self._ptr)
        return self

    fn def_matmul[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__matmul__` via the `nb_matrix_multiply` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_matrix_multiply
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_matrix_multiply,
        ](self._ptr)
        return self

    fn def_mod[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__mod__` via the `nb_remainder` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_remainder
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_remainder,
        ](self._ptr)
        return self

    fn def_mul[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__mul__` via the `nb_multiply` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_multiply
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_multiply,
        ](self._ptr)
        return self

    fn def_or[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__or__` via the `nb_or` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_or
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_or,
        ](self._ptr)
        return self

    fn def_rshift[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__rshift__` via the `nb_rshift` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_rshift
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_rshift,
        ](self._ptr)
        return self

    fn def_sub[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__sub__` via the `nb_subtract` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_subtract
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_subtract,
        ](self._ptr)
        return self

    fn def_truediv[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__truediv__` via the `nb_true_divide` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_true_divide
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_true_divide,
        ](self._ptr)
        return self

    fn def_xor[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__xor__` via the `nb_xor` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_xor
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_xor,
        ](self._ptr)
        return self

    fn def_iadd[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__iadd__` via the `nb_inplace_add` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_add
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_add,
        ](self._ptr)
        return self

    fn def_iand[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__iand__` via the `nb_inplace_and` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_and
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_and,
        ](self._ptr)
        return self

    fn def_ifloordiv[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ifloordiv__` via the `nb_inplace_floor_divide` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_floor_divide
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_floor_divide,
        ](self._ptr)
        return self

    fn def_ilshift[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ilshift__` via the `nb_inplace_lshift` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_lshift
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_lshift,
        ](self._ptr)
        return self

    fn def_imatmul[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__imatmul__` via the `nb_inplace_matrix_multiply` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_matrix_multiply
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_matrix_multiply,
        ](self._ptr)
        return self

    fn def_imod[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__imod__` via the `nb_inplace_remainder` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_remainder
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_remainder,
        ](self._ptr)
        return self

    fn def_imul[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__imul__` via the `nb_inplace_multiply` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_multiply
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_multiply,
        ](self._ptr)
        return self

    fn def_ior[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ior__` via the `nb_inplace_or` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_or
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_or,
        ](self._ptr)
        return self

    fn def_irshift[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__irshift__` via the `nb_inplace_rshift` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_rshift
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_rshift,
        ](self._ptr)
        return self

    fn def_isub[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__isub__` via the `nb_inplace_subtract` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_subtract
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_subtract,
        ](self._ptr)
        return self

    fn def_itruediv[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__itruediv__` via the `nb_inplace_true_divide` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_true_divide
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_true_divide,
        ](self._ptr)
        return self

    fn def_ixor[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ixor__` via the `nb_inplace_xor` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_xor
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_xor,
        ](self._ptr)
        return self

    # Value-receiver binary overloads

    fn def_add[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__add__` via the `nb_add` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_add
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_add,
        ](self._ptr)
        return self

    fn def_and[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__and__` via the `nb_and` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_and
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_and,
        ](self._ptr)
        return self

    fn def_divmod[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__divmod__` via the `nb_divmod` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_divmod
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_divmod,
        ](self._ptr)
        return self

    fn def_floordiv[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__floordiv__` via the `nb_floor_divide` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_floor_divide
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_floor_divide,
        ](self._ptr)
        return self

    fn def_lshift[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__lshift__` via the `nb_lshift` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_lshift
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_lshift,
        ](self._ptr)
        return self

    fn def_matmul[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__matmul__` via the `nb_matrix_multiply` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_matrix_multiply
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_matrix_multiply,
        ](self._ptr)
        return self

    fn def_mod[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__mod__` via the `nb_remainder` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_remainder
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_remainder,
        ](self._ptr)
        return self

    fn def_mul[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__mul__` via the `nb_multiply` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_multiply
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_multiply,
        ](self._ptr)
        return self

    fn def_or[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__or__` via the `nb_or` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_or
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_or,
        ](self._ptr)
        return self

    fn def_rshift[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__rshift__` via the `nb_rshift` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_rshift
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_rshift,
        ](self._ptr)
        return self

    fn def_sub[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__sub__` via the `nb_subtract` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_subtract
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_subtract,
        ](self._ptr)
        return self

    fn def_truediv[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__truediv__` via the `nb_true_divide` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_true_divide
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_true_divide,
        ](self._ptr)
        return self

    fn def_xor[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__xor__` via the `nb_xor` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_xor
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_xor,
        ](self._ptr)
        return self

    fn def_iadd[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__iadd__` via the `nb_inplace_add` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_add
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_add,
        ](self._ptr)
        return self

    fn def_iand[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__iand__` via the `nb_inplace_and` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_and
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_and,
        ](self._ptr)
        return self

    fn def_ifloordiv[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ifloordiv__` via the `nb_inplace_floor_divide` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_floor_divide
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_floor_divide,
        ](self._ptr)
        return self

    fn def_ilshift[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ilshift__` via the `nb_inplace_lshift` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_lshift
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_lshift,
        ](self._ptr)
        return self

    fn def_imatmul[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__imatmul__` via the `nb_inplace_matrix_multiply` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_matrix_multiply
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_matrix_multiply,
        ](self._ptr)
        return self

    fn def_imod[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__imod__` via the `nb_inplace_remainder` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_remainder
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_remainder,
        ](self._ptr)
        return self

    fn def_imul[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__imul__` via the `nb_inplace_multiply` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_multiply
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_multiply,
        ](self._ptr)
        return self

    fn def_ior[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ior__` via the `nb_inplace_or` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_or
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_or,
        ](self._ptr)
        return self

    fn def_irshift[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__irshift__` via the `nb_inplace_rshift` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_rshift
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_rshift,
        ](self._ptr)
        return self

    fn def_isub[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__isub__` via the `nb_inplace_subtract` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_subtract
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_subtract,
        ](self._ptr)
        return self

    fn def_itruediv[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__itruediv__` via the `nb_inplace_true_divide` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_true_divide
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_true_divide,
        ](self._ptr)
        return self

    fn def_ixor[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ixor__` via the `nb_inplace_xor` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_xor
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_xor,
        ](self._ptr)
        return self

    # ------------------------------------------------------------------
    # Ternary slots — C type: ternaryfunc  fn(PyObject *, PyObject *, PyObject *) -> PyObject *
    # `mod` is None unless pow(base, exp, mod) was called.
    # Raise NotImplementedError() to return Py_NotImplemented.
    # ------------------------------------------------------------------

    fn def_pow[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin],
            PythonObject,
            PythonObject,
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__pow__` via the `nb_power` slot.

        Called by `obj ** exp`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_power
        """
        _install_ternary[Self.self_type, method, _PySlotIndex.nb_power](
            self._ptr
        )
        return self

    fn def_ipow[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin],
            PythonObject,
            PythonObject,
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ipow__` via the `nb_inplace_power` slot.

        Called by `obj **= exp`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_power
        """
        _install_ternary[Self.self_type, method, _PySlotIndex.nb_inplace_power](
            self._ptr
        )
        return self

    # Non-raising ternary overloads

    fn def_pow[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin],
            PythonObject,
            PythonObject,
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__pow__` via the `nb_power` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_power
        """
        _install_ternary[
            Self.self_type,
            _lift_obj_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_power,
        ](self._ptr)
        return self

    fn def_ipow[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin],
            PythonObject,
            PythonObject,
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ipow__` via the `nb_inplace_power` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_power
        """
        _install_ternary[
            Self.self_type,
            _lift_obj_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_power,
        ](self._ptr)
        return self

    fn def_pow[
        method: fn(
            Self.self_type, PythonObject, PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__pow__` via the `nb_power` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_power
        """
        _install_ternary[
            Self.self_type,
            _lift_val_obj_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_power,
        ](self._ptr)
        return self

    fn def_ipow[
        method: fn(
            Self.self_type, PythonObject, PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ipow__` via the `nb_inplace_power` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_power
        """
        _install_ternary[
            Self.self_type,
            _lift_val_obj_obj_to_obj[Self.self_type, method],
            _PySlotIndex.nb_inplace_power,
        ](self._ptr)
        return self

    # ConvertibleToPython return overloads

    fn def_abs[
        R: _CPython,
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__abs__` via the `nb_absolute` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_absolute
        """
        _install_unary[
            Self.self_type,
            _conv_ptr_r_unary[Self.self_type, R, method],
            _PySlotIndex.nb_absolute,
        ](self._ptr)
        return self

    fn def_abs[
        R: _CPython,
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__abs__` via the `nb_absolute` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_absolute
        """
        _install_unary[
            Self.self_type,
            _conv_ptr_nr_unary[Self.self_type, R, method],
            _PySlotIndex.nb_absolute,
        ](self._ptr)
        return self

    fn def_abs[
        R: _CPython,
        method: fn(Self.self_type) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__abs__` via the `nb_absolute` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_absolute
        """
        _install_unary[
            Self.self_type,
            _conv_val_r_unary[Self.self_type, R, method],
            _PySlotIndex.nb_absolute,
        ](self._ptr)
        return self

    fn def_float[
        R: _CPython,
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__float__` via the `nb_float` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_float
        """
        _install_unary[
            Self.self_type,
            _conv_ptr_r_unary[Self.self_type, R, method],
            _PySlotIndex.nb_float,
        ](self._ptr)
        return self

    fn def_float[
        R: _CPython,
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__float__` via the `nb_float` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_float
        """
        _install_unary[
            Self.self_type,
            _conv_ptr_nr_unary[Self.self_type, R, method],
            _PySlotIndex.nb_float,
        ](self._ptr)
        return self

    fn def_float[
        R: _CPython,
        method: fn(Self.self_type) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__float__` via the `nb_float` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_float
        """
        _install_unary[
            Self.self_type,
            _conv_val_r_unary[Self.self_type, R, method],
            _PySlotIndex.nb_float,
        ](self._ptr)
        return self

    fn def_index[
        R: _CPython,
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__index__` via the `nb_index` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_index
        """
        _install_unary[
            Self.self_type,
            _conv_ptr_r_unary[Self.self_type, R, method],
            _PySlotIndex.nb_index,
        ](self._ptr)
        return self

    fn def_index[
        R: _CPython,
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__index__` via the `nb_index` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_index
        """
        _install_unary[
            Self.self_type,
            _conv_ptr_nr_unary[Self.self_type, R, method],
            _PySlotIndex.nb_index,
        ](self._ptr)
        return self

    fn def_index[
        R: _CPython,
        method: fn(Self.self_type) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__index__` via the `nb_index` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_index
        """
        _install_unary[
            Self.self_type,
            _conv_val_r_unary[Self.self_type, R, method],
            _PySlotIndex.nb_index,
        ](self._ptr)
        return self

    fn def_int[
        R: _CPython,
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__int__` via the `nb_int` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_int
        """
        _install_unary[
            Self.self_type,
            _conv_ptr_r_unary[Self.self_type, R, method],
            _PySlotIndex.nb_int,
        ](self._ptr)
        return self

    fn def_int[
        R: _CPython,
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__int__` via the `nb_int` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_int
        """
        _install_unary[
            Self.self_type,
            _conv_ptr_nr_unary[Self.self_type, R, method],
            _PySlotIndex.nb_int,
        ](self._ptr)
        return self

    fn def_int[
        R: _CPython,
        method: fn(Self.self_type) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__int__` via the `nb_int` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_int
        """
        _install_unary[
            Self.self_type,
            _conv_val_r_unary[Self.self_type, R, method],
            _PySlotIndex.nb_int,
        ](self._ptr)
        return self

    fn def_invert[
        R: _CPython,
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__invert__` via the `nb_invert` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_invert
        """
        _install_unary[
            Self.self_type,
            _conv_ptr_r_unary[Self.self_type, R, method],
            _PySlotIndex.nb_invert,
        ](self._ptr)
        return self

    fn def_invert[
        R: _CPython,
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__invert__` via the `nb_invert` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_invert
        """
        _install_unary[
            Self.self_type,
            _conv_ptr_nr_unary[Self.self_type, R, method],
            _PySlotIndex.nb_invert,
        ](self._ptr)
        return self

    fn def_invert[
        R: _CPython,
        method: fn(Self.self_type) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__invert__` via the `nb_invert` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_invert
        """
        _install_unary[
            Self.self_type,
            _conv_val_r_unary[Self.self_type, R, method],
            _PySlotIndex.nb_invert,
        ](self._ptr)
        return self

    fn def_neg[
        R: _CPython,
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__neg__` via the `nb_negative` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_negative
        """
        _install_unary[
            Self.self_type,
            _conv_ptr_r_unary[Self.self_type, R, method],
            _PySlotIndex.nb_negative,
        ](self._ptr)
        return self

    fn def_neg[
        R: _CPython,
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__neg__` via the `nb_negative` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_negative
        """
        _install_unary[
            Self.self_type,
            _conv_ptr_nr_unary[Self.self_type, R, method],
            _PySlotIndex.nb_negative,
        ](self._ptr)
        return self

    fn def_neg[
        R: _CPython,
        method: fn(Self.self_type) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__neg__` via the `nb_negative` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_negative
        """
        _install_unary[
            Self.self_type,
            _conv_val_r_unary[Self.self_type, R, method],
            _PySlotIndex.nb_negative,
        ](self._ptr)
        return self

    fn def_pos[
        R: _CPython,
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__pos__` via the `nb_positive` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_positive
        """
        _install_unary[
            Self.self_type,
            _conv_ptr_r_unary[Self.self_type, R, method],
            _PySlotIndex.nb_positive,
        ](self._ptr)
        return self

    fn def_pos[
        R: _CPython,
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__pos__` via the `nb_positive` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_positive
        """
        _install_unary[
            Self.self_type,
            _conv_ptr_nr_unary[Self.self_type, R, method],
            _PySlotIndex.nb_positive,
        ](self._ptr)
        return self

    fn def_pos[
        R: _CPython,
        method: fn(Self.self_type) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__pos__` via the `nb_positive` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_positive
        """
        _install_unary[
            Self.self_type,
            _conv_val_r_unary[Self.self_type, R, method],
            _PySlotIndex.nb_positive,
        ](self._ptr)
        return self

    fn def_add[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__add__` via the `nb_add` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_add
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_add,
        ](self._ptr)
        return self

    fn def_add[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__add__` via the `nb_add` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_add
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_add,
        ](self._ptr)
        return self

    fn def_add[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__add__` via the `nb_add` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_add
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_add,
        ](self._ptr)
        return self

    fn def_and[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__and__` via the `nb_and` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_and
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_and,
        ](self._ptr)
        return self

    fn def_and[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__and__` via the `nb_and` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_and
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_and,
        ](self._ptr)
        return self

    fn def_and[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__and__` via the `nb_and` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_and
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_and,
        ](self._ptr)
        return self

    fn def_divmod[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__divmod__` via the `nb_divmod` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_divmod
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_divmod,
        ](self._ptr)
        return self

    fn def_divmod[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__divmod__` via the `nb_divmod` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_divmod
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_divmod,
        ](self._ptr)
        return self

    fn def_divmod[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__divmod__` via the `nb_divmod` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_divmod
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_divmod,
        ](self._ptr)
        return self

    fn def_floordiv[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__floordiv__` via the `nb_floor_divide` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_floor_divide
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_floor_divide,
        ](self._ptr)
        return self

    fn def_floordiv[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__floordiv__` via the `nb_floor_divide` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_floor_divide
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_floor_divide,
        ](self._ptr)
        return self

    fn def_floordiv[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__floordiv__` via the `nb_floor_divide` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_floor_divide
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_floor_divide,
        ](self._ptr)
        return self

    fn def_lshift[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__lshift__` via the `nb_lshift` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_lshift
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_lshift,
        ](self._ptr)
        return self

    fn def_lshift[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__lshift__` via the `nb_lshift` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_lshift
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_lshift,
        ](self._ptr)
        return self

    fn def_lshift[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__lshift__` via the `nb_lshift` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_lshift
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_lshift,
        ](self._ptr)
        return self

    fn def_matmul[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__matmul__` via the `nb_matrix_multiply` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_matrix_multiply
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_matrix_multiply,
        ](self._ptr)
        return self

    fn def_matmul[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__matmul__` via the `nb_matrix_multiply` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_matrix_multiply
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_matrix_multiply,
        ](self._ptr)
        return self

    fn def_matmul[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__matmul__` via the `nb_matrix_multiply` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_matrix_multiply
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_matrix_multiply,
        ](self._ptr)
        return self

    fn def_mod[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__mod__` via the `nb_remainder` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_remainder
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_remainder,
        ](self._ptr)
        return self

    fn def_mod[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__mod__` via the `nb_remainder` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_remainder
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_remainder,
        ](self._ptr)
        return self

    fn def_mod[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__mod__` via the `nb_remainder` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_remainder
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_remainder,
        ](self._ptr)
        return self

    fn def_mul[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__mul__` via the `nb_multiply` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_multiply
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_multiply,
        ](self._ptr)
        return self

    fn def_mul[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__mul__` via the `nb_multiply` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_multiply
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_multiply,
        ](self._ptr)
        return self

    fn def_mul[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__mul__` via the `nb_multiply` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_multiply
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_multiply,
        ](self._ptr)
        return self

    fn def_or[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__or__` via the `nb_or` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_or
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_or,
        ](self._ptr)
        return self

    fn def_or[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__or__` via the `nb_or` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_or
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_or,
        ](self._ptr)
        return self

    fn def_or[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__or__` via the `nb_or` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_or
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_or,
        ](self._ptr)
        return self

    fn def_rshift[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__rshift__` via the `nb_rshift` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_rshift
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_rshift,
        ](self._ptr)
        return self

    fn def_rshift[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__rshift__` via the `nb_rshift` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_rshift
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_rshift,
        ](self._ptr)
        return self

    fn def_rshift[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__rshift__` via the `nb_rshift` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_rshift
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_rshift,
        ](self._ptr)
        return self

    fn def_sub[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__sub__` via the `nb_subtract` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_subtract
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_subtract,
        ](self._ptr)
        return self

    fn def_sub[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__sub__` via the `nb_subtract` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_subtract
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_subtract,
        ](self._ptr)
        return self

    fn def_sub[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__sub__` via the `nb_subtract` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_subtract
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_subtract,
        ](self._ptr)
        return self

    fn def_truediv[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__truediv__` via the `nb_true_divide` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_true_divide
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_true_divide,
        ](self._ptr)
        return self

    fn def_truediv[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__truediv__` via the `nb_true_divide` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_true_divide
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_true_divide,
        ](self._ptr)
        return self

    fn def_truediv[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__truediv__` via the `nb_true_divide` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_true_divide
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_true_divide,
        ](self._ptr)
        return self

    fn def_xor[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__xor__` via the `nb_xor` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_xor
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_xor,
        ](self._ptr)
        return self

    fn def_xor[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__xor__` via the `nb_xor` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_xor
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_xor,
        ](self._ptr)
        return self

    fn def_xor[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__xor__` via the `nb_xor` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_xor
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_xor,
        ](self._ptr)
        return self

    fn def_iadd[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__iadd__` via the `nb_inplace_add` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_add
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_add,
        ](self._ptr)
        return self

    fn def_iadd[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__iadd__` via the `nb_inplace_add` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_add
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_add,
        ](self._ptr)
        return self

    fn def_iadd[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__iadd__` via the `nb_inplace_add` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_add
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_add,
        ](self._ptr)
        return self

    fn def_iand[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__iand__` via the `nb_inplace_and` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_and
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_and,
        ](self._ptr)
        return self

    fn def_iand[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__iand__` via the `nb_inplace_and` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_and
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_and,
        ](self._ptr)
        return self

    fn def_iand[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__iand__` via the `nb_inplace_and` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_and
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_and,
        ](self._ptr)
        return self

    fn def_ifloordiv[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__ifloordiv__` via the `nb_inplace_floor_divide` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_floor_divide
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_floor_divide,
        ](self._ptr)
        return self

    fn def_ifloordiv[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__ifloordiv__` via the `nb_inplace_floor_divide` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_floor_divide
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_floor_divide,
        ](self._ptr)
        return self

    fn def_ifloordiv[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__ifloordiv__` via the `nb_inplace_floor_divide` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_floor_divide
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_floor_divide,
        ](self._ptr)
        return self

    fn def_ilshift[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__ilshift__` via the `nb_inplace_lshift` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_lshift
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_lshift,
        ](self._ptr)
        return self

    fn def_ilshift[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__ilshift__` via the `nb_inplace_lshift` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_lshift
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_lshift,
        ](self._ptr)
        return self

    fn def_ilshift[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__ilshift__` via the `nb_inplace_lshift` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_lshift
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_lshift,
        ](self._ptr)
        return self

    fn def_imatmul[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__imatmul__` via the `nb_inplace_matrix_multiply` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_matrix_multiply
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_matrix_multiply,
        ](self._ptr)
        return self

    fn def_imatmul[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__imatmul__` via the `nb_inplace_matrix_multiply` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_matrix_multiply
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_matrix_multiply,
        ](self._ptr)
        return self

    fn def_imatmul[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__imatmul__` via the `nb_inplace_matrix_multiply` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_matrix_multiply
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_matrix_multiply,
        ](self._ptr)
        return self

    fn def_imod[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__imod__` via the `nb_inplace_remainder` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_remainder
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_remainder,
        ](self._ptr)
        return self

    fn def_imod[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__imod__` via the `nb_inplace_remainder` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_remainder
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_remainder,
        ](self._ptr)
        return self

    fn def_imod[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__imod__` via the `nb_inplace_remainder` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_remainder
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_remainder,
        ](self._ptr)
        return self

    fn def_imul[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__imul__` via the `nb_inplace_multiply` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_multiply
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_multiply,
        ](self._ptr)
        return self

    fn def_imul[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__imul__` via the `nb_inplace_multiply` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_multiply
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_multiply,
        ](self._ptr)
        return self

    fn def_imul[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__imul__` via the `nb_inplace_multiply` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_multiply
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_multiply,
        ](self._ptr)
        return self

    fn def_ior[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__ior__` via the `nb_inplace_or` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_or
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_or,
        ](self._ptr)
        return self

    fn def_ior[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__ior__` via the `nb_inplace_or` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_or
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_or,
        ](self._ptr)
        return self

    fn def_ior[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__ior__` via the `nb_inplace_or` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_or
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_or,
        ](self._ptr)
        return self

    fn def_irshift[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__irshift__` via the `nb_inplace_rshift` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_rshift
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_rshift,
        ](self._ptr)
        return self

    fn def_irshift[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__irshift__` via the `nb_inplace_rshift` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_rshift
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_rshift,
        ](self._ptr)
        return self

    fn def_irshift[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__irshift__` via the `nb_inplace_rshift` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_rshift
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_rshift,
        ](self._ptr)
        return self

    fn def_isub[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__isub__` via the `nb_inplace_subtract` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_subtract
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_subtract,
        ](self._ptr)
        return self

    fn def_isub[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__isub__` via the `nb_inplace_subtract` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_subtract
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_subtract,
        ](self._ptr)
        return self

    fn def_isub[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__isub__` via the `nb_inplace_subtract` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_subtract
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_subtract,
        ](self._ptr)
        return self

    fn def_itruediv[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__itruediv__` via the `nb_inplace_true_divide` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_true_divide
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_true_divide,
        ](self._ptr)
        return self

    fn def_itruediv[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__itruediv__` via the `nb_inplace_true_divide` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_true_divide
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_true_divide,
        ](self._ptr)
        return self

    fn def_itruediv[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__itruediv__` via the `nb_inplace_true_divide` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_true_divide
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_true_divide,
        ](self._ptr)
        return self

    fn def_ixor[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__ixor__` via the `nb_inplace_xor` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_xor
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_xor,
        ](self._ptr)
        return self

    fn def_ixor[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__ixor__` via the `nb_inplace_xor` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_xor
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_xor,
        ](self._ptr)
        return self

    fn def_ixor[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__ixor__` via the `nb_inplace_xor` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_xor
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_xor,
        ](self._ptr)
        return self

    fn def_pow[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin],
            PythonObject,
            PythonObject,
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__pow__` via the `nb_power` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_power
        """
        _install_ternary[
            Self.self_type,
            _conv_ptr_r_ternary[Self.self_type, R, method],
            _PySlotIndex.nb_power,
        ](self._ptr)
        return self

    fn def_pow[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin],
            PythonObject,
            PythonObject,
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__pow__` via the `nb_power` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_power
        """
        _install_ternary[
            Self.self_type,
            _conv_ptr_nr_ternary[Self.self_type, R, method],
            _PySlotIndex.nb_power,
        ](self._ptr)
        return self

    fn def_pow[
        R: _CPython,
        method: fn(Self.self_type, PythonObject, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__pow__` via the `nb_power` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_power
        """
        _install_ternary[
            Self.self_type,
            _conv_val_r_ternary[Self.self_type, R, method],
            _PySlotIndex.nb_power,
        ](self._ptr)
        return self

    fn def_ipow[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin],
            PythonObject,
            PythonObject,
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__ipow__` via the `nb_inplace_power` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_power
        """
        _install_ternary[
            Self.self_type,
            _conv_ptr_r_ternary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_power,
        ](self._ptr)
        return self

    fn def_ipow[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin],
            PythonObject,
            PythonObject,
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__ipow__` via the `nb_inplace_power` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_power
        """
        _install_ternary[
            Self.self_type,
            _conv_ptr_nr_ternary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_power,
        ](self._ptr)
        return self

    fn def_ipow[
        R: _CPython,
        method: fn(Self.self_type, PythonObject, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__ipow__` via the `nb_inplace_power` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyNumberMethods.nb_inplace_power
        """
        _install_ternary[
            Self.self_type,
            _conv_val_r_ternary[Self.self_type, R, method],
            _PySlotIndex.nb_inplace_power,
        ](self._ptr)
        return self


# ===----------------------------------------------------------------------=== #
# MappingProtocolBuilder
# ===----------------------------------------------------------------------=== #


struct MappingProtocolBuilder[self_type: ImplicitlyDestructible]:
    """Installs CPython mapping protocol slots on a `PythonTypeBuilder`.

    Construct directly from a `PythonTypeBuilder`.  The three methods correspond
    to `__len__`, `__getitem__`, and `__setitem__`/`__delitem__`.
    Handler functions receive `UnsafePointer[T, MutAnyOrigin]` as their first
    argument instead of a raw `PythonObject`.

    Usage:
        ```mojo
        var mpb = MappingProtocolBuilder[MyStruct](tb)
        mpb.def_len[MyStruct.py__len__]()
           .def_getitem[MyStruct.py__getitem__]()
           .def_setitem[MyStruct.py__setitem__]()
        ```
    """

    var _ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]

    fn __init__(out self, mut inner: PythonTypeBuilder):
        self._ptr = UnsafePointer(to=inner)

    fn __init__(
        out self,
        ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin],
    ):
        self._ptr = ptr

    fn def_len[
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) raises -> Int
    ](mut self) -> ref[self] Self:
        """Install `__len__` via the `mp_length` slot.

        Called by `len(obj)`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyMappingMethods.mp_length
        """
        _install_lenfunc[Self.self_type, method](self._ptr)
        return self

    fn def_getitem[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__getitem__` via the `mp_subscript` slot.

        Called by `obj[key]`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyMappingMethods.mp_subscript
        """
        _install_mp_getitem[Self.self_type, method](self._ptr)
        return self

    fn def_setitem[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin],
            PythonObject,
            Variant[PythonObject, Int],
        ) raises -> None
    ](mut self) -> ref[self] Self:
        """Install `__setitem__`/`__delitem__` via the `mp_ass_subscript` slot.

        Called by `obj[key] = value` or `del obj[key]`.

        The third argument to `method` is a `Variant`:
        - `Variant[PythonObject, Int](value)` for assignment.
        - `Variant[PythonObject, Int](Int(0))` for deletion (null C pointer).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyMappingMethods.mp_ass_subscript
        """
        _install_objobjargproc[Self.self_type, method](self._ptr)
        return self

    # Non-raising overloads

    fn def_len[
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) -> Int
    ](mut self) -> ref[self] Self:
        """Install `__len__` via the `mp_length` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyMappingMethods.mp_length
        """
        _install_lenfunc[Self.self_type, _lift_to_int[Self.self_type, method]](
            self._ptr
        )
        return self

    fn def_getitem[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__getitem__` via the `mp_subscript` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyMappingMethods.mp_subscript
        """
        _install_mp_getitem[
            Self.self_type, _lift_obj_to_obj[Self.self_type, method]
        ](self._ptr)
        return self

    fn def_setitem[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin],
            PythonObject,
            Variant[PythonObject, Int],
        ) -> None
    ](mut self) -> ref[self] Self:
        """Install `__setitem__`/`__delitem__` via the `mp_ass_subscript` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyMappingMethods.mp_ass_subscript
        """
        _install_objobjargproc[
            Self.self_type, _lift_obj_var_to_none[Self.self_type, method]
        ](self._ptr)
        return self

    # Value-receiver overloads

    fn def_len[
        method: fn(Self.self_type) raises -> Int
    ](mut self) -> ref[self] Self:
        """Install `__len__` via the `mp_length` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyMappingMethods.mp_length
        """
        _install_lenfunc[
            Self.self_type, _lift_val_to_int[Self.self_type, method]
        ](self._ptr)
        return self

    fn def_getitem[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__getitem__` via the `mp_subscript` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyMappingMethods.mp_subscript
        """
        _install_mp_getitem[
            Self.self_type, _lift_val_obj_to_obj[Self.self_type, method]
        ](self._ptr)
        return self

    fn def_setitem[
        method: fn(
            Self.self_type, PythonObject, Variant[PythonObject, Int]
        ) raises -> None
    ](mut self) -> ref[self] Self:
        """Install `__setitem__`/`__delitem__` via the `mp_ass_subscript` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyMappingMethods.mp_ass_subscript
        """
        _install_objobjargproc[
            Self.self_type, _lift_val_obj_var_to_none[Self.self_type, method]
        ](self._ptr)
        return self

    # ConvertibleToPython return overloads

    fn def_getitem[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__getitem__` via the `mp_subscript` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyMappingMethods.mp_subscript
        """
        _install_mp_getitem[
            Self.self_type, _conv_ptr_r_binary[Self.self_type, R, method]
        ](self._ptr)
        return self

    fn def_getitem[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__getitem__` via the `mp_subscript` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyMappingMethods.mp_subscript
        """
        _install_mp_getitem[
            Self.self_type, _conv_ptr_nr_binary[Self.self_type, R, method]
        ](self._ptr)
        return self

    fn def_getitem[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__getitem__` via the `mp_subscript` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PyMappingMethods.mp_subscript
        """
        _install_mp_getitem[
            Self.self_type, _conv_val_r_binary[Self.self_type, R, method]
        ](self._ptr)
        return self


# ===----------------------------------------------------------------------=== #
# SequenceProtocolBuilder
# ===----------------------------------------------------------------------=== #


struct SequenceProtocolBuilder[self_type: ImplicitlyDestructible]:
    """Installs CPython sequence protocol slots on a `PythonTypeBuilder`.

    Construct directly from a `PythonTypeBuilder`.  Method names follow the
    corresponding Python dunders.
    Handler functions receive `UnsafePointer[T, MutAnyOrigin]` as their first
    argument instead of a raw `PythonObject`.

    `def_getitem`, `def_repeat`, and `def_irepeat` use `ssizeargfunc`
    (integer index/count), unlike the mapping protocol which uses a
    `PythonObject` key.  `def_contains` uses `objobjproc`.

    Usage:
        ```mojo
        var spb = SequenceProtocolBuilder[MyStruct](tb)
        spb.def_len[MyStruct.py__len__]()
           .def_getitem[MyStruct.py__getitem__]()
           .def_contains[MyStruct.py__contains__]()
        ```
    """

    var _ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]

    fn __init__(out self, mut inner: PythonTypeBuilder):
        self._ptr = UnsafePointer(to=inner)

    fn __init__(
        out self,
        ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin],
    ):
        self._ptr = ptr

    fn def_len[
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) raises -> Int
    ](mut self) -> ref[self] Self:
        """Install `__len__` via the `sq_length` slot.

        Called by `len(obj)`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_length
        """
        comptime _lenfunc = fn(PyObjectPtr) -> Py_ssize_t
        var fn_ptr: _lenfunc = _mp_length_wrapper[Self.self_type, method]
        self._ptr[]._insert_slot(
            PyType_Slot(
                _PySlotIndex.sq_length,
                rebind[OpaquePointer[MutAnyOrigin]](fn_ptr),
            )
        )
        return self

    fn def_getitem[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], Int
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__getitem__` via the `sq_item` slot (integer index).

        Called by `obj[index]`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_item
        """
        _install_ssizeargfunc[Self.self_type, method, _PySlotIndex.sq_item](
            self._ptr
        )
        return self

    fn def_setitem[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin],
            Int,
            Variant[PythonObject, Int],
        ) raises -> None
    ](mut self) -> ref[self] Self:
        """Install `__setitem__`/`__delitem__` via the `sq_ass_item` slot.

        Called by `obj[index] = value` or `del obj[index]`.

        The third argument to `method` is a `Variant`:
        - `Variant[PythonObject, Int](value)` for assignment.
        - `Variant[PythonObject, Int](Int(0))` for deletion (null C pointer).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_ass_item
        """
        _install_ssizeobjargproc[Self.self_type, method](self._ptr)
        return self

    fn def_contains[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> Bool
    ](mut self) -> ref[self] Self:
        """Install `__contains__` via the `sq_contains` slot.

        Called by `item in obj`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_contains
        """
        _install_objobjproc[Self.self_type, method, _PySlotIndex.sq_contains](
            self._ptr
        )
        return self

    fn def_concat[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__add__` (concatenation) via the `sq_concat` slot.

        Called by `obj + other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_concat
        """
        _install_binary[Self.self_type, method, _PySlotIndex.sq_concat](
            self._ptr
        )
        return self

    fn def_repeat[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], Int
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__mul__` (repetition) via the `sq_repeat` slot.

        Called by `obj * count`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_repeat
        """
        _install_ssizeargfunc[Self.self_type, method, _PySlotIndex.sq_repeat](
            self._ptr
        )
        return self

    fn def_iconcat[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__iadd__` (in-place concatenation) via the `sq_inplace_concat` slot.

        Called by `obj += other`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_inplace_concat
        """
        _install_binary[Self.self_type, method, _PySlotIndex.sq_inplace_concat](
            self._ptr
        )
        return self

    fn def_irepeat[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], Int
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__imul__` (in-place repetition) via the `sq_inplace_repeat` slot.

        Called by `obj *= count`.
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_inplace_repeat
        """
        _install_ssizeargfunc[
            Self.self_type, method, _PySlotIndex.sq_inplace_repeat
        ](self._ptr)
        return self

    # Non-raising overloads

    fn def_len[
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin]) -> Int
    ](mut self) -> ref[self] Self:
        """Install `__len__` via the `sq_length` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_length
        """
        comptime _lenfunc = fn(PyObjectPtr) -> Py_ssize_t
        var fn_ptr: _lenfunc = _mp_length_wrapper[
            Self.self_type, _lift_to_int[Self.self_type, method]
        ]
        self._ptr[]._insert_slot(
            PyType_Slot(
                _PySlotIndex.sq_length,
                rebind[OpaquePointer[MutAnyOrigin]](fn_ptr),
            )
        )
        return self

    fn def_getitem[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], Int
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__getitem__` via the `sq_item` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_item
        """
        _install_ssizeargfunc[
            Self.self_type,
            _lift_int_to_obj[Self.self_type, method],
            _PySlotIndex.sq_item,
        ](self._ptr)
        return self

    fn def_setitem[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin],
            Int,
            Variant[PythonObject, Int],
        ) -> None
    ](mut self) -> ref[self] Self:
        """Install `__setitem__`/`__delitem__` via the `sq_ass_item` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_ass_item
        """
        _install_ssizeobjargproc[
            Self.self_type, _lift_int_var_to_none[Self.self_type, method]
        ](self._ptr)
        return self

    fn def_contains[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> Bool
    ](mut self) -> ref[self] Self:
        """Install `__contains__` via the `sq_contains` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_contains
        """
        _install_objobjproc[
            Self.self_type,
            _lift_obj_to_bool[Self.self_type, method],
            _PySlotIndex.sq_contains,
        ](self._ptr)
        return self

    fn def_concat[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__add__` (concatenation) via the `sq_concat` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_concat
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.sq_concat,
        ](self._ptr)
        return self

    fn def_repeat[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], Int
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__mul__` (repetition) via the `sq_repeat` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_repeat
        """
        _install_ssizeargfunc[
            Self.self_type,
            _lift_int_to_obj[Self.self_type, method],
            _PySlotIndex.sq_repeat,
        ](self._ptr)
        return self

    fn def_iconcat[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__iadd__` (in-place concatenation) via the `sq_inplace_concat` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_inplace_concat
        """
        _install_binary[
            Self.self_type,
            _lift_obj_to_obj[Self.self_type, method],
            _PySlotIndex.sq_inplace_concat,
        ](self._ptr)
        return self

    fn def_irepeat[
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], Int
        ) -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__imul__` (in-place repetition) via the `sq_inplace_repeat` slot (non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_inplace_repeat
        """
        _install_ssizeargfunc[
            Self.self_type,
            _lift_int_to_obj[Self.self_type, method],
            _PySlotIndex.sq_inplace_repeat,
        ](self._ptr)
        return self

    # Value-receiver overloads

    fn def_len[
        method: fn(Self.self_type) raises -> Int
    ](mut self) -> ref[self] Self:
        """Install `__len__` via the `sq_length` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_length
        """
        comptime _lenfunc = fn(PyObjectPtr) -> Py_ssize_t
        var fn_ptr: _lenfunc = _mp_length_wrapper[
            Self.self_type, _lift_val_to_int[Self.self_type, method]
        ]
        self._ptr[]._insert_slot(
            PyType_Slot(
                _PySlotIndex.sq_length,
                rebind[OpaquePointer[MutAnyOrigin]](fn_ptr),
            )
        )
        return self

    fn def_getitem[
        method: fn(Self.self_type, Int) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__getitem__` via the `sq_item` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_item
        """
        _install_ssizeargfunc[
            Self.self_type,
            _lift_val_int_to_obj[Self.self_type, method],
            _PySlotIndex.sq_item,
        ](self._ptr)
        return self

    fn def_setitem[
        method: fn(
            Self.self_type, Int, Variant[PythonObject, Int]
        ) raises -> None
    ](mut self) -> ref[self] Self:
        """Install `__setitem__`/`__delitem__` via the `sq_ass_item` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_ass_item
        """
        _install_ssizeobjargproc[
            Self.self_type, _lift_val_int_var_to_none[Self.self_type, method]
        ](self._ptr)
        return self

    fn def_contains[
        method: fn(Self.self_type, PythonObject) raises -> Bool
    ](mut self) -> ref[self] Self:
        """Install `__contains__` via the `sq_contains` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_contains
        """
        _install_objobjproc[
            Self.self_type,
            _lift_val_obj_to_bool[Self.self_type, method],
            _PySlotIndex.sq_contains,
        ](self._ptr)
        return self

    fn def_concat[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__add__` (concatenation) via the `sq_concat` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_concat
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.sq_concat,
        ](self._ptr)
        return self

    fn def_repeat[
        method: fn(Self.self_type, Int) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__mul__` (repetition) via the `sq_repeat` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_repeat
        """
        _install_ssizeargfunc[
            Self.self_type,
            _lift_val_int_to_obj[Self.self_type, method],
            _PySlotIndex.sq_repeat,
        ](self._ptr)
        return self

    fn def_iconcat[
        method: fn(Self.self_type, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__iadd__` (in-place concatenation) via the `sq_inplace_concat` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_inplace_concat
        """
        _install_binary[
            Self.self_type,
            _lift_val_obj_to_obj[Self.self_type, method],
            _PySlotIndex.sq_inplace_concat,
        ](self._ptr)
        return self

    fn def_irepeat[
        method: fn(Self.self_type, Int) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__imul__` (in-place repetition) via the `sq_inplace_repeat` slot (value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_inplace_repeat
        """
        _install_ssizeargfunc[
            Self.self_type,
            _lift_val_int_to_obj[Self.self_type, method],
            _PySlotIndex.sq_inplace_repeat,
        ](self._ptr)
        return self

    # ConvertibleToPython return overloads

    fn def_getitem[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], Int
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__getitem__` via the `sq_item` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_item
        """
        _install_ssizeargfunc[
            Self.self_type,
            _conv_ptr_r_int_arg[Self.self_type, R, method],
            _PySlotIndex.sq_item,
        ](self._ptr)
        return self

    fn def_getitem[
        R: _CPython,
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin], Int) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__getitem__` via the `sq_item` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_item
        """
        _install_ssizeargfunc[
            Self.self_type,
            _conv_ptr_nr_int_arg[Self.self_type, R, method],
            _PySlotIndex.sq_item,
        ](self._ptr)
        return self

    fn def_getitem[
        R: _CPython,
        method: fn(Self.self_type, Int) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__getitem__` via the `sq_item` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_item
        """
        _install_ssizeargfunc[
            Self.self_type,
            _conv_val_r_int_arg[Self.self_type, R, method],
            _PySlotIndex.sq_item,
        ](self._ptr)
        return self

    fn def_concat[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__add__` via the `sq_concat` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_concat
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.sq_concat,
        ](self._ptr)
        return self

    fn def_concat[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__add__` via the `sq_concat` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_concat
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.sq_concat,
        ](self._ptr)
        return self

    fn def_concat[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__add__` via the `sq_concat` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_concat
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.sq_concat,
        ](self._ptr)
        return self

    fn def_repeat[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], Int
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__mul__` via the `sq_repeat` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_repeat
        """
        _install_ssizeargfunc[
            Self.self_type,
            _conv_ptr_r_int_arg[Self.self_type, R, method],
            _PySlotIndex.sq_repeat,
        ](self._ptr)
        return self

    fn def_repeat[
        R: _CPython,
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin], Int) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__mul__` via the `sq_repeat` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_repeat
        """
        _install_ssizeargfunc[
            Self.self_type,
            _conv_ptr_nr_int_arg[Self.self_type, R, method],
            _PySlotIndex.sq_repeat,
        ](self._ptr)
        return self

    fn def_repeat[
        R: _CPython,
        method: fn(Self.self_type, Int) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__mul__` via the `sq_repeat` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_repeat
        """
        _install_ssizeargfunc[
            Self.self_type,
            _conv_val_r_int_arg[Self.self_type, R, method],
            _PySlotIndex.sq_repeat,
        ](self._ptr)
        return self

    fn def_iconcat[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__iadd__` via the `sq_inplace_concat` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_inplace_concat
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_r_binary[Self.self_type, R, method],
            _PySlotIndex.sq_inplace_concat,
        ](self._ptr)
        return self

    fn def_iconcat[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], PythonObject
        ) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__iadd__` via the `sq_inplace_concat` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_inplace_concat
        """
        _install_binary[
            Self.self_type,
            _conv_ptr_nr_binary[Self.self_type, R, method],
            _PySlotIndex.sq_inplace_concat,
        ](self._ptr)
        return self

    fn def_iconcat[
        R: _CPython,
        method: fn(Self.self_type, PythonObject) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__iadd__` via the `sq_inplace_concat` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_inplace_concat
        """
        _install_binary[
            Self.self_type,
            _conv_val_r_binary[Self.self_type, R, method],
            _PySlotIndex.sq_inplace_concat,
        ](self._ptr)
        return self

    fn def_irepeat[
        R: _CPython,
        method: fn(
            UnsafePointer[Self.self_type, MutAnyOrigin], Int
        ) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__imul__` via the `sq_inplace_repeat` slot (ConvertibleToPython return overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_inplace_repeat
        """
        _install_ssizeargfunc[
            Self.self_type,
            _conv_ptr_r_int_arg[Self.self_type, R, method],
            _PySlotIndex.sq_inplace_repeat,
        ](self._ptr)
        return self

    fn def_irepeat[
        R: _CPython,
        method: fn(UnsafePointer[Self.self_type, MutAnyOrigin], Int) -> R,
    ](mut self) -> ref[self] Self:
        """Install `__imul__` via the `sq_inplace_repeat` slot (ConvertibleToPython return, non-raising overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_inplace_repeat
        """
        _install_ssizeargfunc[
            Self.self_type,
            _conv_ptr_nr_int_arg[Self.self_type, R, method],
            _PySlotIndex.sq_inplace_repeat,
        ](self._ptr)
        return self

    fn def_irepeat[
        R: _CPython,
        method: fn(Self.self_type, Int) raises -> R,
    ](mut self) -> ref[self] Self:
        """Install `__imul__` via the `sq_inplace_repeat` slot (ConvertibleToPython return, value-receiver overload).
        See: https://docs.python.org/3/c-api/typeobj.html#c.PySequenceMethods.sq_inplace_repeat
        """
        _install_ssizeargfunc[
            Self.self_type,
            _conv_val_r_int_arg[Self.self_type, R, method],
            _PySlotIndex.sq_inplace_repeat,
        ](self._ptr)
        return self
