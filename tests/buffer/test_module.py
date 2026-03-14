"""Integration test for BufferProtocolBuilder (bf_getbuffer, bf_releasebuffer)."""

import mojo_module


def test_buffer_protocol() -> None:
    print("Testing buffer protocol...")

    obj = mojo_module.FloatBuffer.from_count(4)

    # memoryview basics
    mv = memoryview(obj)
    assert mv.format == "d", f"expected format 'd', got {mv.format!r}"
    assert mv.itemsize == 8, f"expected itemsize 8, got {mv.itemsize}"
    assert len(mv) == 4, f"expected len 4, got {len(mv)}"
    assert mv.readonly, "expected readonly buffer"
    print("  memoryview basics: ok")

    # element access via memoryview
    assert mv[0] == 0.0
    assert mv[1] == 1.0
    assert mv[2] == 2.0
    assert mv[3] == 3.0
    print("  memoryview element access: ok")

    # tolist()
    assert mv.tolist() == [0.0, 1.0, 2.0, 3.0]
    print("  memoryview tolist: ok")

    # bytes() round-trip: struct.unpack should recover the original doubles
    import struct

    raw = bytes(mv)
    unpacked = struct.unpack("4d", raw)
    assert unpacked == (0.0, 1.0, 2.0, 3.0), f"struct unpack mismatch: {unpacked}"
    print("  bytes/struct round-trip: ok")

    # numpy (optional — skip gracefully if not installed)
    try:
        import numpy as np

        arr = np.frombuffer(obj, dtype=np.float64)
        assert arr.shape == (4,), f"expected shape (4,), got {arr.shape}"
        assert list(arr) == [0.0, 1.0, 2.0, 3.0], f"numpy values mismatch: {list(arr)}"
        print("  numpy.frombuffer: ok")
    except ImportError:
        print("  numpy not available, skipping numpy test")

    # Empty buffer
    empty = mojo_module.FloatBuffer.from_count(0)
    mv_empty = memoryview(empty)
    assert len(mv_empty) == 0
    print("  empty buffer: ok")

    print("Buffer protocol tests passed!")


if __name__ == "__main__":
    test_buffer_protocol()
