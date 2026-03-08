# ===----------------------------------------------------------------------=== #
# Test for SequenceProtocolBuilder.
#
# Exposes a Seq type to Python that supports:
#   - len(obj)       via sq_length
#   - obj[i]         via sq_item        (integer index)
#   - obj[i] = v     via sq_ass_item    (assignment)
#   - del obj[i]     via sq_ass_item    (deletion)
#   - v in obj       via sq_contains
#   - obj + other    via sq_concat
#   - obj * n        via sq_repeat
# ===----------------------------------------------------------------------=== #

from std.os import abort
from std.memory import UnsafePointer
from std.utils import Variant
from std.python import PythonObject
from std.python.bindings import PythonModuleBuilder

from pontoneer import SequenceProtocolBuilder


struct Seq(Defaultable, Movable, Writable):
    var data: List[Int]

    fn __init__(out self):
        self.data = []

    @staticmethod
    fn _get_self_ptr(
        py_self: PythonObject,
    ) -> UnsafePointer[Self, MutAnyOrigin]:
        try:
            return py_self.downcast_value_ptr[Self]()
        except e:
            abort(String("downcast failed: ", e))

    @staticmethod
    fn from_list(items: PythonObject) raises -> PythonObject:
        var result = Seq()
        for item in items:
            result.data.append(Int(py=item))
        return PythonObject(alloc=result^)

    @staticmethod
    fn py__len__(py_self: PythonObject) raises -> Int:
        return len(Self._get_self_ptr(py_self)[].data)

    @staticmethod
    fn py__getitem__(py_self: PythonObject, index: Int) raises -> PythonObject:
        var ptr = Self._get_self_ptr(py_self)
        if index < 0 or index >= len(ptr[].data):
            raise Error("index out of range")
        return PythonObject(ptr[].data[index])

    @staticmethod
    fn py__setitem__(
        py_self: PythonObject,
        index: Int,
        value: Variant[PythonObject, Int],
    ) raises -> None:
        var ptr = Self._get_self_ptr(py_self)
        if index < 0 or index >= len(ptr[].data):
            raise Error("index out of range")
        if value.isa[PythonObject]():
            ptr[].data[index] = Int(py=value[PythonObject])
        else:
            _ = ptr[].data.pop(index)

    @staticmethod
    fn py__contains__(py_self: PythonObject, item: PythonObject) raises -> Bool:
        var ptr = Self._get_self_ptr(py_self)
        var v = Int(py=item)
        for elem in ptr[].data:
            if elem == v:
                return True
        return False

    @staticmethod
    fn py__concat__(
        py_self: PythonObject, other: PythonObject
    ) raises -> PythonObject:
        var ptr = Self._get_self_ptr(py_self)
        var other_ptr = other.downcast_value_ptr[Self]()
        var result = Seq()
        for v in ptr[].data:
            result.data.append(v)
        for v in other_ptr[].data:
            result.data.append(v)
        return PythonObject(alloc=result^)

    @staticmethod
    fn py__repeat__(py_self: PythonObject, count: Int) raises -> PythonObject:
        var ptr = Self._get_self_ptr(py_self)
        var result = Seq()
        for _ in range(count):
            for v in ptr[].data:
                result.data.append(v)
        return PythonObject(alloc=result^)

    fn write_to(self, mut writer: Some[Writer]):
        writer.write("Seq(len=", len(self.data), ")")


@export
fn PyInit_mojo_module() -> PythonObject:
    try:
        var b = PythonModuleBuilder("mojo_module")
        ref tb = (
            b.add_type[Seq]("Seq")
            .def_init_defaultable[Seq]()
            .def_staticmethod[Seq.from_list]("from_list")
        )
        var spb = SequenceProtocolBuilder(tb)
        _ = (
            spb.def_len[Seq.py__len__]()
            .def_getitem[Seq.py__getitem__]()
            .def_setitem[Seq.py__setitem__]()
            .def_contains[Seq.py__contains__]()
            .def_concat[Seq.py__concat__]()
            .def_repeat[Seq.py__repeat__]()
        )
        return b.finalize()
    except e:
        abort(String("failed to create Python module: ", e))
