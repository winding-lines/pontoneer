# ===----------------------------------------------------------------------=== #
# CPython type-slot index constants.
#
# These mirror the slot indices in CPython's Include/typeslots.h.  In the
# upstreamed version (https://github.com/modular/modular/pull/6453) these live
# in stdlib's `_cpython.mojo`; here, as a standalone library, they are kept in
# this internal module.  Do not renumber — they are part of the stable ABI.
# ref: https://github.com/python/cpython/blob/main/Include/typeslots.h
#
# Internal: not re-exported from `__init__.mojo`.
# ===----------------------------------------------------------------------=== #


struct _PySlotIndex:
    # Buffer protocol
    comptime bf_getbuffer = Int32(1)
    comptime bf_releasebuffer = Int32(2)
    # Mapping protocol
    comptime mp_setitem = Int32(3)  # mp_ass_subscript
    comptime mp_length = Int32(4)
    comptime mp_getitem = Int32(5)  # mp_subscript
    # Number protocol
    comptime nb_absolute = Int32(6)
    comptime nb_add = Int32(7)
    comptime nb_and = Int32(8)
    comptime nb_bool = Int32(9)
    comptime nb_divmod = Int32(10)
    comptime nb_float = Int32(11)
    comptime nb_floor_divide = Int32(12)
    comptime nb_index = Int32(13)
    comptime nb_inplace_add = Int32(14)
    comptime nb_inplace_and = Int32(15)
    comptime nb_inplace_floor_divide = Int32(16)
    comptime nb_inplace_lshift = Int32(17)
    comptime nb_inplace_multiply = Int32(18)
    comptime nb_inplace_or = Int32(19)
    comptime nb_inplace_power = Int32(20)
    comptime nb_inplace_remainder = Int32(21)
    comptime nb_inplace_rshift = Int32(22)
    comptime nb_inplace_subtract = Int32(23)
    comptime nb_inplace_true_divide = Int32(24)
    comptime nb_inplace_xor = Int32(25)
    comptime nb_int = Int32(26)
    comptime nb_invert = Int32(27)
    comptime nb_lshift = Int32(28)
    comptime nb_multiply = Int32(29)
    comptime nb_negative = Int32(30)
    comptime nb_or = Int32(31)
    comptime nb_positive = Int32(32)
    comptime nb_power = Int32(33)
    comptime nb_remainder = Int32(34)
    comptime nb_rshift = Int32(35)
    comptime nb_subtract = Int32(36)
    comptime nb_true_divide = Int32(37)
    comptime nb_xor = Int32(38)
    # Sequence protocol
    comptime sq_ass_item = Int32(39)
    comptime sq_concat = Int32(40)
    comptime sq_contains = Int32(41)
    comptime sq_inplace_concat = Int32(42)
    comptime sq_inplace_repeat = Int32(43)
    comptime sq_item = Int32(44)
    comptime sq_length = Int32(45)
    comptime sq_repeat = Int32(46)
    # Type protocol
    comptime tp_alloc = Int32(47)
    comptime tp_base = Int32(48)
    comptime tp_bases = Int32(49)
    comptime tp_call = Int32(50)
    comptime tp_clear = Int32(51)
    comptime tp_dealloc = Int32(52)
    comptime tp_del = Int32(53)
    comptime tp_descr_get = Int32(54)
    comptime tp_descr_set = Int32(55)
    comptime tp_doc = Int32(56)
    comptime tp_getattr = Int32(57)
    comptime tp_getattro = Int32(58)
    comptime tp_hash = Int32(59)
    comptime tp_init = Int32(60)
    comptime tp_is_gc = Int32(61)
    comptime tp_iter = Int32(62)
    comptime tp_iternext = Int32(63)
    comptime tp_methods = Int32(64)
    comptime tp_new = Int32(65)
    comptime tp_repr = Int32(66)
    comptime tp_richcompare = Int32(67)
    comptime tp_setattr = Int32(68)
    comptime tp_setattro = Int32(69)
    comptime tp_str = Int32(70)
    comptime tp_traverse = Int32(71)
    comptime tp_members = Int32(72)
    comptime tp_getset = Int32(73)
    comptime tp_free = Int32(74)
    comptime nb_matrix_multiply = Int32(75)
    comptime nb_inplace_matrix_multiply = Int32(76)
    # Async protocol (Python 3.5+)
    comptime am_await = Int32(77)
    comptime am_aiter = Int32(78)
    comptime am_anext = Int32(79)
    comptime tp_finalize = Int32(80)  # Python 3.5+
    comptime am_send = Int32(81)  # Python 3.10+
    comptime tp_vectorcall = Int32(82)  # Python 3.14+
    comptime tp_token = Int32(83)  # Python 3.14+
