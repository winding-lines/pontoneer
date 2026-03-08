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


struct TypeProtocolBuilder:
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
        TypeProtocolBuilder(tb).def_richcompare[MyStruct.rich_compare]()
        MappingProtocolBuilder(tb)
            .def_len[MyStruct.py__len__]()
            .def_getitem[MyStruct.py__getitem__]()
            .def_setitem[MyStruct.py__setitem__]()
        NumberProtocolBuilder(tb).def_neg[MyStruct.py__neg__]()
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
        method: fn(PythonObject, PythonObject, Int) raises -> Bool
    ](mut self) -> ref[self] Self:
        """Install rich comparison via the `tp_richcompare` slot.

        Raise `NotImplementedError()` from `method` to return
        `Py_NotImplemented` to Python (triggering the reflected operation).

        Parameters:
            method: Static method with signature
                `fn(py_self, other: PythonObject, op: Int) raises -> Bool`
                where `op` is one of `RichCompareOps.Py_LT` … `Py_GE`.
        """
        _install_richcompare[method](self._ptr)
        return self


# ===----------------------------------------------------------------------=== #
# Slot-install helpers — free functions usable by any builder
# ===----------------------------------------------------------------------=== #


fn _install_unary[
    method: fn(PythonObject) raises -> PythonObject,
    slot: Int32,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `unaryfunc` slot into the builder pointed to by `ptr`."""
    comptime _unaryfunc = fn(PyObjectPtr) -> PyObjectPtr
    var fn_ptr: _unaryfunc = _unaryfunc_wrapper[method]
    ptr[]._insert_slot(
        PyType_Slot(slot, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr))
    )


fn _install_binary[
    method: fn(PythonObject, PythonObject) raises -> PythonObject,
    slot: Int32,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `binaryfunc` slot into the builder pointed to by `ptr`."""
    comptime _binaryfunc = fn(PyObjectPtr, PyObjectPtr) -> PyObjectPtr
    var fn_ptr: _binaryfunc = _binaryfunc_wrapper[method]
    ptr[]._insert_slot(
        PyType_Slot(slot, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr))
    )


fn _install_ternary[
    method: fn(PythonObject, PythonObject, PythonObject) raises -> PythonObject,
    slot: Int32,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `ternaryfunc` slot into the builder pointed to by `ptr`."""
    comptime _ternaryfunc = fn(
        PyObjectPtr, PyObjectPtr, PyObjectPtr
    ) -> PyObjectPtr
    var fn_ptr: _ternaryfunc = _ternaryfunc_wrapper[method]
    ptr[]._insert_slot(
        PyType_Slot(slot, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr))
    )


fn _install_inquiry[
    method: fn(PythonObject) raises -> Bool,
    slot: Int32,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert an `inquiry` slot into the builder pointed to by `ptr`."""
    comptime _inquiry = fn(PyObjectPtr) -> c_int
    var fn_ptr: _inquiry = _inquiry_wrapper[method]
    ptr[]._insert_slot(
        PyType_Slot(slot, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr))
    )


fn _install_richcompare[
    method: fn(PythonObject, PythonObject, Int) raises -> Bool,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `richcmpfunc` slot (`tp_richcompare`) into the builder pointed to by `ptr`.
    """
    # Assign to a typed variable first so the compiler concretizes the
    # parameterized function into a plain C function pointer before rebind.
    comptime _richcmpfunc = fn(PyObjectPtr, PyObjectPtr, c_int) -> PyObjectPtr
    var fn_ptr: _richcmpfunc = _richcompare_wrapper[method]
    ptr[]._insert_slot(
        PyType_Slot(
            _PySlotIndex.tp_richcompare,
            rebind[OpaquePointer[MutAnyOrigin]](fn_ptr),
        )
    )


fn _install_lenfunc[
    method: fn(PythonObject) raises -> Int,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `lenfunc` slot (`mp_length`) into the builder pointed to by `ptr`.
    """
    comptime _lenfunc = fn(PyObjectPtr) -> Py_ssize_t
    var fn_ptr: _lenfunc = _mp_length_wrapper[method]
    ptr[]._insert_slot(
        PyType_Slot(
            _PySlotIndex.mp_length, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr)
        )
    )


