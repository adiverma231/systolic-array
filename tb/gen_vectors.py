"""Generate the deterministic quantized fully-connected demo vectors.

The hardware consumes signed symmetric int8 operands and produces an int32
accumulator.  This module keeps the floating-point layer, quantized operands,
scales, and quantized bias together so the cocotb test and the standalone CLI
use exactly the same convention:

    x_q = round(x / input_scale)
    w_q = round(w / weight_scale)
    y_q = x_q @ w_q + bias_q
    y ~= y_q * (input_scale * weight_scale)

All zero-points are zero.  The default layer has N input rows, N outputs, and
2*N input features, which exercises two reduction tiles on the N-wide top
interface without requiring padding.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

import numpy as np


DEFAULT_SEED = 0x3A17_2026


def quantize_symmetric(values: np.ndarray) -> tuple[np.ndarray, float]:
    """Quantize a floating-point tensor to signed symmetric int8.

    The usable symmetric range is -127..127, leaving -128 available as an
    ordinary int8 value while keeping the zero-point exactly zero.
    """

    floating = np.asarray(values, dtype=np.float64)
    peak = float(np.max(np.abs(floating)))
    scale = peak / 127.0 if peak > 0.0 else 1.0
    quantized = np.rint(floating / scale).clip(-127, 127).astype(np.int8)
    return quantized, scale


@dataclass(frozen=True)
class InferenceVectors:
    """One reproducible floating-point layer and its quantized representation."""

    input_float: np.ndarray
    weight_float: np.ndarray
    bias_float: np.ndarray
    input_q: np.ndarray
    weight_q: np.ndarray
    bias_q: np.ndarray
    input_scale: float
    weight_scale: float
    output_scale: float

    @property
    def reference_float(self) -> np.ndarray:
        """Unquantized layer output used as the accuracy reference."""

        return self.input_float @ self.weight_float + self.bias_float

    @property
    def quantized_accumulator(self) -> np.ndarray:
        """Expected int32 result before dequantization."""

        product = self.input_q.astype(np.int32) @ self.weight_q.astype(np.int32)
        return product + self.bias_q[np.newaxis, :]

    @property
    def dequantized_output(self) -> np.ndarray:
        """Expected output after converting the int32 result back to float."""

        return self.quantized_accumulator.astype(np.float64) * self.output_scale

    @property
    def absolute_error_bound(self) -> np.ndarray:
        """Conservative elementwise bound for round-to-nearest quantization."""

        features = self.input_float.shape[1]
        input_error = 0.5 * self.input_scale
        weight_error = 0.5 * self.weight_scale
        bias_error = 0.5 * self.output_scale

        # |(x+dx)(w+dw)-xw| <= |w||dx| + |x||dw| + |dx||dw|.
        bound = (
            np.sum(np.abs(self.weight_float), axis=0)[np.newaxis, :] * input_error
            + np.sum(np.abs(self.input_float), axis=1)[:, np.newaxis] * weight_error
            + features * input_error * weight_error
            + bias_error
        )
        # Include a tiny numerical margin for the float multiply/add path.
        return bound + 4.0 * np.finfo(np.float64).eps


def make_demo_vectors(
    n: int = 4,
    input_features: int | None = None,
    seed: int = DEFAULT_SEED,
) -> InferenceVectors:
    """Build a deterministic small fully-connected inference problem."""

    if n < 1:
        raise ValueError("n must be positive")
    if input_features is None:
        input_features = 2 * n
    if input_features < 1 or input_features % n:
        raise ValueError("input_features must be a positive multiple of n")

    rng = np.random.default_rng(seed)
    batch = n
    outputs = n

    # Fixed ranges keep the quantization error easy to interpret while still
    # producing signed values and nontrivial bias contributions.
    input_float = rng.uniform(-1.15, 1.15, size=(batch, input_features))
    weight_float = rng.uniform(-0.75, 0.75, size=(input_features, outputs))
    bias_float = rng.uniform(-0.20, 0.20, size=(outputs,))

    input_q, input_scale = quantize_symmetric(input_float)
    weight_q, weight_scale = quantize_symmetric(weight_float)
    output_scale = input_scale * weight_scale
    bias_q = np.rint(bias_float / output_scale).astype(np.int32)

    return InferenceVectors(
        input_float=input_float,
        weight_float=weight_float,
        bias_float=bias_float,
        input_q=input_q,
        weight_q=weight_q,
        bias_q=bias_q,
        input_scale=input_scale,
        weight_scale=weight_scale,
        output_scale=output_scale,
    )


def save_vectors(vectors: InferenceVectors, output: Path) -> None:
    """Write vectors and quantization metadata to a portable compressed NPZ."""

    output.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(
        output,
        input_float=vectors.input_float,
        weight_float=vectors.weight_float,
        bias_float=vectors.bias_float,
        input_q=vectors.input_q,
        weight_q=vectors.weight_q,
        bias_q=vectors.bias_q,
        input_scale=np.float64(vectors.input_scale),
        weight_scale=np.float64(vectors.weight_scale),
        output_scale=np.float64(vectors.output_scale),
        input_zero_point=np.int32(0),
        weight_zero_point=np.int32(0),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--n", type=int, default=4, help="array/output/batch dimension")
    parser.add_argument(
        "--input-features",
        type=int,
        default=None,
        help="input feature count (default: 2*n)",
    )
    parser.add_argument(
        "--seed",
        type=lambda value: int(value, 0),
        default=DEFAULT_SEED,
        help="random seed, accepting decimal or 0x-prefixed values",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="optional .npz output path",
    )
    args = parser.parse_args()

    vectors = make_demo_vectors(args.n, args.input_features, args.seed)
    if args.output is not None:
        save_vectors(vectors, args.output)
        print(f"wrote {args.output}")

    print(
        "demo layer: "
        f"input={vectors.input_float.shape}, weights={vectors.weight_float.shape}, "
        f"output_scale={vectors.output_scale:.8g}, seed=0x{args.seed:x}"
    )


if __name__ == "__main__":
    main()
