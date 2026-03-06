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
from std.memory import OpaquePointer
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


struct PontoneerTypeBuilder(Copyable):
    """Wraps `PythonTypeBuilder` and adds `def_method` overloads for the
    CPython mapping protocol and rich comparison protocol slots.

    Usage:
        ```mojo
        var tb = b.add_type[MyStruct]("MyStruct")
                   .def_init_defaultable[MyStruct]()
                   .def_staticmethod[MyStruct.new]("new")

        _ = PontoneerTypeBuilder(tb^)
                .def_method[MyStruct.py__len__,     PyTypeObjectSlot.mp_length]()
                .def_method[MyStruct.py__getitem__,  PyTypeObjectSlot.mp_getitem]()
                .def_method[MyStruct.py__setitem__,  PyTypeObjectSlot.mp_setitem]()
                .def_method[MyStruct.rich_compare,   PyTypeObjectSlot.tp_richcompare]()
        ```

    The underlying `PythonTypeBuilder` is consumed on construction; use
    `inner()` if you need to call further stdlib builder methods afterwards.
    """

    var _inner: PythonTypeBuilder

    fn __init__(out self, owned inner: PythonTypeBuilder):
        self._inner = inner^

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
        self._inner._insert_slot(
            PyType_Slot(
                _Py_mp_length,
                rebind[OpaquePointer[MutAnyOrigin]](
                    _mp_length_wrapper[method]
                ),
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
        self._inner._insert_slot(
            PyType_Slot(
                _Py_mp_getitem,
                rebind[OpaquePointer[MutAnyOrigin]](
                    _mp_subscript_wrapper[method]
                ),
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
        self._inner._insert_slot(
            PyType_Slot(
                _Py_mp_setitem,
                rebind[OpaquePointer[MutAnyOrigin]](
                    _mp_ass_subscript_wrapper[method]
                ),
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
        self._inner._insert_slot(
            PyType_Slot(
                _Py_tp_richcompare,
                rebind[OpaquePointer[MutAnyOrigin]](
                    _richcompare_wrapper[method]
                ),
            )
        )
        return self

    # ------------------------------------------------------------------
    # Escape hatch
    # ------------------------------------------------------------------

    fn inner(ref self) -> ref[self] PythonTypeBuilder:
        """Borrow the underlying `PythonTypeBuilder` for further configuration."""
        return self._inner
