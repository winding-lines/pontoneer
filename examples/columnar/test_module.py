"""Integration test for the columnar DataFrame example.

Run via:
    pixi run test-example
"""

import mojo_module


def test_mojo_columnar() -> None:
    print("Hello from Basic Columnar Example!")

    # Mismatched column lengths should raise.
    try:
        _ = mojo_module.DataFrame.with_columns([1.0, 2.0, 3.0], [0.1, 0.2])
        raise Exception("ValueError expected due to unbalanced columns.")
    except Exception as ex:
        assert "not match" in str(ex)

    df = mojo_module.DataFrame.with_columns([1.0, 2.0, 3.0], [0.1, 0.2, 0.3])
    assert "DataFrame" in str(df)

    # __len__ (mp_length)
    assert len(df) == 3

    # __getitem__ (mp_subscript)
    assert df[0] == (1.0, 0.1)
    assert df[1] == (2.0, 0.2)

    # __setitem__ (mp_ass_subscript — assignment)
    df[1] = (5.0, 6.0)
    assert df[1] == (5.0, 6.0)
    assert df[0] == (1.0, 0.1)   # neighbours unchanged
    assert df[2] == (3.0, 0.3)

    # __delitem__ (mp_ass_subscript — deletion)
    for_delete = mojo_module.DataFrame.with_columns(
        [1.0, 2.0, 3.0], [0.1, 0.2, 0.3]
    )
    del for_delete[0]
    assert for_delete[0] == (2.0, 0.2)

    big_df = mojo_module.DataFrame.with_columns(
        [1.0, 2.0, 30000.0], [0.1, 0.2, 1.0]
    )

    def rich_compare_counts(
        d: mojo_module.DataFrame,
    ) -> tuple[int, int, int]:
        return tuple(
            d.get_call_count(f"rich_compare[{op}]") for op in (0, 2, 4)
        )

    # LT and EQ are implemented directly.
    assert df < big_df
    assert rich_compare_counts(df) == (1, 0, 0)
    assert rich_compare_counts(big_df) == (0, 0, 0)

    # GT is not implemented, so Python retries as LT on the other operand.
    assert big_df > df
    assert rich_compare_counts(df) == (2, 0, 0)
    assert rich_compare_counts(big_df) == (0, 0, 1)

    print("🎉🎉🎉 Mission Success! 🎉🎉🎉")


if __name__ == "__main__":
    test_mojo_columnar()
