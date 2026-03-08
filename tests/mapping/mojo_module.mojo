# ===----------------------------------------------------------------------=== #
# Test for MappingProtocolBuilder.
#
# Exposes a SimpleList type to Python that supports:
#   - len(obj)       via mp_length
#   - obj[i]         via mp_subscript
#   - obj[i] = v     via mp_ass_subscript (assignment)
#   - del obj[i]     via mp_ass_subscript (deletion)
# ===----------------------------------------------------------------------=== #

from std.os import abort
from std.memory import UnsafePointer
from std.utils import Variant
from std.python import PythonObject
from std.python.bindings import PythonModuleBuilder

from pontoneer import MappingProtocolBuilder


struct SimpleList(Defaultable, Movable, Writable):
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
        var result = SimpleList()
        for item in items:
            result.data.append(Int(py=item))
        return PythonObject(alloc=result^)

    @staticmethod
    fn py__len__(py_self: PythonObject) raises -> Int:
        return len(Self._get_self_ptr(py_self)[].data)

    @staticmethod
    fn py__getitem__(
        py_self: PythonObject, index: PythonObject
    ) raises -> PythonObject:
        var ptr = Self._get_self_ptr(py_self)
        var i = Int(py=index)
        if i < 0 or i >= len(ptr[].data):
            raise Error("index out of range")
        return PythonObject(ptr[].data[i])

    @staticmethod
    fn py__setitem__(
        py_self: PythonObject,
        index: PythonObject,
        value: Variant[PythonObject, Int],
    ) raises -> None:
        var ptr = Self._get_self_ptr(py_self)
        var i = Int(py=index)
        if i < 0 or i >= len(ptr[].data):
            raise Error("index out of range")
        if value.isa[PythonObject]():
            ptr[].data[i] = Int(py=value[PythonObject])
        else:
            _ = ptr[].data.pop(i)

    fn write_to(self, mut writer: Some[Writer]):
        writer.write("SimpleList(len=", len(self.data), ")")


@export
fn PyInit_mojo_module() -> PythonObject:
    try:
        var b = PythonModuleBuilder("mojo_module")
        ref tb = (
            b.add_type[SimpleList]("SimpleList")
            .def_init_defaultable[SimpleList]()
            .def_staticmethod[SimpleList.from_list]("from_list")
        )
        var mpb = MappingProtocolBuilder(tb)
        _ = (
            mpb.def_len[SimpleList.py__len__]()
            .def_getitem[SimpleList.py__getitem__]()
            .def_setitem[SimpleList.py__setitem__]()
        )
        return b.finalize()
    except e:
        abort(String("failed to create Python module: ", e))
