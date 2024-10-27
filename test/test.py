# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

# For reference, the pinout is:
#    .tck(ui_in[0]),
#    .tdi(ui_in[1]),
#    .tms(ui_in[2]),
#    .trst(ui_in[3]),
@cocotb.test()
async def test_tms_five_high_for_reset(dut):
        dut._log.info("Start")
        clock = Clock(dut.clk, 3, units="us")
        cocotb.start_soon(clock.start())
        dut._log.info("Reset the interrupt timer")
        dut.ena.value = 1
        dut.ui_in.value = 0
        dut.uio_in.value = 0
        dut.rst_n.value = 1
        await ClockCycles(dut.clk, 1)
        dut.rst_n.value = 0
        await ClockCycles(dut.clk, 1)
        dut.rst_n.value = 1
        dut.ui_in.value = 0b0000_1000
        await ClockCycles(dut.clk, 1)

        # Drive TRST low and TCK high then low to reset tap controller
        dut._log.info("Reset the jtag tap controller")
        dut.ui_in.value = 0b0000_0001
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0b0000_1000
        await ClockCycles(dut.clk, 1)
        assert dut.uo_out.value == 0x0

        # Drive TCK high/low enough times to see 0xFAF01

        # Drive TMS high then low for five cycles to put us into reset.
        dut._log.info("TMS high for five pulses to reset TAP controller")
        dut.ui_in.value = 0b0000_0111
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0b0000_0110
        await ClockCycles(dut.clk, 1)

        dut.ui_in.value = 0b0000_0111
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0b0000_0110
        await ClockCycles(dut.clk, 1)

        dut.ui_in.value = 0b0000_0111
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0b0000_0110
        await ClockCycles(dut.clk, 1)

        dut.ui_in.value = 0b0000_0111
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0b0000_0110
        await ClockCycles(dut.clk, 1)

        dut.ui_in.value = 0b0000_0111
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0b0000_0110
        # At this point, the design is in reset but
        # the interrupt is also firing on all the other pins.
        assert dut.uo_out.value == 0xFE

        await ClockCycles(dut.clk, 1)
        assert dut.uo_out.value == 0x0

# Ensure that IDCODE is returned when asked for
cocotb.test()
async def test_idcode(dut):
        dut._log.info("Start")
        clock = Clock(dut.clk, 3, units="us")
        cocotb.start_soon(clock.start())
        dut._log.info("Reset the interrupt timer")
        dut.ena.value = 1
        dut.ui_in.value = 0
        dut.uio_in.value = 0
        dut.rst_n.value = 1
        await ClockCycles(dut.clk, 1)
        dut.rst_n.value = 0
        await ClockCycles(dut.clk, 1)
        dut.rst_n.value = 1
        await ClockCycles(dut.clk, 1)

        # Drive TRST and TCK high then low to reset tap controller
        dut._log.info("Reset the jtag tap controller")
        dut.ui_in.value = 0b0000_1001
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0b0000_0000
        await ClockCycles(dut.clk, 1)
        assert dut.uo_out.value == 0x0

        # Drive TCK and TMS into ShiftDr state
        # TMS: 0 1 0 0 to get into ShiftDr

        # Drive TCK high/low enough times to see 0xFAF01
        for i in range(32):
        # Code to execute in each iteration
                print(i) 
