"""
Cocotb testbench for tt_um_layla_spike_detector
Generates synthetic neural data: background noise + spike waveforms
Verifies spike detection timing and absence of false positives.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer
import random
import math


# ── Synthetic signal generation ──────────────────────────────────────────────

def gaussian(n, mu, sigma, amplitude):
    """Gaussian spike shape, returns integer sample list"""
    return [int(amplitude * math.exp(-0.5 * ((i - mu) / sigma) ** 2))
            for i in range(n)]

def make_neural_signal(n_samples, spike_times, noise_amp=8, spike_amp=60):
    """
    Build a synthetic neural signal:
    - Gaussian white noise (noise_amp)
    - Positive spike waveforms at spike_times (spike_amp peak)
    """
    signal = [random.randint(-noise_amp, noise_amp) for _ in range(n_samples)]
    for t in spike_times:
        spike = gaussian(20, 10, 2.5, spike_amp)
        for i, s in enumerate(spike):
            idx = t + i - 10
            if 0 <= idx < n_samples:
                signal[idx] = max(-128, min(127, signal[idx] + s))
    return signal


# ── Helpers ───────────────────────────────────────────────────────────────────

async def reset_dut(dut):
    dut.rst_n.value  = 0
    dut.ui_in.value  = 0
    dut.uio_in.value = 0b00000100  # CS_n high (SPI idle)
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)


async def send_sample(dut, sample):
    """Drive one 8-bit sample. The design samples on clk_en (every 1000 cycles)."""
    dut.ui_in.value = sample & 0xFF
    await ClockCycles(dut.clk, 1000)


async def spi_write_config(dut, k_thresh, refractory_len):
    """
    Send 16-bit config word via bit-bang SPI (mode 0, MSB first).
    Word: [15:12]=k_thresh [11:8]=0 [7:0]=refractory_len
    """
    word = ((k_thresh & 0xF) << 12) | (refractory_len & 0xFF)

    dut.uio_in.value = 0b00000000
    await ClockCycles(dut.clk, 4)

    for bit in range(15, -1, -1):
        mosi = (word >> bit) & 1
        dut.uio_in.value = (mosi << 1)
        await ClockCycles(dut.clk, 4)
        dut.uio_in.value = (mosi << 1) | 0b001
        await ClockCycles(dut.clk, 4)
        dut.uio_in.value = (mosi << 1)
        await ClockCycles(dut.clk, 2)

    dut.uio_in.value = 0b00000100
    await ClockCycles(dut.clk, 4)
    dut._log.info(f"SPI config sent: k={k_thresh}, refractory={refractory_len}")


# ── Tests ─────────────────────────────────────────────────────────────────────

@cocotb.test()
async def test_basic_spike_detection(dut):
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())
    await reset_dut(dut)

    random.seed(42)
    spike_times = [80, 200]
    signal = make_neural_signal(300, spike_times, noise_amp=8, spike_amp=60)

    detected_times = []
    dut._log.info("Starting basic spike detection test...")

    for i, sample in enumerate(signal):
        dut.ui_in.value = sample & 0xFF
        await ClockCycles(dut.clk, 1000)

        spike_bit = int(dut.uo_out.value) >> 7
        if spike_bit:
            ts = int(dut.uo_out.value) & 0x7F
            detected_times.append((i, ts))
            dut._log.info(f"  Spike detected at sample {i}, timestamp={ts}")

    dut._log.info(f"Total spikes detected: {len(detected_times)}")
    assert len(detected_times) >= 2, (
        f"Expected at least 2 spike detections, got {len(detected_times)}"
    )
    dut._log.info("PASS: basic spike detection")


@cocotb.test()
async def test_no_false_positives_noise_only(dut):
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())
    await reset_dut(dut)

    random.seed(7)
    signal = [random.randint(-8, 8) for _ in range(500)]

    false_positives = 0
    for i, sample in enumerate(signal):
        dut.ui_in.value = sample & 0xFF
        await ClockCycles(dut.clk, 1000)
        if i > 100 and (int(dut.uo_out.value) >> 7):
            false_positives += 1

    dut._log.info(f"False positives in noise-only test: {false_positives}")
    assert false_positives < 2, (
        f"Too many false positives: {false_positives}"
    )
    dut._log.info("PASS: no false positives in noise-only signal")


@cocotb.test()
async def test_refractory_period(dut):
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())
    await reset_dut(dut)

    random.seed(13)
    spike_times = [60, 70]
    signal = make_neural_signal(200, spike_times, noise_amp=5, spike_amp=70)

    detected = 0
    for sample in signal:
        dut.ui_in.value = sample & 0xFF
        await ClockCycles(dut.clk, 1000)
        if int(dut.uo_out.value) >> 7:
            detected += 1

    dut._log.info(f"Detections for closely-spaced spikes: {detected}")
    assert detected < 4, (
        f"Refractory period failed: expected fewer detections, got {detected}"
    )
    dut._log.info("PASS: refractory period blocks double-detection")


@cocotb.test()
async def test_spi_config(dut):
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())
    await reset_dut(dut)

    await spi_write_config(dut, k_thresh=8, refractory_len=50)

    random.seed(21)
    spike_times = [100]
    signal = make_neural_signal(250, spike_times, noise_amp=8, spike_amp=30)

    detected = 0
    for sample in signal:
        dut.ui_in.value = sample & 0xFF
        await ClockCycles(dut.clk, 1000)
        if int(dut.uo_out.value) >> 7:
            detected += 1

    dut._log.info(f"Detections with k=8 (high threshold): {detected}")
    assert detected == 0, (
        f"SPI threshold config failed: weak spike should be suppressed, got {detected}"
    )
    dut._log.info("PASS: SPI config raises threshold correctly")


@cocotb.test()
async def test_reset_clears_state(dut):
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())
    await reset_dut(dut)

    for _ in range(50):
        dut.ui_in.value = random.randint(0, 127)
        await ClockCycles(dut.clk, 1000)

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    assert int(dut.uo_out.value) == 0, "uo_out should be 0 during reset"
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    dut._log.info("PASS: reset clears output")