fn _install_mp_getitem[
    method: fn(PythonObject, PythonObject) raises -> PythonObject,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `binaryfunc` slot (`mp_subscript`) into the builder pointed to by `ptr`.
    """
    comptime _binaryfunc = fn(PyObjectPtr, PyObjectPtr) -> PyObjectPtr
    var fn_ptr: _binaryfunc = _mp_subscript_wrapper[method]
    ptr[]._insert_slot(
        PyType_Slot(
            _PySlotIndex.mp_getitem, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr)
        )
    )


fn _install_objobjargproc[
    method: fn(
        PythonObject, PythonObject, Variant[PythonObject, Int]
    ) raises -> None,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert an `objobjargproc` slot (`mp_ass_subscript`) into the builder pointed to by `ptr`.
    """
    comptime _objobjargproc = fn(PyObjectPtr, PyObjectPtr, PyObjectPtr) -> c_int
    var fn_ptr: _objobjargproc = _mp_ass_subscript_wrapper[method]
    ptr[]._insert_slot(
        PyType_Slot(
            _PySlotIndex.mp_setitem, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr)
        )
    )


fn _install_ssizeargfunc[
    method: fn(PythonObject, Int) raises -> PythonObject,
    slot: Int32,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert a `ssizeargfunc` slot into the builder pointed to by `ptr`."""
    comptime _ssizeargfunc = fn(PyObjectPtr, Py_ssize_t) -> PyObjectPtr
    var fn_ptr: _ssizeargfunc = _ssizeargfunc_wrapper[method]
    ptr[]._insert_slot(
        PyType_Slot(slot, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr))
    )


fn _install_ssizeobjargproc[
    method: fn(PythonObject, Int, Variant[PythonObject, Int]) raises -> None,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert the `ssizeobjargproc` slot (`sq_ass_item`) into the builder pointed to by `ptr`.
    """
    comptime _ssizeobjargproc = fn(
        PyObjectPtr, Py_ssize_t, PyObjectPtr
    ) -> c_int
    var fn_ptr: _ssizeobjargproc = _ssizeobjargproc_wrapper[method]
    ptr[]._insert_slot(
        PyType_Slot(
            _PySlotIndex.sq_ass_item,
            rebind[OpaquePointer[MutAnyOrigin]](fn_ptr),
        )
    )


fn _install_objobjproc[
    method: fn(PythonObject, PythonObject) raises -> Bool,
    slot: Int32,
](ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]):
    """Insert an `objobjproc` slot into the builder pointed to by `ptr`."""
    comptime _objobjproc = fn(PyObjectPtr, PyObjectPtr) -> c_int
    var fn_ptr: _objobjproc = _objobjproc_wrapper[method]
    ptr[]._insert_slot(
        PyType_Slot(slot, rebind[OpaquePointer[MutAnyOrigin]](fn_ptr))
    )


# ===----------------------------------------------------------------------=== #
# NumberProtocolBuilder
# ===----------------------------------------------------------------------=== #


