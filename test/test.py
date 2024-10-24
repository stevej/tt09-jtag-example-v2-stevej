# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

#    .tck(ui_in[0]),
#    .tdi(ui_in[1]),
#    .tms(ui_in[2]),
#    .trst(ui_in[3]),
@cocotb.test()
async def test_rms_five_high_for_reset(dut):
        dut._log.info("Start")
        clock = Clock(dut.clk, 3, units="us")
        cocotb.start_soon(clock.start())
        dut._log.info("Reset")
        dut.ena.value = 1
        dut.ui_in.value = 0
        dut.uio_in.value = 0
        dut.rst_n.value = 0
        await ClockCycles(dut.clk, 1)
        dut.rst_n.value = 1
        await ClockCycles(dut.clk, 1)

        # Drive TRST and TCK high then low to reset the design.
        dut.ui_in.value = 0b0000_1001
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0b0000_0000
        await ClockCycles(dut.clk, 1)
        assert dut.uo_out.value == 0x0

        # Drive TMS high then low for five cycles to put us into reset.
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

