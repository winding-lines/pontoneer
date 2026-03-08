"""Integration test for TypeProtocolBuilder (tp_richcompare — all six operators)."""

import mojo_module


def box(v: float) -> mojo_module.Box:
    return mojo_module.Box.new(v)


def test_type_protocol() -> None:
    print("Testing type protocol (rich comparison)...")

    lo = box(1.0)
    hi = box(5.0)
    eq = box(1.0)

    # __lt__ (Py_LT)
    assert lo < hi
    assert not hi < lo
    assert not lo < eq

    # __le__ (Py_LE)
    assert lo <= hi
    assert lo <= eq
    assert not hi <= lo

    # __eq__ (Py_EQ)
    assert lo == eq
    assert not lo == hi

    # __ne__ (Py_NE)
    assert lo != hi
    assert not lo != eq

    # __gt__ (Py_GT)
    assert hi > lo
    assert not lo > hi
    assert not lo > eq

    # __ge__ (Py_GE)
    assert hi >= lo
    assert lo >= eq
    assert not lo >= hi

    # Sorting relies on __lt__
    boxes = [box(3.0), box(1.0), box(2.0)]
    boxes.sort()
    assert boxes[0].get_value() == 1.0
    assert boxes[1].get_value() == 2.0
    assert boxes[2].get_value() == 3.0

    print("Type protocol tests passed!")


if __name__ == "__main__":
    test_type_protocol()
