"""Stage 3 quantized fully-connected inference check.

The demo layer has N input rows, N outputs, and 2*N input features.  The
feature dimension is split into two N-wide reduction tiles, each executed as
one public top-level transaction.  Python accumulates the two int32 tile
results, adds the quantized bias, dequantizes, and compares against the
original floating-point layer.
"""

from __future__ import annotations

import os

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge, Timer

from gen_vectors import make_demo_vectors


N = int(os.environ.get("N", "4"))
K = int(os.environ.get("K", str(N)))
DATA_WIDTH = 8
ACC_WIDTH = 32


async def clock_edge(dut) -> None:
    await RisingEdge(dut.clk)
    await ReadOnly()


def as_unsigned(value: int, width: int) -> int:
    return value & ((1 << width) - 1)


def as_signed(value: int, width: int) -> int:
    value &= (1 << width) - 1
    return value - (1 << width) if value & (1 << (width - 1)) else value


async def drive_idle(dut) -> None:
    dut.start.value = 0
    dut.load_a_en.value = 0
    dut.load_a_row.value = 0
    dut.load_a_col.value = 0
    dut.load_a_data.value = 0
    dut.load_b_en.value = 0
    dut.load_b_row.value = 0
    dut.load_b_col.value = 0
    dut.load_b_data.value = 0
    dut.result_row.value = 0
    dut.result_col.value = 0


async def reset(dut) -> None:
    dut.rst.value = 1
    await drive_idle(dut)
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    dut.rst.value = 0


async def load_tile(dut, a: np.ndarray, b: np.ndarray) -> None:
    """Write one N x K and K x N tile through the public load ports."""

    assert a.shape == (N, K)
    assert b.shape == (K, N)
    assert int(dut.busy.value) == 0, "accelerator must be idle before loading"

    for index in range(N * K):
        a_row, a_col = divmod(index, K)
        b_row, b_col = divmod(index, N)

        await FallingEdge(dut.clk)
        dut.load_a_en.value = 1
        dut.load_a_row.value = a_row
        dut.load_a_col.value = a_col
        dut.load_a_data.value = as_unsigned(int(a[a_row, a_col]), DATA_WIDTH)

        dut.load_b_en.value = 1
        dut.load_b_row.value = b_row
        dut.load_b_col.value = b_col
        dut.load_b_data.value = as_unsigned(int(b[b_row, b_col]), DATA_WIDTH)
        await clock_edge(dut)

    await FallingEdge(dut.clk)
    dut.load_a_en.value = 0
    dut.load_b_en.value = 0


async def start_and_wait(dut) -> None:
    await FallingEdge(dut.clk)
    dut.start.value = 1
    await clock_edge(dut)
    assert int(dut.busy.value) == 1, "busy must assert when start is accepted"

    await FallingEdge(dut.clk)
    dut.start.value = 0

    timeout_cycles = K + (4 * N) + 32
    for _ in range(timeout_cycles):
        await clock_edge(dut)
        if int(dut.done.value) == 1:
            await clock_edge(dut)
            assert int(dut.done.value) == 0
            assert int(dut.busy.value) == 0
            return

    raise AssertionError(f"timed out waiting for done after {timeout_cycles} cycles")


async def read_tile(dut) -> np.ndarray:
    result = np.empty((N, N), dtype=np.int32)
    for row in range(N):
        for col in range(N):
            await FallingEdge(dut.clk)
            dut.result_row.value = row
            dut.result_col.value = col
            await Timer(1, units="ns")
            result[row, col] = as_signed(int(dut.result_data.value), ACC_WIDTH)
    return result


@cocotb.test()
async def test_quantized_fc_inference(dut) -> None:
    """Run the quantized layer and compare both int32 and float results."""

    if N < 1 or K != N:
        raise AssertionError("the inference demo requires a square N x N OS tile")

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    vectors = make_demo_vectors(n=N, input_features=2 * N)
    feature_tiles = vectors.input_q.shape[1] // N
    accumulated = np.zeros((N, N), dtype=np.int64)

    for tile_index in range(feature_tiles):
        feature_start = tile_index * N
        feature_stop = feature_start + N
        a_tile = vectors.input_q[:, feature_start:feature_stop]
        b_tile = vectors.weight_q[feature_start:feature_stop, :]

        await load_tile(dut, a_tile, b_tile)
        await start_and_wait(dut)
        accumulated += (await read_tile(dut)).astype(np.int64)

    actual_accumulator = accumulated + vectors.bias_q[np.newaxis, :]
    expected_accumulator = vectors.quantized_accumulator.astype(np.int64)
    np.testing.assert_array_equal(
        actual_accumulator,
        expected_accumulator,
        err_msg="tiled int32 accumulator mismatch",
    )

    actual_float = actual_accumulator.astype(np.float64) * vectors.output_scale
    reference_float = vectors.reference_float
    error = np.abs(actual_float - reference_float)
    bound = vectors.absolute_error_bound

    np.testing.assert_array_less(
        error,
        bound + 1.0e-10,
        err_msg="dequantized inference exceeded the quantization error bound",
    )
    cocotb.log.info(
        "PASS: quantized FC %s x %s, max_abs_error=%.7g, max_bound=%.7g, "
        "input_scale=%.7g, weight_scale=%.7g",
        vectors.input_float.shape,
        vectors.weight_float.shape,
        float(np.max(error)),
        float(np.max(bound)),
        vectors.input_scale,
        vectors.weight_scale,
    )
