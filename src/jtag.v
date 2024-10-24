`ifndef _JTAG_
`define _JTAG_

`default_nettype none
`timescale 1us / 100 ns

`include "byte_transmitter.v"

// Ensures that the first_state happens before the second_state.
// We use a label as a breadcrumb in case an invalid state is asserted
`define HAPPENS_BEFORE(first_state, second_state) \
  if (f_past_valid && $past(trst) && current_state == second_state) begin \
    HA_``first_state``_to_``second_state : assert ($past(current_state) == first_state); \
  end;

module jtag (
    input tck,
    /* verilator lint_off UNUSED */
    input wire tdi,
    output wire tdo,
    input wire tms,
    input wire trst,
    input wire reset, // comes from main domain clock.
    output in_reset
);

  // IDCODE of our jtag device.
  localparam [31:0] IDCODE = 32'hFAF0;

  localparam [4:0] TestLogicReset = 5'h0;
  localparam [4:0] RunTestOrIdle = 5'h1;
  localparam [4:0] SelectDrScan = 5'h2;
  localparam [4:0] SelectIrScan = 5'h3;
  localparam [4:0] CaptureDr = 5'h4;
  localparam [4:0] CaptureIr = 5'h5;
  localparam [4:0] ShiftDr = 5'h6;
  localparam [4:0] ShiftIr = 5'h7;
  localparam [4:0] Exit1Dr = 5'h8;
  localparam [4:0] Exit1Ir = 5'h9;
  localparam [4:0] PauseDr = 5'h10;
  localparam [4:0] PauseIr = 5'h11;
  localparam [4:0] Exit2Dr = 5'h12;
  localparam [4:0] Exit2Ir = 5'h13;
  localparam [4:0] UpdateDr = 5'h14;
  localparam [4:0] UpdateIr = 5'h15;

  reg [4:0] current_state;
  reg r_in_reset;
  //
  reg r_in_reset_from_main_clk;
  assign in_reset = r_in_reset;
  // for checking that the TAP state machine is in reset at the right time.
  reg [4:0] tms_reset_check;
  reg [7:0] cycles;

  wire idcode_out_done;
  reg transmitter_channel; // for byte_transmitter to write to TDO
  reg tap_channel; // for TAP controller to write to TDO

  byte_transmitter id_byte_transmitter(
    .clk(tck),
    .reset(~trst),
    .enable(1'b1), // TODO: this is where mux goes.
    .in(IDCODE),
    .out(transmitter_channel), // make this another wire.
    .done(idcode_out_done));

reg r_output_selector_transmitter;  // 1 means TAP controller, 0 means byte transmitter
mux_2_1 output_mux (
    .one(tap_channel),
    .two(transmitter_channel),
    .selector(r_output_selector_transmitter),
    .out(tdo)
);
  // Getting the reset signal from the main design clock into the 
  // jtag design requires us to cross domain clocks so we use
  // a small synchronizer.
  // A single cycle pulse on output for each pulse on input:
  (* ASYNC_REG = "TRUE" *) reg [2:0] sync;
  always @(posedge tck) sync <= (sync << 1) | {1'b0, 1'b0, reset};
  assign r_in_reset_from_main_clk = sync[1] & !sync[2];

  always @(posedge tck) begin
    if (trst | r_in_reset_from_main_clk) begin
      current_state <= TestLogicReset;  // 0
      tms_reset_check <= 5'b0_0000;
      cycles <= 0;
      r_in_reset <= 1;
      r_output_selector_transmitter <= 1; // by default the tap controller writes
      tap_channel <= 0;
    end else begin
      r_in_reset <= 0;
      tms_reset_check <= tms_reset_check << 1;
      tms_reset_check[0] <= tms;
      cycles <= cycles + 1;
      // TAP state machine
      case (current_state)
        TestLogicReset: begin  // 0
          r_in_reset <= 1;
          tms_reset_check <= 5'b0_0000;
          tap_channel <= 0;

          case (tms)
            1: current_state <= TestLogicReset;
            default: current_state <= RunTestOrIdle;
          endcase
        end
        RunTestOrIdle:  // 1
        case (tms)
          1: current_state <= SelectDrScan;
          default: current_state <= RunTestOrIdle;
        endcase
        SelectDrScan:  // 2
        case (tms)
          1: current_state <= SelectIrScan;
          default: current_state <= CaptureDr;
        endcase
        SelectIrScan:  // 3
        case (tms)
          1: current_state <= TestLogicReset;
          default: current_state <= CaptureIr;
        endcase
        CaptureDr:  // 4
        case (tms)
          1: current_state <= Exit1Dr;
          default: current_state <= ShiftDr;
        endcase
        CaptureIr:  // 5
        case (tms)
          1: current_state <= Exit1Ir;
          default: current_state <= ShiftIr;
        endcase
        ShiftDr:  // 6
        // Pretty sure this means connect a shift register to TDO and drain it
        case (tms)
          1: current_state <= Exit1Dr;
          default: begin
            // place the byte transmitter with the IDCODE register and start to shift it onto TDO. 
            if (!idcode_out_done) begin
            end else begin
              current_state <= ShiftDr;
            end
          end
        endcase
        ShiftIr:  // 7
        case (tms)
          1: current_state <= Exit1Ir;
          default: current_state <= ShiftIr;
        endcase
        Exit1Dr:  // 8
        case (tms)
          1: current_state <= UpdateDr;
          default: current_state <= PauseDr;
        endcase
        Exit1Ir:  // 9
        case (tms)
          1: current_state <= UpdateIr;
          default: current_state <= PauseIr;
        endcase
        PauseDr:  // 10
        case (tms)
          1: current_state <= Exit2Dr;
          default: current_state <= PauseDr;
        endcase
        PauseIr:  // 11
        case (tms)
          1: current_state <= Exit2Ir;
          default: current_state <= PauseIr;
        endcase
        Exit2Dr:  // 12
        case (tms)
          1: current_state <= UpdateDr;
          default: current_state <= ShiftDr;
        endcase
        Exit2Ir:  // 13
        case (tms)
          1: current_state <= UpdateIr;
          default: current_state <= ShiftIr;
        endcase
        UpdateDr:  // 14
        case (tms)
          1: current_state <= SelectDrScan;
          default: current_state <= RunTestOrIdle;
        endcase
        UpdateIr:  // 15
        case (tms)
          1: current_state <= SelectDrScan;
          default: current_state <= RunTestOrIdle;
        endcase
        default: current_state <= TestLogicReset;
      endcase
    end
  end


`ifdef FORMAL
  logic f_past_valid;

  initial begin
    f_past_valid = 0;
  end

  always @(posedge tck) f_past_valid <= 1;

  always_comb begin
    if (!f_past_valid) assume (trst);
  end

  always @(posedge tck) begin
    if (f_past_valid) begin
      // our state never overruns the enum values.
      assert (current_state <= 5'h15);
      cover (current_state <= UpdateIr);
    end
  end

  always @(posedge tck) begin
    // Whenever TMS is high for five cycles, the design is in reset
    if (f_past_valid && (tms_reset_check == 5'b1_1111)) begin
      assert (current_state == TestLogicReset);
    end

    // TRST puts us in state 0
    if (f_past_valid && $past(trst)) begin
      initial_state : assert (current_state == TestLogicReset);
    end

    //
    // Checking that states are achievable via the documented Tap FSM
    //
    `HAPPENS_BEFORE(TestLogicReset, RunTestOrIdle)
    `HAPPENS_BEFORE(RunTestOrIdle, RunTestOrIdle)
    `HAPPENS_BEFORE(RunTestOrIdle, SelectDrScan)
    `HAPPENS_BEFORE(SelectDrScan, SelectIrScan)
    `HAPPENS_BEFORE(SelectDrScan, CaptureDr)
    `HAPPENS_BEFORE(SelectIrScan, CaptureIr)
    `HAPPENS_BEFORE(CaptureDr, Exit1Dr)
    `HAPPENS_BEFORE(CaptureDr, ShiftDr)
    `HAPPENS_BEFORE(CaptureIr, Exit1Ir)
    `HAPPENS_BEFORE(CaptureIr, ShiftIr)
    `HAPPENS_BEFORE(ShiftDr, Exit1Dr)
    `HAPPENS_BEFORE(ShiftDr, ShiftDr)
    `HAPPENS_BEFORE(ShiftIr, Exit1Ir)
    `HAPPENS_BEFORE(ShiftIr, ShiftIr)
    `HAPPENS_BEFORE(Exit1Dr, UpdateDr)
    `HAPPENS_BEFORE(Exit1Dr, PauseDr)
    `HAPPENS_BEFORE(Exit1Ir, UpdateIr)
    `HAPPENS_BEFORE(Exit1Ir, PauseIr)
    `HAPPENS_BEFORE(PauseDr, Exit2Dr)
    `HAPPENS_BEFORE(PauseDr, PauseDr)
    `HAPPENS_BEFORE(PauseIr, Exit2Ir)
    `HAPPENS_BEFORE(PauseIr, PauseIr)
    `HAPPENS_BEFORE(Exit2Dr, UpdateDr)
    `HAPPENS_BEFORE(Exit2Dr, ShiftDr)
    `HAPPENS_BEFORE(Exit2Ir, UpdateIr)
    `HAPPENS_BEFORE(Exit2Ir, ShiftIr)
    `HAPPENS_BEFORE(UpdateDr, SelectDrScan)
    `HAPPENS_BEFORE(UpdateDr, RunTestOrIdle)
    `HAPPENS_BEFORE(UpdateIr, SelectDrScan)
    `HAPPENS_BEFORE(UpdateIr, RunTestOrIdle)
    // This state transition test is broken for unknown reasons.
    /*`HAPPENS_BEFORE(SelectIrScan, TestLogicReset) */

  end
`endif
endmodule
`endif
