# ===----------------------------------------------------------------------=== #
# Test for NumberProtocolBuilder.
#
# Exposes a Number type (wrapping Int) to Python that supports:
#   - -n, abs(n), +n, ~n                   via nb_negative/absolute/positive/invert
#   - bool(n)                              via nb_bool
#   - int(n), float(n), operator.index(n)  via nb_int/float/index
#   - n + m, n - m, n * m, n // m, n % m  via nb_add/subtract/multiply/floor_divide/remainder
#   - n & m, n | m, n ^ m                 via nb_and/or/xor
#   - n << m, n >> m                       via nb_lshift/rshift
#   - n ** m                               via nb_power
# ===----------------------------------------------------------------------=== #

from std.os import abort
from std.memory import UnsafePointer
from std.python import PythonObject
from std.python.bindings import PythonModuleBuilder

from pontoneer import NotImplementedError, NumberProtocolBuilder


struct Number(Defaultable, Movable, Writable):
    var value: Int

    fn __init__(out self):
        self.value = 0

    fn __init__(out self, value: Int):
        self.value = value

    @staticmethod
    fn _get_self_ptr(
        py_self: PythonObject,
    ) -> UnsafePointer[Self, MutAnyOrigin]:
        try:
            return py_self.downcast_value_ptr[Self]()
        except e:
            abort(String("downcast failed: ", e))

    @staticmethod
    fn new(value: PythonObject) raises -> PythonObject:
        return PythonObject(alloc=Number(Int(py=value)))

    @staticmethod
    fn get_value(py_self: PythonObject) raises -> PythonObject:
        return PythonObject(Self._get_self_ptr(py_self)[].value)

    # ------------------------------------------------------------------
    # Unary slots
    # ------------------------------------------------------------------

    @staticmethod
    fn py__neg__(
        self_ptr: UnsafePointer[Self, MutAnyOrigin]
    ) raises -> PythonObject:
        return PythonObject(alloc=Number(-self_ptr[].value))

    @staticmethod
    fn py__abs__(
        self_ptr: UnsafePointer[Self, MutAnyOrigin]
    ) raises -> PythonObject:
        return PythonObject(alloc=Number(abs(self_ptr[].value)))

    @staticmethod
    fn py__pos__(
        self_ptr: UnsafePointer[Self, MutAnyOrigin]
    ) raises -> PythonObject:
        return PythonObject(alloc=Number(self_ptr[].value))

    @staticmethod
    fn py__invert__(
        self_ptr: UnsafePointer[Self, MutAnyOrigin]
    ) raises -> PythonObject:
        return PythonObject(alloc=Number(~self_ptr[].value))

    # ------------------------------------------------------------------
    # Bool slot
    # ------------------------------------------------------------------

    @staticmethod
    fn py__bool__(self_ptr: UnsafePointer[Self, MutAnyOrigin]) raises -> Bool:
        return self_ptr[].value != 0

    # ------------------------------------------------------------------
    # Conversion slots
    # ------------------------------------------------------------------

    @staticmethod
    fn py__int__(
        self_ptr: UnsafePointer[Self, MutAnyOrigin]
    ) raises -> PythonObject:
        return PythonObject(self_ptr[].value)

    @staticmethod
    fn py__float__(
        self_ptr: UnsafePointer[Self, MutAnyOrigin]
    ) raises -> PythonObject:
        return PythonObject(Float64(self_ptr[].value))

    @staticmethod
    fn py__index__(
        self_ptr: UnsafePointer[Self, MutAnyOrigin]
    ) raises -> PythonObject:
        return PythonObject(self_ptr[].value)

    # ------------------------------------------------------------------
    # Binary slots — raise NotImplementedError for non-Number operands
    # ------------------------------------------------------------------

    @staticmethod
    fn py__add__(
        self_ptr: UnsafePointer[Self, MutAnyOrigin], other: PythonObject
    ) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=Number(self_ptr[].value + o[].value))
        except:
            raise NotImplementedError()

    @staticmethod
    fn py__sub__(
        self_ptr: UnsafePointer[Self, MutAnyOrigin], other: PythonObject
    ) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=Number(self_ptr[].value - o[].value))
        except:
            raise NotImplementedError()

    @staticmethod
    fn py__mul__(
        self_ptr: UnsafePointer[Self, MutAnyOrigin], other: PythonObject
    ) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=Number(self_ptr[].value * o[].value))
        except:
            raise NotImplementedError()

    @staticmethod
    fn py__floordiv__(
        self_ptr: UnsafePointer[Self, MutAnyOrigin], other: PythonObject
    ) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=Number(self_ptr[].value // o[].value))
        except:
            raise NotImplementedError()

    @staticmethod
    fn py__mod__(
        self_ptr: UnsafePointer[Self, MutAnyOrigin], other: PythonObject
    ) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=Number(self_ptr[].value % o[].value))
        except:
            raise NotImplementedError()

    @staticmethod
    fn py__and__(
        self_ptr: UnsafePointer[Self, MutAnyOrigin], other: PythonObject
    ) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=Number(self_ptr[].value & o[].value))
        except:
            raise NotImplementedError()

    @staticmethod
    fn py__or__(
        self_ptr: UnsafePointer[Self, MutAnyOrigin], other: PythonObject
    ) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=Number(self_ptr[].value | o[].value))
        except:
            raise NotImplementedError()

    @staticmethod
    fn py__xor__(
        self_ptr: UnsafePointer[Self, MutAnyOrigin], other: PythonObject
    ) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=Number(self_ptr[].value ^ o[].value))
        except:
            raise NotImplementedError()

    @staticmethod
    fn py__lshift__(
        self_ptr: UnsafePointer[Self, MutAnyOrigin], other: PythonObject
    ) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=Number(self_ptr[].value << o[].value))
        except:
            raise NotImplementedError()

    @staticmethod
    fn py__rshift__(
        self_ptr: UnsafePointer[Self, MutAnyOrigin], other: PythonObject
    ) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=Number(self_ptr[].value >> o[].value))
        except:
            raise NotImplementedError()

    # ------------------------------------------------------------------
    # Ternary slot
    # ------------------------------------------------------------------

    @staticmethod
    fn py__pow__(
        self_ptr: UnsafePointer[Self, MutAnyOrigin],
        exp: PythonObject,
        mod: PythonObject,
    ) raises -> PythonObject:
        try:
            var e = exp.downcast_value_ptr[Self]()
            var result = Int(Float64(self_ptr[].value) ** Float64(e[].value))
            return PythonObject(alloc=Number(result))
        except:
            raise NotImplementedError()

    fn write_to(self, mut writer: Some[Writer]):
        writer.write("Number(", self.value, ")")


