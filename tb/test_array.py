"""Cocotb end-to-end checks for the Stage 1 tile-level accelerator."""

from __future__ import annotations

import os

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, ReadOnly, RisingEdge, Timer

from ref_model import int8_matmul


N = int(os.environ.get("N", "4"))
K = int(os.environ.get("K", str(N)))
DATA_WIDTH = 8
ACC_WIDTH = 32


async def clock_edge(dut) -> None:
    """Wait for a rising edge and settle all registered/combinational logic."""

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
    """Write A[N,K] and B[K,N] through the public independent load ports."""

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
            # `busy` stays high through the done notification. Wait until the
            # following idle cycle before beginning the next load transaction.
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


def directed_tile() -> tuple[np.ndarray, np.ndarray]:
    values_a = [0, 1, -1, 127, -128, 64, -64, 13]
    values_b = [0, -1, 1, -128, 127, -64, 64, -7]
    a = np.array(
        [[values_a[(row * K + col) % len(values_a)] for col in range(K)] for row in range(N)],
        dtype=np.int8,
    )
    b = np.array(
        [[values_b[(row * N + col + 3) % len(values_b)] for col in range(N)] for row in range(K)],
        dtype=np.int8,
    )
    return a, b


@cocotb.test()
async def test_os_matmul_against_numpy(dut) -> None:
    """Exercise full public transactions against the independent NumPy model."""

    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset(dut)

    rng = np.random.default_rng(0x51A7)
    zero_a = np.zeros((N, K), dtype=np.int8)
    zero_b = np.zeros((K, N), dtype=np.int8)
    directed_a, directed_b = directed_tile()
    random_a = rng.integers(-128, 128, size=(N, K), dtype=np.int16).astype(np.int8)
    random_b = rng.integers(-128, 128, size=(K, N), dtype=np.int16).astype(np.int8)

    for label, a, b in (
        ("zero", zero_a, zero_b),
        ("signed-extreme", directed_a, directed_b),
        ("random", random_a, random_b),
    ):
        await load_tile(dut, a, b)
        await start_and_wait(dut)
        actual = await read_tile(dut)
        expected = int8_matmul(a, b)
        np.testing.assert_array_equal(actual, expected, err_msg=f"{label} tile mismatch")
