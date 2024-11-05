# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_minipit_fires_every_ten_cycles(dut):
        dut._log.info("Start")
        clock = Clock(dut.clk, 3, units="us")
        cocotb.start_soon(clock.start())
        dut._log.info("Reset the interrupt timer")
        dut.ena.value = 1
        dut.ui_in.value = 0
        dut.uio_in.value = 0
        dut.rst_n.value = 1
        # We start with TRST being high per the spec.
        dut.ui_in.value = 0b0000_1000

        await ClockCycles(dut.clk, 1)
        dut.rst_n.value = 0
        # Pulling TRST low
        dut.ui_in.value = 0b0000_0000

        await ClockCycles(dut.clk, 1)
        dut.rst_n.value = 1
        # Pulling TRST high again
        dut.ui_in.value = 0b0000_1000

        # We need one cycle for interrupt setup
        await ClockCycles(dut.clk, 1)
        # TODO: fix uo_out[7] being X
        #assert dut.uo_out.value == 0x0
        assert dut.uo_out.value[0] == 0x0
        # After 10 clock cycles, minipit fires
        for i in range(5):
                # GATES=yes needs 11 due to what looks like latching in comparison
                # GATES=no needs 10
                await ClockCycles(dut.clk, 10)
                assert dut.uo_out.value[0] == 0x1


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

        # Drive TRST low and TCK high then low to reset tap controller
        dut._log.info("Reset the jtag tap controller")
        dut.ui_in.value = 0b0000_0001
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0b0000_1000
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0b0000_1001
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0b0000_1000
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0b0000_1001
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0b0000_1000
        await ClockCycles(dut.clk, 1)

        assert dut.uo_out.value == 0x0

        # Drive TMS high then low for five cycles to put us into reset.
        dut._log.info("TMS high for five pulses to reset TAP controller")
        dut.ui_in.value = 0b0000_1111
        await ClockCycles(dut.clk, 1)

        dut.ui_in.value = 0b0000_1110
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0b0000_1111
        await ClockCycles(dut.clk, 1)

        dut.ui_in.value = 0b0000_1110
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0b0000_1111
        await ClockCycles(dut.clk, 1)

        # At this point, the design is in reset but
        # the interrupt is also firing on all the other pins.
        assert dut.uo_out.value == 0xFE

        await ClockCycles(dut.clk, 1)
        assert dut.uo_out.value == 0x0

# Ensure that IDCODE is returned when asked for
@cocotb.test()
async def test_idcode(dut):
        dut._log.info("Start")
        clock = Clock(dut.clk, 1, units="us")
        cocotb.start_soon(clock.start())
        dut._log.info("Reset the part")
        dut.ena.value = 1
        dut.ui_in.value = 0
        dut.uio_in.value = 0
        dut.rst_n.value = 1
        await ClockCycles(dut.clk, 1)
        dut.rst_n.value = 0

        # Drive TRST and TCK high then low to reset tap controller
        dut._log.info("Reset the jtag tap controller")
        dut.ui_in.value = 0b0000_0001
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0b0000_0000
        await ClockCycles(dut.clk, 1)
        dut.rst_n.value = 1
 
        dut.ui_in.value = 0b0000_1001
        await ClockCycles(dut.clk, 1)
        dut.ui_in.value = 0b0000_1000
        await ClockCycles(dut.clk, 1)

        # Should be nothing on the output lines as there hasn't been enough
        # for an interrupt and we haven't changed out of the initial JTAG state.
        assert dut.uo_out.value == 0x0

        #    .tck(ui_in[0]),
        #    .tdi(ui_in[1]),
        #    .tms(ui_in[2]),
        #    .trst(ui_in[3]),
        #
        # Drive TCK and TMS into ShiftDr state
        # TMS: 0 1 0 0 to get into ShiftDr
        STATES = [0b0000_1001, 0b0000_1101, 0b0000_1001, 0b0000_1001]
        for state in STATES:
                dut.ui_in.value = state
                await ClockCycles(dut.clk, 1)
                dut.ui_in.value = 0b0000_1000
                await ClockCycles(dut.clk, 1)
                #assert dut.uo_out.value == 0x0

        expected_idcode = 0xFAF01
        given_idcode = 0
        # Drive TCK high/low enough times to see 0xFAF01, our IDCODE
        for i in range(31):
                dut.ui_in.value = 0b0000_1001
                await ClockCycles(dut.clk, 1)
                dut.ui_in.value = 0b0000_1000
                await ClockCycles(dut.clk, 1)
                tdo = dut.uo_out.value[7]
                print(dut.uo_out.value)
                given_idcode = (given_idcode << 1) + int(tdo)

        assert given_idcode == expected_idcode