# NumberV uses value-receiver handlers.  Simple unary/bool slots are
# non-raising; binary slots that need NotImplementedError are raising.
struct NumberV(Defaultable, Movable, Writable):
    var value: Int

    fn __init__(out self):
        self.value = 0

    fn __init__(out self, value: Int):
        self.value = value

    @staticmethod
    fn _get_self_ptr(
        py_self: PythonObject,
    ) -> UnsafePointer[Self, MutAnyOrigin]:
        try:
            return py_self.downcast_value_ptr[Self]()
        except e:
            abort(String("downcast failed: ", e))

    @staticmethod
    fn new(value: PythonObject) raises -> PythonObject:
        return PythonObject(alloc=NumberV(Int(py=value)))

    @staticmethod
    fn get_value(py_self: PythonObject) raises -> PythonObject:
        return PythonObject(Self._get_self_ptr(py_self)[].value)

    # Value-receiver handlers — unary slots return a new Python-boxed NumberV
    fn py__neg__(self) raises -> PythonObject:
        return PythonObject(alloc=NumberV(-self.value))

    fn py__abs__(self) raises -> PythonObject:
        return PythonObject(alloc=NumberV(abs(self.value)))

    fn py__pos__(self) raises -> PythonObject:
        return PythonObject(alloc=NumberV(self.value))

    fn py__invert__(self) raises -> PythonObject:
        return PythonObject(alloc=NumberV(~self.value))

    fn py__bool__(self) -> Bool:
        return self.value != 0

    fn py__int__(self) raises -> PythonObject:
        return PythonObject(self.value)

    fn py__float__(self) raises -> PythonObject:
        return PythonObject(Float64(self.value))

    fn py__index__(self) raises -> PythonObject:
        return PythonObject(self.value)

    # Raising value receivers for binary slots (need NotImplementedError)
    fn py__add__(self, other: PythonObject) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=NumberV(self.value + o[].value))
        except:
            raise NotImplementedError()

    fn py__sub__(self, other: PythonObject) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=NumberV(self.value - o[].value))
        except:
            raise NotImplementedError()

    fn py__mul__(self, other: PythonObject) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=NumberV(self.value * o[].value))
        except:
            raise NotImplementedError()

    fn py__floordiv__(self, other: PythonObject) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=NumberV(self.value // o[].value))
        except:
            raise NotImplementedError()

    fn py__mod__(self, other: PythonObject) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=NumberV(self.value % o[].value))
        except:
            raise NotImplementedError()

    fn py__and__(self, other: PythonObject) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=NumberV(self.value & o[].value))
        except:
            raise NotImplementedError()

    fn py__or__(self, other: PythonObject) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=NumberV(self.value | o[].value))
        except:
            raise NotImplementedError()

    fn py__xor__(self, other: PythonObject) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=NumberV(self.value ^ o[].value))
        except:
            raise NotImplementedError()

    fn py__lshift__(self, other: PythonObject) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=NumberV(self.value << o[].value))
        except:
            raise NotImplementedError()

    fn py__rshift__(self, other: PythonObject) raises -> PythonObject:
        try:
            var o = other.downcast_value_ptr[Self]()
            return PythonObject(alloc=NumberV(self.value >> o[].value))
        except:
            raise NotImplementedError()

    fn py__pow__(
        self, exp: PythonObject, mod: PythonObject
    ) raises -> PythonObject:
        try:
            var e = exp.downcast_value_ptr[Self]()
            var result = Int(Float64(self.value) ** Float64(e[].value))
            return PythonObject(alloc=NumberV(result))
        except:
            raise NotImplementedError()

    fn write_to(self, mut writer: Some[Writer]):
        writer.write("NumberV(", self.value, ")")


