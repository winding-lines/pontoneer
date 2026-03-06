# ===----------------------------------------------------------------------=== #
# PontoneerTypeBuilder — extends PythonTypeBuilder with mapping protocol and
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

from .protocols import PyTypeObjectSlot, NotImplementedError
from .protocol_adapters import (
    _mp_length_wrapper,
    _mp_subscript_wrapper,
    _mp_ass_subscript_wrapper,
    _richcompare_wrapper,
)

# CPython type slot indices.
# ref: https://github.com/python/cpython/blob/main/Include/typeslots.h
comptime _Py_mp_setitem = Int32(3)
comptime _Py_mp_length = Int32(4)
comptime _Py_mp_getitem = Int32(5)
comptime _Py_tp_richcompare = Int32(67)


struct PontoneerTypeBuilder:
    """Wraps a `PythonTypeBuilder` reference and adds `def_method` overloads
    for the CPython mapping protocol and rich comparison protocol slots.

    `PontoneerTypeBuilder` holds a pointer to a `PythonTypeBuilder` that is
    owned by the enclosing `PythonModuleBuilder`.  The caller must ensure the
    module builder (and its type_builders list) outlives this object, which is
    naturally satisfied when both are used within the same `PyInit_*` function.

    Usage:
        ```mojo
        var ptb = PontoneerTypeBuilder(
            b.add_type[MyStruct]("MyStruct")
             .def_init_defaultable[MyStruct]()
             .def_staticmethod[MyStruct.new]("new")
        )
        ptb.def_method[MyStruct.py__len__,    PyTypeObjectSlot.mp_length]()
        ptb.def_method[MyStruct.py__getitem__, PyTypeObjectSlot.mp_getitem]()
        ptb.def_method[MyStruct.py__setitem__, PyTypeObjectSlot.mp_setitem]()
        ptb.def_method[MyStruct.rich_compare,  PyTypeObjectSlot.tp_richcompare]()
        ```
    """

    # Unsafe pointer into the module builder's type_builders list.
    # The pointed-to builder must outlive this PontoneerTypeBuilder.
    var _ptr: UnsafePointer[mut=True, PythonTypeBuilder, MutAnyOrigin]

    fn __init__(out self, mut inner: PythonTypeBuilder):
        var ptr = UnsafePointer(to=inner)
        self._ptr = ptr

    # ------------------------------------------------------------------
    # Mapping Protocol — mp_length (__len__)
    # ------------------------------------------------------------------

    fn def_method[
        method: fn (PythonObject) raises -> Int,
        slot: PyTypeObjectSlot,
    ](mut self) -> ref[self] Self where slot.is_mp_length():
        """Install a `__len__` implementation via the `mp_length` slot.

        Parameters:
            method: Static method with signature
                `fn(py_self: PythonObject) raises -> Int`.
            slot: Must be `PyTypeObjectSlot.mp_length`.
        """
        comptime _lenfunc = fn (PyObjectPtr) -> Py_ssize_t
        var fn_ptr: _lenfunc = _mp_length_wrapper[method]
        self._ptr[]._insert_slot(
            PyType_Slot(
                _Py_mp_length,
                rebind[OpaquePointer[MutAnyOrigin]](fn_ptr),
            )
        )
        return self

    # ------------------------------------------------------------------
    # Mapping Protocol — mp_subscript (__getitem__)
    # ------------------------------------------------------------------

    fn def_method[
        method: fn (PythonObject, PythonObject) raises -> PythonObject,
        slot: PyTypeObjectSlot,
    ](mut self) -> ref[self] Self where slot.is_mp_getitem():
        """Install a `__getitem__` implementation via the `mp_subscript` slot.

        Parameters:
            method: Static method with signature
                `fn(py_self: PythonObject, key: PythonObject) raises -> PythonObject`.
            slot: Must be `PyTypeObjectSlot.mp_getitem`.
        """
        comptime _binaryfunc = fn (PyObjectPtr, PyObjectPtr) -> PyObjectPtr
        var fn_ptr: _binaryfunc = _mp_subscript_wrapper[method]
        self._ptr[]._insert_slot(
            PyType_Slot(
                _Py_mp_getitem,
                rebind[OpaquePointer[MutAnyOrigin]](fn_ptr),
            )
        )
        return self

    # ------------------------------------------------------------------
    # Mapping Protocol — mp_ass_subscript (__setitem__ / __delitem__)
    # ------------------------------------------------------------------

    fn def_method[
        method: fn (
            PythonObject, PythonObject, Variant[PythonObject, Int]
        ) raises -> None,
        slot: PyTypeObjectSlot,
    ](mut self) -> ref[self] Self where slot.is_mp_setitem():
        """Install `__setitem__`/`__delitem__` via the `mp_ass_subscript` slot.

        The third argument to `method` is a `Variant`:
        - `Variant[PythonObject, Int](value)` for assignment.
        - `Variant[PythonObject, Int](Int(0))` for deletion (null C pointer).

        Parameters:
            method: Static method with signature
                `fn(py_self, key: PythonObject, value: Variant[PythonObject, Int]) raises -> None`.
            slot: Must be `PyTypeObjectSlot.mp_setitem`.
        """
        comptime _objobjargproc = fn (PyObjectPtr, PyObjectPtr, PyObjectPtr) -> c_int
        var fn_ptr: _objobjargproc = _mp_ass_subscript_wrapper[method]
        self._ptr[]._insert_slot(
            PyType_Slot(
                _Py_mp_setitem,
                rebind[OpaquePointer[MutAnyOrigin]](fn_ptr),
            )
        )
        return self

    # ------------------------------------------------------------------
    # Type Protocol — tp_richcompare (__lt__, __eq__, etc.)
    # ------------------------------------------------------------------

    fn def_method[
        method: fn (PythonObject, PythonObject, Int) raises -> Bool,
        slot: PyTypeObjectSlot,
    ](mut self) -> ref[self] Self where slot.is_tp_richcompare():
        """Install rich comparison via the `tp_richcompare` slot.

        Raise `NotImplementedError()` from `method` to return
        `Py_NotImplemented` to Python (triggering the reflected operation).

        Parameters:
            method: Static method with signature
                `fn(py_self, other: PythonObject, op: Int) raises -> Bool`
                where `op` is one of `RichCompareOps.Py_LT` … `Py_GE`.
            slot: Must be `PyTypeObjectSlot.tp_richcompare`.
        """
        # Assign to a typed variable first so the compiler concretizes the
        # parameterized function into a plain C function pointer before rebind.
        # (Functions that take non-pointer C arguments, like `c_int`, remain
        # as MLIR "generators" otherwise and rebind rejects them.)
        comptime _richcmpfunc = fn (PyObjectPtr, PyObjectPtr, c_int) -> PyObjectPtr
        var fn_ptr: _richcmpfunc = _richcompare_wrapper[method]
        self._ptr[]._insert_slot(
            PyType_Slot(
                _Py_tp_richcompare,
                rebind[OpaquePointer[MutAnyOrigin]](fn_ptr),
            )
        )
        return self

