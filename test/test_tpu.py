import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, ClockCycles, Timer

import tpu_model as mm

NOP, PUSH, CLEAR, DRAIN, SET_CFG, RD_PTR, RD_NEXT, RSVD = 0, 1, 2, 3, 4, 5, 6, 7

STYLES = ["free", "single"]
gap_chance = 0.0

GATE_LEVEL = os.environ.get("GATES") == "yes"


async def idle(dut, n=1):
    for i in range(n):
        await FallingEdge(dut.clk)
        dut.ui_in.value = random.randint(0, 255)
        dut.uio_in.value = random.randint(0, 255) & 0b11110111
        dut.ena.value = random.randint(0, 1)


async def send(dut, cmd, data=0):
    if gap_chance > 0 and random.random() < gap_chance:
        await idle(dut, random.randint(1, 3))
    await FallingEdge(dut.clk)
    dut.ui_in.value = data & 0xFF
    junk = random.randint(0, 15) << 4
    dut.uio_in.value = junk | 0b1000 | cmd
    dut.ena.value = random.randint(0, 1)


def ovf_pin(dut):
    return (int(dut.uio_out.value) >> 6) & 1


async def read_byte(dut, addr):
    await send(dut, RD_PTR, addr)
    await idle(dut, 2)
    return int(dut.uo_out.value)


async def read_results(dut):
    stuff = []
    for addr in range(16):
        stuff.append(await read_byte(dut, addr))
    return stuff


async def stream(dut, a, w, mode):
    steps = len(w)
    if mode == 1:
        steps = (len(w) + 1) // 2
    for k in range(steps):
        for b in mm.pack_step(a, w, k, mode):
            await send(dut, PUSH, b)


async def drain(dut):
    await send(dut, DRAIN)
    await idle(dut, 2)


async def do_product(dut, a, w, mode):
    await send(dut, SET_CFG, mode)
    await send(dut, CLEAR)
    await stream(dut, a, w, mode)
    await drain(dut)


async def check(dut, sums, ovf, what):
    got = await read_results(dut)
    want = mm.result_bytes(sums)
    assert got == want, f"{what}: got {got}, want {want}"
    assert ovf_pin(dut) == int(ovf), f"{what}: OVF pin {ovf_pin(dut)}, want {int(ovf)}"


def rand_matrices(K, mode, extremes=False):
    lo, hi = (-128, 127) if mode == 0 else (-8, 7)
    if extremes:
        a = [[random.choice([-128, 127, -128, random.randint(-128, 127)]) for k in range(K)]
             for row in range(2)]
        w = [[random.choice([lo, hi, lo, random.randint(lo, hi)]) for col in range(2)]
             for k in range(K)]
        return a, w
    a = [[random.randint(-128, 127) for k in range(K)] for row in range(2)]
    w = [[random.randint(lo, hi) for col in range(2)] for k in range(K)]
    return a, w


def pad_even(a, w):
    if len(w) % 2 == 1:
        a = [a[0] + [0], a[1] + [0]]
        w = w + [[0, 0]]
    return a, w


def join(a1, w1, a2, w2):
    return [a1[0] + a2[0], a1[1] + a2[1]], w1 + w2


def bytes_to_sums(b):
    nums = []
    for i in range(4):
        v = b[3*i] | (b[3*i+1] << 8) | (b[3*i+2] << 16)
        if v >= 8388608:
            v -= 16777216
        nums.append(v)
    return [[nums[0], nums[1]], [nums[2], nums[3]]]


async def single_step_clock(dut):
    while True:
        dut.clk.value = 0
        await Timer(random.randint(10, 100), unit="ns")
        dut.clk.value = 1
        await Timer(random.randint(10, 100), unit="ns")


async def setup(dut, style):
    global gap_chance
    if style == "free":
        cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
        gap_chance = 0.0
    else:
        cocotb.start_soon(single_step_clock(dut))
        gap_chance = 0.3

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1


@cocotb.test()
@cocotb.parametrize(style=STYLES)
async def known_products(dut, style):
    await setup(dut, style)

    a = [[1, 2], [3, 4]]
    w = [[5, 6], [7, 8]]
    await do_product(dut, a, w, 0)
    await check(dut, [[19, 22], [43, 50]], False, "int8 known")

    eye = [[1, 0], [0, 1]]
    a = [[-128, 127], [55, -3]]
    for mode in (0, 1):
        await do_product(dut, a, eye, mode)
        await check(dut, [[-128, 127], [55, -3]], False, f"identity mode={mode}")

    await do_product(dut, [[-128], [127]], [[-8, 7]], 1)
    await check(dut, [[1024, -896], [-1016, 889]], False, "W4A8 K=1")


