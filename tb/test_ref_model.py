"""Small host-side checks for the NumPy golden model."""

import unittest

import numpy as np

from ref_model import int8_matmul


class Int8MatmulTest(unittest.TestCase):
    def test_signed_extremes_widen_before_accumulation(self) -> None:
        a = np.array([[-128, 127], [3, -5]], dtype=np.int8)
        b = np.array([[-128, 4], [7, -128]], dtype=np.int8)

        actual = int8_matmul(a, b)

        # Calculate explicitly to make the intended arithmetic unambiguous.
        expected = np.array(
            [
                [(-128 * -128) + (127 * 7), (-128 * 4) + (127 * -128)],
                [(3 * -128) + (-5 * 7), (3 * 4) + (-5 * -128)],
            ],
            dtype=np.int32,
        )
        np.testing.assert_array_equal(actual, expected)

    def test_rejects_incompatible_shapes(self) -> None:
        with self.assertRaises(ValueError):
            int8_matmul(np.zeros((2, 3), dtype=np.int8), np.zeros((2, 2), dtype=np.int8))


if __name__ == "__main__":
    unittest.main()
