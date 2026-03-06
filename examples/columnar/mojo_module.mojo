# ===----------------------------------------------------------------------=== #
# Example from https://github.com/modular/modular/pull/5562, adapted to use
# the pontoneer library instead of the stdlib additions directly.
#
# Exposes a simple columnar DataFrame to Python that supports:
#   - len(df)          via mp_length
#   - df[i]            via mp_subscript
#   - df[i] = (x, y)  via mp_ass_subscript
#   - del df[i]        via mp_ass_subscript (null value)
#   - df < other       via tp_richcompare
# ===----------------------------------------------------------------------=== #

from std.os import abort
from std.memory import UnsafePointer
from std.utils import Variant
from std.python import Python, PythonObject
from std.python.bindings import PythonModuleBuilder

from pontoneer import (
    PyTypeObjectSlot,
    NotImplementedError,
    RichCompareOps,
    PontoneerTypeBuilder,
)

comptime Coord1DColumn = List[Float64]


fn _extent(pos: Coord1DColumn) -> Tuple[Float64, Float64]:
    """Return the (min, max) of a column."""
    v_min = Float64.MAX
    v_max = Float64.MIN
    for v in pos:
        v_min = min(v_min, v)
        v_max = max(v_max, v)
    return (v_min, v_max)


fn _compute_bounding_box_area(
    pos_x: Coord1DColumn,
    pos_y: Coord1DColumn,
) -> Float64:
    if len(pos_x) == 0:
        return 0.0
    ext_x = _extent(pos_x)
    ext_y = _extent(pos_y)
    return (ext_x[1] - ext_x[0]) * (ext_y[1] - ext_y[0])


struct DataFrame(Defaultable, Movable, Writable):
    """A simple columnar data structure storing 2-D points.

    x and y coordinates are stored in separate columns for cache-friendly
    access patterns.  Used here to demonstrate the mapping protocol and
    rich comparison protocol via pontoneer.
    """

    var pos_x: Coord1DColumn
    var pos_y: Coord1DColumn
    var call_counts: Dict[String, Int]
    var _bounding_box_area: Float64

    fn __init__(out self):
        self.pos_x = []
        self.pos_y = []
        self._bounding_box_area = 0
        self.call_counts = {}

    fn __init__(
        out self,
        var x: Coord1DColumn,
        var y: Coord1DColumn,
    ):
        self._bounding_box_area = _compute_bounding_box_area(x, y)
        self.pos_x = x^
        self.pos_y = y^
        self.call_counts = {}

    @staticmethod
    fn _get_self_ptr(
        py_self: PythonObject,
    ) -> UnsafePointer[Self, MutAnyOrigin]:
        try:
            return py_self.downcast_value_ptr[Self]()
        except e:
            abort(
                String(
                    "Python method receiver did not have the expected type: ",
                    e,
                )
            )

    # ------------------------------------------------------------------
    # Regular methods
    # ------------------------------------------------------------------

    @staticmethod
    fn get_call_count(
        py_self: PythonObject, name: PythonObject
    ) raises -> PythonObject:
        """Return the number of times a named method was called (for testing)."""
        var self_ptr = Self._get_self_ptr(py_self)
        return self_ptr[].call_counts.get(String(py=name), 0)

    @staticmethod
    fn with_columns(
        pos_x: PythonObject, pos_y: PythonObject
    ) raises -> PythonObject:
        var len_x = Int(pos_x.__len__())
        var len_y = Int(pos_y.__len__())
        if len_x != len_y:
            raise Error("The length of the two columns does not match.")
        var ptr_x = Coord1DColumn(capacity=len_x)
        var ptr_y = Coord1DColumn(capacity=len_y)
        for value in pos_x:
            ptr_x.append(Float64(py=value))
        for value in pos_y:
            ptr_y.append(Float64(py=value))
        return PythonObject(alloc=DataFrame(ptr_x^, ptr_y^))

    # ------------------------------------------------------------------
    # Mapping protocol
    # ------------------------------------------------------------------

    @staticmethod
    fn py__len__(py_self: PythonObject) raises -> Int:
        var self_ptr = Self._get_self_ptr(py_self)
        return len(self_ptr[].pos_x)

    @staticmethod
    fn py__getitem__(
        py_self: PythonObject, index: PythonObject
    ) raises -> PythonObject:
        var self_ptr = Self._get_self_ptr(py_self)
        var i = Int(py=index)
        var length = len(self_ptr[].pos_x)
        if i < 0 or i >= length:
            raise Error("index out of range")
        return Python().tuple(
            self_ptr[].pos_x[i], self_ptr[].pos_y[i]
        )

    @staticmethod
    fn py__setitem__(
        py_self: PythonObject,
        index: PythonObject,
        value: Variant[PythonObject, Int],
    ) raises -> None:
        var self_ptr = Self._get_self_ptr(py_self)
        var i = Int(py=index)
        var length = len(self_ptr[].pos_x)
        if i < 0 or i >= length:
            raise Error("index out of range")
        if value.isa[PythonObject]():
            # Assignment: value is a (x, y) tuple.
            self_ptr[].pos_x[i] = Float64(py=value[PythonObject][0])
            self_ptr[].pos_y[i] = Float64(py=value[PythonObject][1])
        else:
            # Deletion (value is null / Int(0)).
            _ = self_ptr[].pos_x.pop(i)
            _ = self_ptr[].pos_y.pop(i)

    # ------------------------------------------------------------------
    # Rich comparison protocol
    # ------------------------------------------------------------------

    @staticmethod
    fn rich_compare(
        self_ptr: PythonObject, other: PythonObject, op: Int
    ) raises -> Bool:
        """Compare DataFrames by bounding-box area.

        Only LT and EQ are implemented; all other operations raise
        NotImplementedError so Python falls back to the reflected call.
        """
        var self_df = Self._get_self_ptr(self_ptr)
        var invocation = "rich_compare[{}]".format(op)
        self_df[].call_counts[invocation] = (
            self_df[].call_counts.get(invocation, 0) + 1
        )
        var other_df = Self._get_self_ptr(other)
        if op == RichCompareOps.Py_LT:
            return self_df[]._bounding_box_area < other_df[]._bounding_box_area
        if op == RichCompareOps.Py_EQ:
            return self_df[]._bounding_box_area == other_df[]._bounding_box_area
        raise NotImplementedError()

    fn write_to(self, mut writer: Some[Writer]):
        writer.write("DataFrame( length=", len(self.pos_x), ")")


@export
fn PyInit_mojo_module() -> PythonObject:
    """Entry point: create the Python extension module."""
    try:
        var b = PythonModuleBuilder("mojo_module")

        var tb = b.add_type[DataFrame]("DataFrame")
            .def_init_defaultable[DataFrame]()
            .def_staticmethod[DataFrame.with_columns]("with_columns")
            .def_method[DataFrame.get_call_count]("get_call_count")

        _ = PontoneerTypeBuilder(tb^)
            .def_method[DataFrame.py__len__,    PyTypeObjectSlot.mp_length]()
            .def_method[DataFrame.py__getitem__, PyTypeObjectSlot.mp_getitem]()
            .def_method[DataFrame.py__setitem__, PyTypeObjectSlot.mp_setitem]()
            .def_method[
                DataFrame.rich_compare, PyTypeObjectSlot.tp_richcompare
            ]()

        return b.finalize()
    except e:
        abort(String("failed to create Python module: ", e))
