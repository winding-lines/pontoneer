"""Integration test for NumberProtocolBuilder (unary, bool, conversion, binary, ternary slots)."""

import operator
import mojo_module


def n(v: int) -> mojo_module.Number:
    return mojo_module.Number.new(v)


def val(x: mojo_module.Number) -> int:
    return x.get_value()


def test_number_protocol() -> None:
    print("Testing number protocol...")

    # __neg__ (nb_negative)
    assert val(-n(7)) == -7
    assert val(-n(-3)) == 3

    # __abs__ (nb_absolute)
    assert val(abs(n(-5))) == 5
    assert val(abs(n(5))) == 5

    # __pos__ (nb_positive)
    assert val(+n(4)) == 4

    # __invert__ (nb_invert)
    assert val(~n(0)) == -1
    assert val(~n(6)) == -7

    # __bool__ (nb_bool)
    assert bool(n(1))
    assert bool(n(-1))
    assert not bool(n(0))

    # __int__ (nb_int)
    assert int(n(42)) == 42

    # __float__ (nb_float)
    assert float(n(3)) == 3.0

    # __index__ (nb_index)
    assert operator.index(n(10)) == 10
    # __index__ also enables use as a sequence index
    lst = [0, 1, 2, 3]
    assert lst[n(2)] == 2

    # __add__ (nb_add)
    assert val(n(3) + n(4)) == 7

    # __add__ with non-Number returns NotImplemented → TypeError
    try:
        _ = n(1) + 42
        raise Exception("TypeError expected")
    except TypeError:
        pass

    # __sub__ (nb_subtract)
    assert val(n(10) - n(3)) == 7

    # __mul__ (nb_multiply)
    assert val(n(6) * n(7)) == 42

    # __floordiv__ (nb_floor_divide)
    assert val(n(17) // n(5)) == 3

    # __mod__ (nb_remainder)
    assert val(n(17) % n(5)) == 2

    # __and__ (nb_and)
    assert val(n(0b1100) & n(0b1010)) == 0b1000

    # __or__ (nb_or)
    assert val(n(0b1100) | n(0b1010)) == 0b1110

    # __xor__ (nb_xor)
    assert val(n(0b1100) ^ n(0b1010)) == 0b0110

    # __lshift__ (nb_lshift)
    assert val(n(1) << n(4)) == 16

    # __rshift__ (nb_rshift)
    assert val(n(32) >> n(2)) == 8

    # __pow__ (nb_power)
    assert val(n(2) ** n(10)) == 1024
    assert val(n(3) ** n(3)) == 27

    print("Number protocol tests passed!")


if __name__ == "__main__":
    test_number_protocol()