struct NumberProtocolBuilder:
    """Installs CPython number protocol slots on a `PythonTypeBuilder`.

    Construct directly from a `PythonTypeBuilder`.  Each method is named after the
    corresponding Python dunder and accepts only the matching function signature.

    Binary methods (`def_add`, `def_mul`, etc.) and ternary methods (`def_pow`,
    `def_ipow`) support `NotImplementedError`: raise it from your handler to
    return `Py_NotImplemented` to Python, triggering the reflected operation.

    Usage:
        ```mojo
        var npb = NumberProtocolBuilder(tb)
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
        method: fn(PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__abs__` via the `nb_absolute` slot."""
        _install_unary[method, _PySlotIndex.nb_absolute](self._ptr)
        return self

    fn def_float[
        method: fn(PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__float__` via the `nb_float` slot."""
        _install_unary[method, _PySlotIndex.nb_float](self._ptr)
        return self

    fn def_index[
        method: fn(PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__index__` via the `nb_index` slot."""
        _install_unary[method, _PySlotIndex.nb_index](self._ptr)
        return self

    fn def_int[
        method: fn(PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__int__` via the `nb_int` slot."""
        _install_unary[method, _PySlotIndex.nb_int](self._ptr)
        return self

    fn def_invert[
        method: fn(PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__invert__` via the `nb_invert` slot."""
        _install_unary[method, _PySlotIndex.nb_invert](self._ptr)
        return self

    fn def_neg[
        method: fn(PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__neg__` via the `nb_negative` slot."""
        _install_unary[method, _PySlotIndex.nb_negative](self._ptr)
        return self

    fn def_pos[
        method: fn(PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__pos__` via the `nb_positive` slot."""
        _install_unary[method, _PySlotIndex.nb_positive](self._ptr)
        return self

    # ------------------------------------------------------------------
    # Bool slot — C type: inquiry  int(*)(PyObject *)
    # ------------------------------------------------------------------

    fn def_bool[
        method: fn(PythonObject) raises -> Bool
    ](mut self) -> ref[self] Self:
        """Install `__bool__` via the `nb_bool` slot."""
        _install_inquiry[method, _PySlotIndex.nb_bool](self._ptr)
        return self

    # ------------------------------------------------------------------
    # Binary slots — C type: binaryfunc  fn(PyObject *, PyObject *) -> PyObject *
    # Raise NotImplementedError() to return Py_NotImplemented.
    # ------------------------------------------------------------------

    fn def_add[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__add__` via the `nb_add` slot."""
        _install_binary[method, _PySlotIndex.nb_add](self._ptr)
        return self

    fn def_and[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__and__` via the `nb_and` slot."""
        _install_binary[method, _PySlotIndex.nb_and](self._ptr)
        return self

    fn def_divmod[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__divmod__` via the `nb_divmod` slot."""
        _install_binary[method, _PySlotIndex.nb_divmod](self._ptr)
        return self

    fn def_floordiv[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__floordiv__` via the `nb_floor_divide` slot."""
        _install_binary[method, _PySlotIndex.nb_floor_divide](self._ptr)
        return self

    fn def_lshift[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__lshift__` via the `nb_lshift` slot."""
        _install_binary[method, _PySlotIndex.nb_lshift](self._ptr)
        return self

    fn def_matmul[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__matmul__` via the `nb_matrix_multiply` slot."""
        _install_binary[method, _PySlotIndex.nb_matrix_multiply](self._ptr)
        return self

    fn def_mod[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__mod__` via the `nb_remainder` slot."""
        _install_binary[method, _PySlotIndex.nb_remainder](self._ptr)
        return self

    fn def_mul[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__mul__` via the `nb_multiply` slot."""
        _install_binary[method, _PySlotIndex.nb_multiply](self._ptr)
        return self

    fn def_or[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__or__` via the `nb_or` slot."""
        _install_binary[method, _PySlotIndex.nb_or](self._ptr)
        return self

    fn def_rshift[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__rshift__` via the `nb_rshift` slot."""
        _install_binary[method, _PySlotIndex.nb_rshift](self._ptr)
        return self

    fn def_sub[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__sub__` via the `nb_subtract` slot."""
        _install_binary[method, _PySlotIndex.nb_subtract](self._ptr)
        return self

    fn def_truediv[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__truediv__` via the `nb_true_divide` slot."""
        _install_binary[method, _PySlotIndex.nb_true_divide](self._ptr)
        return self

    fn def_xor[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__xor__` via the `nb_xor` slot."""
        _install_binary[method, _PySlotIndex.nb_xor](self._ptr)
        return self

    # In-place binary slots

    fn def_iadd[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__iadd__` via the `nb_inplace_add` slot."""
        _install_binary[method, _PySlotIndex.nb_inplace_add](self._ptr)
        return self

    fn def_iand[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__iand__` via the `nb_inplace_and` slot."""
        _install_binary[method, _PySlotIndex.nb_inplace_and](self._ptr)
        return self

    fn def_ifloordiv[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ifloordiv__` via the `nb_inplace_floor_divide` slot."""
        _install_binary[method, _PySlotIndex.nb_inplace_floor_divide](self._ptr)
        return self

    fn def_ilshift[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ilshift__` via the `nb_inplace_lshift` slot."""
        _install_binary[method, _PySlotIndex.nb_inplace_lshift](self._ptr)
        return self

    fn def_imatmul[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__imatmul__` via the `nb_inplace_matrix_multiply` slot."""
        _install_binary[method, _PySlotIndex.nb_inplace_matrix_multiply](
            self._ptr
        )
        return self

    fn def_imod[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__imod__` via the `nb_inplace_remainder` slot."""
        _install_binary[method, _PySlotIndex.nb_inplace_remainder](self._ptr)
        return self

    fn def_imul[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__imul__` via the `nb_inplace_multiply` slot."""
        _install_binary[method, _PySlotIndex.nb_inplace_multiply](self._ptr)
        return self

    fn def_ior[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ior__` via the `nb_inplace_or` slot."""
        _install_binary[method, _PySlotIndex.nb_inplace_or](self._ptr)
        return self

    fn def_irshift[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__irshift__` via the `nb_inplace_rshift` slot."""
        _install_binary[method, _PySlotIndex.nb_inplace_rshift](self._ptr)
        return self

    fn def_isub[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__isub__` via the `nb_inplace_subtract` slot."""
        _install_binary[method, _PySlotIndex.nb_inplace_subtract](self._ptr)
        return self

    fn def_itruediv[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__itruediv__` via the `nb_inplace_true_divide` slot."""
        _install_binary[method, _PySlotIndex.nb_inplace_true_divide](self._ptr)
        return self

    fn def_ixor[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ixor__` via the `nb_inplace_xor` slot."""
        _install_binary[method, _PySlotIndex.nb_inplace_xor](self._ptr)
        return self

    # ------------------------------------------------------------------
    # Ternary slots — C type: ternaryfunc  fn(PyObject *, PyObject *, PyObject *) -> PyObject *
    # `mod` is None unless pow(base, exp, mod) was called.
    # Raise NotImplementedError() to return Py_NotImplemented.
    # ------------------------------------------------------------------

    fn def_pow[
        method: fn(
            PythonObject, PythonObject, PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__pow__` via the `nb_power` slot."""
        _install_ternary[method, _PySlotIndex.nb_power](self._ptr)
        return self

    fn def_ipow[
        method: fn(
            PythonObject, PythonObject, PythonObject
        ) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__ipow__` via the `nb_inplace_power` slot."""
        _install_ternary[method, _PySlotIndex.nb_inplace_power](self._ptr)
        return self


# ===----------------------------------------------------------------------=== #
# MappingProtocolBuilder
# ===----------------------------------------------------------------------=== #


struct MappingProtocolBuilder:
    """Installs CPython mapping protocol slots on a `PythonTypeBuilder`.

    Construct directly from a `PythonTypeBuilder`.  The three methods correspond
    to `__len__`, `__getitem__`, and `__setitem__`/`__delitem__`.

    Usage:
        ```mojo
        var mpb = MappingProtocolBuilder(tb)
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
        method: fn(PythonObject) raises -> Int
    ](mut self) -> ref[self] Self:
        """Install `__len__` via the `mp_length` slot."""
        _install_lenfunc[method](self._ptr)
        return self

    fn def_getitem[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__getitem__` via the `mp_subscript` slot."""
        _install_mp_getitem[method](self._ptr)
        return self

    fn def_setitem[
        method: fn(
            PythonObject, PythonObject, Variant[PythonObject, Int]
        ) raises -> None
    ](mut self) -> ref[self] Self:
        """Install `__setitem__`/`__delitem__` via the `mp_ass_subscript` slot.

        The third argument to `method` is a `Variant`:
        - `Variant[PythonObject, Int](value)` for assignment.
        - `Variant[PythonObject, Int](Int(0))` for deletion (null C pointer).
        """
        _install_objobjargproc[method](self._ptr)
        return self


# ===----------------------------------------------------------------------=== #
# SequenceProtocolBuilder
# ===----------------------------------------------------------------------=== #


struct SequenceProtocolBuilder:
    """Installs CPython sequence protocol slots on a `PythonTypeBuilder`.

    Construct directly from a `PythonTypeBuilder`.  Method names follow the
    corresponding Python dunders.

    `def_getitem`, `def_repeat`, and `def_irepeat` use `ssizeargfunc`
    (integer index/count), unlike the mapping protocol which uses a
    `PythonObject` key.  `def_contains` uses `objobjproc`.

    Usage:
        ```mojo
        var spb = SequenceProtocolBuilder(tb)
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
        method: fn(PythonObject) raises -> Int
    ](mut self) -> ref[self] Self:
        """Install `__len__` via the `sq_length` slot."""
        comptime _lenfunc = fn(PyObjectPtr) -> Py_ssize_t
        var fn_ptr: _lenfunc = _mp_length_wrapper[method]
        self._ptr[]._insert_slot(
            PyType_Slot(
                _PySlotIndex.sq_length,
                rebind[OpaquePointer[MutAnyOrigin]](fn_ptr),
            )
        )
        return self

    fn def_getitem[
        method: fn(PythonObject, Int) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__getitem__` via the `sq_item` slot (integer index)."""
        _install_ssizeargfunc[method, _PySlotIndex.sq_item](self._ptr)
        return self

    fn def_setitem[
        method: fn(PythonObject, Int, Variant[PythonObject, Int]) raises -> None
    ](mut self) -> ref[self] Self:
        """Install `__setitem__`/`__delitem__` via the `sq_ass_item` slot.

        The third argument to `method` is a `Variant`:
        - `Variant[PythonObject, Int](value)` for assignment.
        - `Variant[PythonObject, Int](Int(0))` for deletion (null C pointer).
        """
        _install_ssizeobjargproc[method](self._ptr)
        return self

    fn def_contains[
        method: fn(PythonObject, PythonObject) raises -> Bool
    ](mut self) -> ref[self] Self:
        """Install `__contains__` via the `sq_contains` slot."""
        _install_objobjproc[method, _PySlotIndex.sq_contains](self._ptr)
        return self

    fn def_concat[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__add__` (concatenation) via the `sq_concat` slot."""
        _install_binary[method, _PySlotIndex.sq_concat](self._ptr)
        return self

    fn def_repeat[
        method: fn(PythonObject, Int) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__mul__` (repetition) via the `sq_repeat` slot."""
        _install_ssizeargfunc[method, _PySlotIndex.sq_repeat](self._ptr)
        return self

    fn def_iconcat[
        method: fn(PythonObject, PythonObject) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__iadd__` (in-place concatenation) via the `sq_inplace_concat` slot.
        """
        _install_binary[method, _PySlotIndex.sq_inplace_concat](self._ptr)
        return self

    fn def_irepeat[
        method: fn(PythonObject, Int) raises -> PythonObject
    ](mut self) -> ref[self] Self:
        """Install `__imul__` (in-place repetition) via the `sq_inplace_repeat` slot.
        """
        _install_ssizeargfunc[method, _PySlotIndex.sq_inplace_repeat](self._ptr)
        return self