@cocotb.test()
@cocotb.parametrize(style=STYLES)
async def random_products(dut, style):
    await setup(dut, style)
    for mode in (0, 1):
        for trial in range(20):
            K = random.randint(1, 64)
            a, w = rand_matrices(K, mode, extremes=(trial % 4 == 0))
            await do_product(dut, a, w, mode)
            sums, ovf = mm.run_array(a, w, mode)
            await check(dut, sums, ovf, f"random mode={mode} K={K}")
        dut._log.info(f"mode {mode}: 20 random products matched the golden model")


@cocotb.test()
@cocotb.parametrize(style=STYLES)
async def overflow_edges(dut, style):
    await setup(dut, style)

    for K, want_ovf in [(511, False), (512, True)]:
        a = [[-128] * K, [-128] * K]
        w = [[-128, -128] for k in range(K)]
        await do_product(dut, a, w, 0)
        sums, ovf = mm.run_array(a, w, 0)
        assert ovf == want_ovf
        await check(dut, sums, ovf, f"int8 overflow K={K}")

    await idle(dut, 5)
    assert ovf_pin(dut) == 1, "OVF dropped without CLEAR"

    a2 = [[random.randint(1, 127) for k in range(10)] for row in range(2)]
    w2 = [[random.randint(1, 127) for col in range(2)] for k in range(10)]
    await stream(dut, a2, w2, 0)
    await drain(dut)
    big_a, big_w = join(a, w, a2, w2)
    sums, ovf = mm.run_array(big_a, big_w, 0)
    assert ovf
    await check(dut, sums, ovf, "OVF still set after more steps")

    await send(dut, CLEAR)
    await idle(dut, 2)
    assert ovf_pin(dut) == 0, "CLEAR did not reset OVF"

    if GATE_LEVEL:
        dut._log.info("gate-level run: skipping the W4A8 4,095/4,096 overflow case")
        return
    for K, want_ovf in [(8190, False), (8192, True)]:
        a = [[-128] * K, [-128] * K]
        w = [[-8, -8] for k in range(K)]
        await do_product(dut, a, w, 1)
        sums, ovf = mm.run_array(a, w, 1)
        assert ovf == want_ovf
        await check(dut, sums, ovf, f"W4A8 overflow K={K}")


@cocotb.test()
@cocotb.parametrize(style=STYLES)
async def bursts_without_clear(dut, style):
    await setup(dut, style)
    for mode in (0, 1):
        for trial in range(5):
            await send(dut, SET_CFG, mode)
            await send(dut, CLEAR)
            all_a, all_w = [[], []], []
            for burst in range(3):
                a, w = rand_matrices(random.randint(1, 20), mode)
                if mode == 1:
                    a, w = pad_even(a, w)
                await stream(dut, a, w, mode)
                await drain(dut)
                all_a, all_w = join(all_a, all_w, a, w)
                sums, ovf = mm.run_array(all_a, all_w, mode)
                await check(dut, sums, ovf, f"burst {burst} mode={mode}")


@cocotb.test()
@cocotb.parametrize(style=STYLES)
async def chunked_2000(dut, style):
    await setup(dut, style)
    K = 2000
    a, w = rand_matrices(K, 0, extremes=True)
    total = [[0, 0], [0, 0]]
    await send(dut, SET_CFG, 0)
    for start in range(0, K, 511):
        small_a = [a[0][start:start+511], a[1][start:start+511]]
        small_w = w[start:start+511]
        await send(dut, CLEAR)
        await stream(dut, small_a, small_w, 0)
        await drain(dut)
        got = await read_results(dut)
        assert ovf_pin(dut) == 0, f"chunk at {start} overflowed"
        part = bytes_to_sums(got)
        for r in range(2):
            for c in range(2):
                total[r][c] += part[r][c]
    assert total == mm.chunked(a, w, 0), "chunked total differs from the model"
    assert total == mm.matmul(a, w, 0), "chunked total differs from the exact product"


