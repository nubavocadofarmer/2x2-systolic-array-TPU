# 2x2 Systolic TPU

A 2×2 output-stationary systolic matrix engine for [Tiny Tapeout](https://tinytapeout.com)
on SkyWater 130 nm (sky130), in a 2×2-tile slot at 50 MHz.

- **int8 and W4A8.** int8 × int8 (4 multiplies per array step), or int8 activations ×
  two packed signed 4-bit weights (8 multiplies per step).
- **Four INT24 accumulators**, one per processing element, with a sticky overflow flag.
- **Streamed operands.** The host (the demo board's RP2040) sends every byte through the
  pins, one command per clock, and reads the results back. Bias, activation functions,
  softmax and requantization run on the host.

The datasheet, with the pinout, command set, PUSH byte order, result layout and a worked
example, is in [docs/info.md](docs/info.md).

## Layout

| Path | Contents |
| --- | --- |
| `src/` | RTL: `tpu_pkg.sv`, `os_pe.sv` (one PE), `os_array.sv` (2×2 grid and readout), `host_if.sv` (command decoder, staging, skew), `tt_um_nubavocadofarmer_systolic_tpu.sv` (top), plus the hardening `config.json` |
| `test/` | `tpu_model.py` golden model and `check_tpu_model.py` self-check; `test_tpu.py` cocotb suite through the pins (`tb.v` wrapper); SystemVerilog unit testbenches `tb_os_pe.sv`, `tb_os_array.sv`, `tb_host_if.sv`, `tb_tpu.sv` |
| `formal/` | SymbiYosys checks: `tpu.sby` and the `fv_*.sv` harnesses |
| `reports/` | Yosys area report and the script that makes it |
| `docs/info.md` | Tiny Tapeout datasheet |

## Verification

- **Golden model.** `test/tpu_model.py` defines correct behavior; the cocotb suite checks
  every result byte and the overflow pin against it.
- **cocotb suite** (`test/test_tpu.py`): 9 tests, each run with a free-running 50 MHz clock
  and with a randomly single-stepped clock plus random idle gaps. Known and random products
  (K = 1–64, both modes), the 511/512 and 4,095/4,096-step overflow edges and stickiness,
  bursts without CLEAR, a 2,000-input chunked reduction, mode switches, partial steps,
  back-to-back readout and pointer wrap, and reset mid-work. Every RTL line is covered.
- **Unit testbenches**: all 16.8 M multiplier input combinations in `tb_os_pe.sv`, plus
  array, host interface and pin-level checks.
- **Formal** (`formal/tpu.sby`): proofs that OVF stays set until CLEAR, CLEAR zeroes the
  accumulators and operand registers, and the mode changes only at CLEAR; a 40-cycle
  bounded check that the array never steps on a partial fill.
- **Lint**: Verilator `-Wall` clean.

## Running the checks

Needs Icarus Verilog, Python 3 with `pip install -r test/requirements.txt`, and for the
extras Verilator, Yosys and SymbiYosys.

```sh
cd test && make
```

```sh
python3 test/check_tpu_model.py
```

```sh
cd test && make SIM=verilator
```

```sh
cd formal && sby -f tpu.sby
```

```sh
bash reports/run_area.sh
```

`make SIM=verilator` also writes line and toggle coverage to `test/coverage.dat`.
`bash reports/run_area.sh` needs `sky130_fd_sc_hd__tt_025C_1v80.lib` in `~/pdk`.

## Hardening

The `gds` GitHub Action builds the layout with LibreLane. At 2×2 tiles the design places
at about 57% utilization and passes Tiny Tapeout's precheck and the gate-level test. It
does not fit 1×2: the flow synthesizes about 35,000 µm² of cells, more than a 1×2 core.

## License

Apache 2.0, see [LICENSE](LICENSE).
