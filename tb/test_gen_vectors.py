"""Host-side checks for the Stage 3 quantized inference vectors."""

import tempfile
import unittest
from pathlib import Path

import numpy as np

from gen_vectors import make_demo_vectors, save_vectors


class InferenceVectorTest(unittest.TestCase):
    def test_generation_is_deterministic_and_well_shaped(self) -> None:
        first = make_demo_vectors(n=4)
        second = make_demo_vectors(n=4)

        for name in (
            "input_float",
            "weight_float",
            "bias_float",
            "input_q",
            "weight_q",
            "bias_q",
        ):
            np.testing.assert_array_equal(getattr(first, name), getattr(second, name))

        self.assertEqual(first.input_q.shape, (4, 8))
        self.assertEqual(first.weight_q.shape, (8, 4))
        self.assertEqual(first.bias_q.shape, (4,))
        self.assertGreater(first.input_scale, 0.0)
        self.assertGreater(first.weight_scale, 0.0)
        self.assertTrue(np.all(first.input_q <= 127))
        self.assertTrue(np.all(first.input_q >= -127))
        self.assertTrue(np.all(first.weight_q <= 127))
        self.assertTrue(np.all(first.weight_q >= -127))

    def test_integer_reference_and_error_bound(self) -> None:
        vectors = make_demo_vectors(n=4)
        explicit = (
            vectors.input_q.astype(np.int32) @ vectors.weight_q.astype(np.int32)
            + vectors.bias_q[np.newaxis, :]
        )
        np.testing.assert_array_equal(vectors.quantized_accumulator, explicit)
        error = np.abs(vectors.dequantized_output - vectors.reference_float)
        np.testing.assert_array_less(error, vectors.absolute_error_bound + 1.0e-10)

    def test_npz_round_trip(self) -> None:
        vectors = make_demo_vectors(n=2)
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "vectors.npz"
            save_vectors(vectors, output)
            with np.load(output) as loaded:
                np.testing.assert_array_equal(loaded["input_q"], vectors.input_q)
                np.testing.assert_array_equal(loaded["weight_q"], vectors.weight_q)
                np.testing.assert_array_equal(loaded["bias_q"], vectors.bias_q)
                self.assertEqual(int(loaded["input_zero_point"]), 0)
                self.assertEqual(int(loaded["weight_zero_point"]), 0)


if __name__ == "__main__":
    unittest.main()