@cocotb.test()
@cocotb.parametrize(style=STYLES)
async def mode_switches(dut, style):
    await setup(dut, style)

    a, w = rand_matrices(6, 0)
    await send(dut, SET_CFG, 0)
    await send(dut, CLEAR)
    for k in range(6):
        for b in mm.pack_step(a, w, k, 0):
            await send(dut, PUSH, b)
        if k == 2:
            await send(dut, SET_CFG, 1)
    await drain(dut)
    sums, ovf = mm.run_array(a, w, 0)
    await check(dut, sums, ovf, "int8 with pending W4A8 config")

    a, w = rand_matrices(7, 1)
    await send(dut, CLEAR)
    await stream(dut, a, w, 1)
    await drain(dut)
    sums, ovf = mm.run_array(a, w, 1)
    await check(dut, sums, ovf, "W4A8 after CLEAR")

    a, w = rand_matrices(5, 0)
    await do_product(dut, a, w, 0)
    sums, ovf = mm.run_array(a, w, 0)
    await check(dut, sums, ovf, "back to int8")


@cocotb.test()
@cocotb.parametrize(style=STYLES)
async def partial_steps_and_nops(dut, style):
    await setup(dut, style)
    for mode in (0, 1):
        full = 4 if mode == 0 else 6
        for partial in range(1, full):
            a, w = rand_matrices(random.randint(1, 9), mode)

            await send(dut, SET_CFG, mode)
            await send(dut, CLEAR)
            for i in range(partial):
                await send(dut, PUSH, random.randint(0, 255))
            await drain(dut)
            await stream(dut, a, w, mode)
            await drain(dut)
            sums, ovf = mm.run_array(a, w, mode)
            await check(dut, sums, ovf, f"partial DRAIN mode={mode} n={partial}")

            await send(dut, CLEAR)
            for i in range(partial):
                await send(dut, PUSH, random.randint(0, 255))
            await send(dut, SET_CFG, mode)
            await stream(dut, a, w, mode)
            await drain(dut)
            await check(dut, sums, ovf, f"partial SET_CFG mode={mode} n={partial}")

    for i in range(10):
        await send(dut, random.choice([NOP, RSVD]), random.randint(0, 255))
    await check(dut, sums, ovf, "after NOP/reserved")


@cocotb.test()
@cocotb.parametrize(style=STYLES)
async def fast_readout_and_wrap(dut, style):
    await setup(dut, style)
    a, w = rand_matrices(9, 0, extremes=True)
    await do_product(dut, a, w, 0)
    sums, ovf = mm.run_array(a, w, 0)
    want = mm.result_bytes(sums)

    await FallingEdge(dut.clk)
    dut.uio_in.value = 0b1000 | RD_PTR
    dut.ui_in.value = 0
    await FallingEdge(dut.clk)
    dut.uio_in.value = 0b1000 | RD_NEXT
    got = []
    for i in range(17):
        await FallingEdge(dut.clk)
        got.append(int(dut.uo_out.value))
        dut.uio_in.value = 0b1000 | RD_NEXT
    await idle(dut, 2)
    assert got == want + [want[0]], f"fast readout: got {got}, want {want + [want[0]]}"

    for addr in range(16):
        b = await read_byte(dut, (random.randint(0, 15) << 4) | addr)
        assert b == want[addr], f"RD_PTR {addr} with junk high bits"


@cocotb.test()
@cocotb.parametrize(style=STYLES)
async def reset_mid_work(dut, style):
    await setup(dut, style)

    for case in ("int8 OVF set, W4A8 config pending", "W4A8 active, work in flight"):
        if case.startswith("int8"):
            a = [[-128] * 512, [-128] * 512]
            w = [[-128, -128] for k in range(512)]
            await do_product(dut, a, w, 0)
            assert ovf_pin(dut) == 1
            await send(dut, SET_CFG, 1)
        else:
            await send(dut, SET_CFG, 1)
            await send(dut, CLEAR)
            a, w = rand_matrices(5, 1)
            await stream(dut, a, w, 1)
        await send(dut, PUSH, 99)
        await send(dut, RD_PTR, 7)

        await FallingEdge(dut.clk)
        dut.rst_n.value = 0
        await ClockCycles(dut.clk, 2)
        await FallingEdge(dut.clk)
        dut.rst_n.value = 1

        assert ovf_pin(dut) == 0, f"{case}: rst_n did not clear OVF"
        assert int(dut.uo_out.value) == 0, f"{case}: read pointer or acc not reset"
        await check(dut, [[0, 0], [0, 0]], False, f"{case}: right after reset")

        a, w = rand_matrices(6, 0)
        await send(dut, CLEAR)
        await stream(dut, a, w, 0)
        await drain(dut)
        sums, ovf = mm.run_array(a, w, 0)
        await check(dut, sums, ovf, f"{case}: int8 after reset")
