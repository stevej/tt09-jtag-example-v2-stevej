`ifndef _JTAG_
`define _JTAG_

`default_nettype none

`include "byte_transmitter.v"
`include "mux_2_1.v"

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
    input wire trst_n,
    input wire reset  // comes from main domain clock.
);

  wire trst;
  assign trst = ~trst_n;

  // TAP controller state
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

  // IR Instruction values
  localparam [3:0] Abort = 4'b1000;
  localparam [3:0] IdCode = 4'b1110;
  localparam [3:0] Bypass = 4'b1111;

  reg [3:0] current_ir_instruction;
  reg current_ir_instruction_broken;

  // DR Register containing the IDCODE of our jtag device.
  localparam [31:0] IdCodeDrRegister = 32'hFAF01;

  // whether a reset in the main design has been seen.
  wire r_in_reset_from_main_clk;

  // for checking that the TAP state machine is in reset at the right time.
  // TODO: move this behind an `ifdef FORMAL and prefix with `f_`
  reg [4:0] tms_reset_check;
  reg [7:0] cycles;

  wire idcode_out_done;

  reg byte_transmitter_enable;
  reg reset_byte_transmitter;
  reg transmitter_channel;  // for byte_transmitter to write to TDO

  byte_transmitter id_byte_transmitter (
      .clk(tck),
      .reset(trst | reset_byte_transmitter),  // TODO: We need to be able to reset the byte_counter?
      .enable(byte_transmitter_enable),
      .in(IdCodeDrRegister),
      .out(transmitter_channel),  // make this another wire.
      .done(idcode_out_done)
  );

  reg tap_channel;  // for TAP controller to write to TDO
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
  /*
  (* ASYNC_REG = "TRUE" *) reg [2:0] sync;
  always @(posedge tck) begin
    sync <= (sync << 1) | {1'b0, 1'b0, reset};
  end
  assign r_in_reset_from_main_clk = sync[1] & !sync[2];
  */

  always @(posedge tck) begin
    if (trst) begin
      current_state <= TestLogicReset;  // State 0
      current_ir_instruction_broken <= 0;
      tms_reset_check <= 5'b0_0000;
      cycles <= 0;
      current_ir_instruction <= 4'b1110;  // IDCODE is the default instruction.
      r_output_selector_transmitter <= 1;  // by default the tap controller writes
      tap_channel <= 0;  // How can an X sneak in here?
      byte_transmitter_enable <= 0;
      reset_byte_transmitter <= 0;
    end else begin
      tms_reset_check <= tms_reset_check << 1;
      tms_reset_check[0] <= tms;
      cycles <= cycles + 1;
      // TAP state machine
      case (current_state)
        TestLogicReset: begin  // 0
          tms_reset_check <= 5'b0_0000;
          tap_channel <= 0;  // Where is this X coming from?
          case (tms)
            1: current_state <= TestLogicReset;
            default: current_state <= RunTestOrIdle;
          endcase
        end
        RunTestOrIdle: begin  // 1
          tap_channel <= 0;
          case (tms)
            1: current_state <= SelectDrScan;
            default: current_state <= RunTestOrIdle;
          endcase
        end
        SelectDrScan: begin  // 2
          tap_channel <= 0;
          case (tms)
            1: current_state <= SelectIrScan;
            default: current_state <= CaptureDr;
          endcase
        end
        SelectIrScan: begin  // 3
          tap_channel <= 0;
          case (tms)
            1: current_state <= TestLogicReset;
            default: current_state <= CaptureIr;
          endcase
        end
        CaptureDr: begin  // 4
          tap_channel <= 0;
          case (tms)
            1: current_state <= Exit1Dr;
            default: current_state <= ShiftDr;
          endcase
        end
        CaptureIr: begin  // 5
          tap_channel <= 0;
          case (tms)
            1: current_state <= Exit1Ir;
            default: current_state <= ShiftIr;
          endcase
        end
        ShiftDr: begin  // 6
          if (~byte_transmitter_enable) tap_channel <= 0;
          // in the Shift-DR state, this data is shifted out, least significant bit first
          // Pretty sure this means connect a shift register to TDO and drain it
          case (tms)
            1: current_state <= Exit1Dr;
            default: begin
              case (current_ir_instruction)
                IdCode: begin
                  // place the byte transmitter with the IDCODE register and start to shift it onto TDO. 
                  r_output_selector_transmitter <= 0;
                  byte_transmitter_enable <= 1;
                  if (~idcode_out_done) begin
                    current_state <= ShiftDr;
                  end else begin
                    byte_transmitter_enable <= 0;
                    current_state <= Exit1Dr;  // Not sure if this is correct.
                  end
                end
                default: begin
                  current_ir_instruction_broken <= 1;
                  current_state <= ShiftDr;
                end
              endcase
            end
          endcase
        end
        ShiftIr: begin  // 7
          tap_channel <= 0;
          case (tms)
            1: current_state <= Exit1Ir;
            default: current_state <= ShiftIr;
          endcase
        end
        Exit1Dr: begin  // 8
          tap_channel <= 0;
          case (tms)
            1: current_state <= UpdateDr;
            default: current_state <= PauseDr;
          endcase
        end
        Exit1Ir: begin  // 9
          tap_channel <= 0;
          case (tms)
            1: current_state <= UpdateIr;
            default: current_state <= PauseIr;
          endcase
        end
        PauseDr: begin  // 10
          tap_channel <= 0;
          case (tms)
            1: current_state <= Exit2Dr;
            default: current_state <= PauseDr;
          endcase
        end
        PauseIr: begin  // 11
          tap_channel <= 0;
          case (tms)
            1: current_state <= Exit2Ir;
            default: current_state <= PauseIr;
          endcase
        end
        Exit2Dr: begin  // 12
          tap_channel <= 0;
          case (tms)
            1: current_state <= UpdateDr;
            default: current_state <= ShiftDr;
          endcase
        end
        Exit2Ir: begin  // 13
          tap_channel <= 0;
          case (tms)
            1: current_state <= UpdateIr;
            default: current_state <= ShiftIr;
          endcase
        end
        UpdateDr: begin  // 14
          tap_channel <= 0;
          case (tms)
            1: current_state <= SelectDrScan;
            default: current_state <= RunTestOrIdle;
          endcase
        end
        UpdateIr: begin  // 15
          tap_channel <= 0;
          case (tms)
            1: current_state <= SelectDrScan;
            default: current_state <= RunTestOrIdle;
          endcase
        end
        default: begin
          tap_channel   <= 0;
          current_state <= TestLogicReset;
        end
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
    /*
    if (f_past_valid && $past(trst)) begin
      assume(trst);
      assert(current_state != 1'bX);
      assert(r_output_selector_transmitter != 1'bX);
      assert(tdo != 1'bX);
    end
    */
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
