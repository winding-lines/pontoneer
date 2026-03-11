# ===----------------------------------------------------------------------=== #
# Test for TypeProtocolBuilder.
#
# Exposes a Box type (wrapping Float64) to Python that supports all six
# rich comparison operators via tp_richcompare:
#   - box1 < box2    Py_LT
#   - box1 <= box2   Py_LE
#   - box1 == box2   Py_EQ
#   - box1 != box2   Py_NE
#   - box1 > box2    Py_GT
#   - box1 >= box2   Py_GE
# ===----------------------------------------------------------------------=== #

from std.os import abort
from std.memory import UnsafePointer
from std.python import PythonObject
from std.python.bindings import PythonModuleBuilder

from pontoneer import NotImplementedError, RichCompareOps, TypeProtocolBuilder


struct Box(Defaultable, Movable, Writable):
    var value: Float64

    fn __init__(out self):
        self.value = 0.0

    fn __init__(out self, value: Float64):
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
        return PythonObject(alloc=Box(Float64(py=value)))

    @staticmethod
    fn get_value(py_self: PythonObject) raises -> PythonObject:
        return PythonObject(Self._get_self_ptr(py_self)[].value)

    @staticmethod
    fn rich_compare(
        self_ptr: UnsafePointer[Self, MutAnyOrigin], other: PythonObject, op: Int
    ) raises -> Bool:
        var a = self_ptr[].value
        var b = other.downcast_value_ptr[Self]()[].value
        if op == RichCompareOps.Py_LT:
            return a < b
        if op == RichCompareOps.Py_LE:
            return a <= b
        if op == RichCompareOps.Py_EQ:
            return a == b
        if op == RichCompareOps.Py_NE:
            return a != b
        if op == RichCompareOps.Py_GT:
            return a > b
        if op == RichCompareOps.Py_GE:
            return a >= b
        raise NotImplementedError()

    fn write_to(self, mut writer: Some[Writer]):
        writer.write("Box(", self.value, ")")


@export
fn PyInit_mojo_module() -> PythonObject:
    try:
        var b = PythonModuleBuilder("mojo_module")
        ref tb = (
            b.add_type[Box]("Box")
            .def_init_defaultable[Box]()
            .def_staticmethod[Box.new]("new")
            .def_method[Box.get_value]("get_value")
        )
        var tpb = TypeProtocolBuilder[Box](tb)
        _ = tpb.def_richcompare[Box.rich_compare]()
        return b.finalize()
    except e:
        abort(String("failed to create Python module: ", e))
