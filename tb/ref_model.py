"""Bit-exact reference operations for the systolic-array test suite.

The accelerator multiplies signed int8 operands and accumulates products in
signed int32.  NumPy's default int8 matmul can overflow before accumulation,
so operands are widened explicitly before multiplication.
"""

from __future__ import annotations

import numpy as np


def int8_matmul(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Return ``a @ b`` with int8 inputs and int32 wraparound accumulation.

    Args:
        a: Rank-2 matrix interpreted as signed int8.
        b: Rank-2 matrix interpreted as signed int8.

    Raises:
        ValueError: If either operand is not rank-2 or their reduction
            dimensions differ.
    """

    a_int8 = np.asarray(a, dtype=np.int8)
    b_int8 = np.asarray(b, dtype=np.int8)

    if a_int8.ndim != 2 or b_int8.ndim != 2:
        raise ValueError("int8_matmul expects two rank-2 matrices")
    if a_int8.shape[1] != b_int8.shape[0]:
        raise ValueError(
            "incompatible matmul shapes: "
            f"{a_int8.shape} and {b_int8.shape}"
        )

    return a_int8.astype(np.int32) @ b_int8.astype(np.int32)
