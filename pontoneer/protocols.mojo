# ===----------------------------------------------------------------------=== #
# Standalone implementations of types introduced in:
# https://github.com/modular/modular/pull/5562
#
# Provides PyTypeObjectSlot, NotImplementedError, and RichCompareOps for
# use with Python extension modules that require the mapping or rich
# comparison protocols.
# ===----------------------------------------------------------------------=== #

from std.ffi import c_int


struct RichCompareOps:
    """Flags used by the tp_richcompare function.

    Pass the `op` argument from your rich compare handler to these constants
    to determine which comparison is being requested.

    References:
    - https://github.com/python/cpython/blob/main/Include/object.h#L721
    - https://docs.python.org/3/c-api/typeobj.html#c.PyTypeObject.tp_richcompare
    """

    comptime Py_LT = 0
    comptime Py_LE = 1
    comptime Py_EQ = 2
    comptime Py_NE = 3
    comptime Py_GT = 4
    comptime Py_GE = 5


struct PyTypeObjectSlot(
    ImplicitlyCopyable,
    TrivialRegisterPassable,
):
    """Tag struct that identifies a CPython type object slot.

    Use the compile-time constants as the `slot` parameter in
    `PontoneerTypeBuilder.def_method` to select which protocol slot to fill.

    References:
    - https://docs.python.org/3/c-api/typeobj.html
    - https://github.com/python/cpython/blob/main/Include/typeslots.h
    """

    var _type_slot: Int32

    comptime mp_setitem = PyTypeObjectSlot(3)
    """Mapping Protocol: `mp_ass_subscript` slot — __setitem__ / __delitem__.

    References:
    - https://docs.python.org/3/c-api/typeobj.html#c.PyMappingMethods.mp_ass_subscript
    """

    comptime mp_length = PyTypeObjectSlot(4)
    """Mapping Protocol: `mp_length` slot — __len__.

    References:
    - https://docs.python.org/3/c-api/typeobj.html#c.PyMappingMethods.mp_length
    """

    comptime mp_getitem = PyTypeObjectSlot(5)
    """Mapping Protocol: `mp_subscript` slot — __getitem__.

    References:
    - https://docs.python.org/3/c-api/typeobj.html#c.PyMappingMethods.mp_subscript
    """

    comptime tp_richcompare = PyTypeObjectSlot(67)
    """Type Protocol: `tp_richcompare` slot — __lt__, __le__, __eq__, etc.

    References:
    - https://docs.python.org/3/c-api/typeobj.html#c.PyTypeObject.tp_richcompare
    """

    @always_inline("builtin")
    fn __init__(out self, type_slot: Int32):
        self._type_slot = type_slot

    fn as_c_int(self) -> c_int:
        """Return the slot's integer index as a c_int."""
        return c_int(self._type_slot)

    @always_inline("builtin")
    fn is_mp_length(self) -> Bool:
        return self._type_slot == Self.mp_length._type_slot

    @always_inline("builtin")
    fn is_mp_getitem(self) -> Bool:
        return self._type_slot == Self.mp_getitem._type_slot

    @always_inline("builtin")
    fn is_mp_setitem(self) -> Bool:
        return self._type_slot == Self.mp_setitem._type_slot

    @always_inline("builtin")
    fn is_tp_richcompare(self) -> Bool:
        return self._type_slot == Self.tp_richcompare._type_slot


@fieldwise_init
struct NotImplementedError(TrivialRegisterPassable, Writable):
    """Raise this from a rich compare handler to signal Python's NotImplemented.

    When caught by the `_richcompare_wrapper`, this causes the wrapper to
    return `Py_NotImplemented` to Python rather than setting an exception,
    allowing Python to try the reflected operation on the other operand.

    Example:
        ```mojo
        @staticmethod
        fn rich_compare(
            self_ptr: PythonObject, other: PythonObject, op: Int
        ) raises -> Bool:
            if op == RichCompareOps.Py_EQ:
                ...
            raise NotImplementedError()
        ```
    """

    comptime name: String = "NotImplementedError"
    """Well-known name used by `_richcompare_wrapper` for dispatch."""

    fn write_to(self, mut writer: Some[Writer]):
        writer.write(Self.name)