@export
fn PyInit_mojo_module() -> PythonObject:
    try:
        var b = PythonModuleBuilder("mojo_module")
        ref tb = (
            b.add_type[Number]("Number")
            .def_init_defaultable[Number]()
            .def_staticmethod[Number.new]("new")
            .def_method[Number.get_value]("get_value")
        )
        var npb = NumberProtocolBuilder[Number](tb)
        _ = (
            npb.def_neg[Number.py__neg__]()
            .def_abs[Number.py__abs__]()
            .def_pos[Number.py__pos__]()
            .def_invert[Number.py__invert__]()
            .def_bool[Number.py__bool__]()
            .def_int[Number.py__int__]()
            .def_float[Number.py__float__]()
            .def_index[Number.py__index__]()
            .def_add[Number.py__add__]()
            .def_sub[Number.py__sub__]()
            .def_mul[Number.py__mul__]()
            .def_floordiv[Number.py__floordiv__]()
            .def_mod[Number.py__mod__]()
            .def_and[Number.py__and__]()
            .def_or[Number.py__or__]()
            .def_xor[Number.py__xor__]()
            .def_lshift[Number.py__lshift__]()
            .def_rshift[Number.py__rshift__]()
            .def_pow[Number.py__pow__]()
        )
        ref tbv = (
            b.add_type[NumberV]("NumberV")
            .def_init_defaultable[NumberV]()
            .def_staticmethod[NumberV.new]("new")
            .def_method[NumberV.get_value]("get_value")
        )
        var npbv = NumberProtocolBuilder[NumberV](tbv)
        _ = (
            npbv.def_neg[NumberV.py__neg__]()
            .def_abs[NumberV.py__abs__]()
            .def_pos[NumberV.py__pos__]()
            .def_invert[NumberV.py__invert__]()
            .def_bool[NumberV.py__bool__]()
            .def_int[NumberV.py__int__]()
            .def_float[NumberV.py__float__]()
            .def_index[NumberV.py__index__]()
            .def_add[NumberV.py__add__]()
            .def_sub[NumberV.py__sub__]()
            .def_mul[NumberV.py__mul__]()
            .def_floordiv[NumberV.py__floordiv__]()
            .def_mod[NumberV.py__mod__]()
            .def_and[NumberV.py__and__]()
            .def_or[NumberV.py__or__]()
            .def_xor[NumberV.py__xor__]()
            .def_lshift[NumberV.py__lshift__]()
            .def_rshift[NumberV.py__rshift__]()
            .def_pow[NumberV.py__pow__]()
        )
        return b.finalize()
    except e:
        abort(String("failed to create Python module: ", e))
