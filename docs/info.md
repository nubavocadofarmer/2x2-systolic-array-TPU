## How it works

This project is a tiny matrix engine: a 2×2 output-stationary systolic array that computes
C = A × W for a 2-row A and a 2-column W, with any inner dimension K, in a 2×2-tile slot.

- **Two modes.** int8 × int8 (4 multiplies per array step), and W4A8: int8 activations
  times two packed signed 4-bit weights (8 multiplies per step).
- **Four INT24 accumulators**, one per processing element (PE). PE(m, j) owns C[m][j].
  Activations move right and weights move down. The chip adds the systolic skew itself,
  so the host sends aligned values.
- **Overflow flag.** Every add checks for signed overflow. OVF (`uio[6]`) goes high and
  stays high until the next CLEAR. Overflow-free lengths: 511 steps in int8, 4,095 steps
  (8,190 inputs) in W4A8.
- **No on-chip memory** beyond the four sums and a few bytes of staging. The host streams
  every operand in through DATA, one byte per command, one command per clock. Bias,
  activation functions, softmax and requantization run on the host.

### Pins

| Pin | Dir | Signal |
| --- | --- | --- |
| `ui[7:0]` | in | DATA: operand, config or pointer byte |
| `uo[7:0]` | out | RESULT: the byte at the read pointer |
| `uio[2:0]` | in | CMD |
| `uio[3]` | in | VALID: 1 = CMD and DATA on this edge are a command |
| `uio[6]` | out | OVF, sticky until CLEAR |
| `uio[5:4]`, `uio[7]` | in | unused |

`rst_n` is a synchronous active-low reset that clears everything.

### Commands

DATA, CMD and VALID are registered on every rising edge, and a command captured with
VALID = 1 executes on the next clock.

| CMD | Name | DATA | Action |
| --- | --- | --- | --- |
| 0 | NOP | | nothing |
| 1 | PUSH | operand | store the byte in staging; when 4 (int8) or 6 (W4A8) bytes are in, the array steps once |
| 2 | CLEAR | | zero the accumulators, the array's operand registers and OVF; apply the mode from SET_CFG |
| 3 | DRAIN | | 2 array steps with zero inputs to finish the skewed tail; a partial step is thrown away |
| 4 | SET_CFG | bit 0: 0 = int8, 1 = W4A8 | takes effect at the next CLEAR; also throws away a partial step |
| 5 | RD_PTR | bits 3:0: byte address | set the read pointer |
| 6 | RD_NEXT | | read pointer + 1 (wraps 15 → 0) |
| 7 | reserved | | acts as NOP |

RESULT shows the new byte 2 rising edges after RD_PTR or RD_NEXT is presented. After a
DRAIN, hold VALID low for 2 clocks.

### PUSH order for one step

| Byte | int8 step k | W4A8 step k |
| --- | --- | --- |
| 0 | A[0][k] | A[0][2k] |
| 1 | A[1][k] | A[0][2k+1] |
| 2 | W[k][0] | A[1][2k] |
| 3 | W[k][1] | A[1][2k+1] |
| 4 | | column 0: high nibble W[2k+1][0], low nibble W[2k][0] |
| 5 | | column 1: high nibble W[2k+1][1], low nibble W[2k][1] |

In W4A8 an odd K is padded with a zero activation and a zero weight.

### Results

Accumulator i = 2m + j holds C[m][j] at read addresses 3i to 3i + 2, little-endian two's
complement. Addresses 12–15 read 0.

## How to test

The demo board's RP2040 drives the clock and every pin, so you can single-step the chip
from MicroPython for bring-up.

1. Hold `rst_n` low for a few clocks, then release it.
2. SET_CFG 0 (int8), then CLEAR.
3. PUSH 1, 3, 5, 6, then PUSH 2, 4, 7, 8. That is A = [[1, 2], [3, 4]] and
   W = [[5, 6], [7, 8]], one step per 4 bytes.
4. DRAIN, then 2 clocks with VALID low.
5. RD_PTR 0, then read RESULT and send RD_NEXT, 12 bytes in total, sampling RESULT
   2 clocks after each pointer command.
6. Expect `13 00 00 16 00 00 2B 00 00 32 00 00`, which is C = [[19, 22], [43, 50]],
   and OVF = 0.

More checks:

- **W4A8:** SET_CFG 1, CLEAR, then 6 PUSHes per step in the order above. Identity
  weights [[1, 0], [0, 1]] give C = A.
- **Overflow:** 511 steps of (−128) × (−128) leave OVF at 0; 512 set it. CLEAR resets it.
- **Bursts:** skipping CLEAR keeps accumulating, so long sums can be streamed in pieces.
  For sums past the overflow-free limits, run CLEAR-separated chunks and add the results
  on the host.
- **Full speed:** once single-stepping works, drive the same commands from an RP2040 PIO
  program at one command per clock, up to 50 MHz.

The project's golden model, `test/tpu_model.py`, gives the expected bytes for any
product: `pack_step()` for the PUSH bytes and `result_bytes(run_array(...)[0])` for the
16 bytes to read back.

## External hardware

None beyond the Tiny Tapeout demo board. Its RP2040 drives the clock, `rst_n` and every
input pin, and reads RESULT and OVF.
