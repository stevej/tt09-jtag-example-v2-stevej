`ifndef _JTAG_
`define _JTAG_

`default_nettype none

`include "byte_transmitter.v"

// Ensures that the first_state happens before the second_state.
// We use a label as a breadcrumb in case an invalid state is asserted
`define HAPPENS_BEFORE(first_state, second_state) \
  if (f_past_valid && $past(!trst_n) && trst_n && current_state == second_state) begin \
    HA_``first_state``_to_``second_state : assert ($past(current_state) == first_state); \
  end;

// Ensures that we are able to leave the state in the FSM.
`define STATE_EXITS(state) \
  if (f_past_valid && $past(!trst_n) && trst_n && $past(current_state) == state) begin \
   STATE_EXITS_``state`` : assert (current_state != state); \
  end;

module jtag (
`ifdef FORMAL (*gclk*)
`endif
    input  logic clk_tck,
    /* verilator lint_off UNUSED */
    input  logic tdi,
    input  logic tms,
    input  logic trst_n,   /* TRST_N active low reset */
    input  logic enable,
    output logic tdo
);

  // Debug signals to see how far we've gotten in the TAP state machine.
  logic in_run_test_idle;
  logic in_select_dr_scan;
  logic in_capture_dr;
  logic in_shift_dr;
  logic in_exit1_dr;

  // TAP Controller state machine current_state values
  localparam logic [3:0] TestLogicReset = 4'h0;  // 0
  localparam logic [3:0] RunTestOrIdle = 4'h1;  // 1
  localparam logic [3:0] SelectDrScan = 4'h2;  // 2
  localparam logic [3:0] SelectIrScan = 4'h3;  // 4
  localparam logic [3:0] CaptureDr = 4'h4;  // 8
  localparam logic [3:0] CaptureIr = 4'h5;  // 10
  localparam logic [3:0] ShiftDr = 4'h6;  // 20
  localparam logic [3:0] ShiftIr = 4'h7;  // 40
  localparam logic [3:0] Exit1Dr = 4'h8;  // 80
  localparam logic [3:0] Exit1Ir = 4'h9;  // 100
  localparam logic [3:0] PauseDr = 4'hA;  // 100
  localparam logic [3:0] PauseIr = 4'hB;  // 200
  localparam logic [3:0] Exit2Dr = 4'hC;  // 400
  localparam logic [3:0] Exit2Ir = 4'hD;  // 800
  localparam logic [3:0] UpdateDr = 4'hE;  // 1000
  localparam logic [3:0] UpdateIr = 4'hF;  // 2000

  logic [3:0] current_state;

  // IR Instruction values
  localparam logic [3:0] Abort = 4'b1000;
  localparam logic [3:0] IdCode = 4'b1110;
  localparam logic [3:0] Bypass = 4'b1111;

  logic [3:0] current_ir_instruction;

  // DR Register containing the IDCODE of our jtag device.
  localparam logic [31:0] IdCodeDrlogicister = 32'hFAF01;

  // whether a reset in the main design has been seen.
  //wire r_in_reset_from_main_clk;

  // for checking that the TAP state machine is in reset at the right time.
`ifdef FORMAL
  logic [4:0] f_tms_reset_check;
`endif

  // Are we done writing the idcode?
  wire  idcode_out_done;

  logic byte_transmitter_enable;
  logic reset_byte_transmitter;
  wire  transmitter_channel;  // for byte_transmitter to write to TDO

  byte_transmitter id_byte_transmitter (
      .clk_tck(clk_tck),
      .reset(~trst_n | reset_byte_transmitter),
      .enable(byte_transmitter_enable),
      .in(IdCodeDrlogicister),
      .out(transmitter_channel),  // make this another wire.
      .done(idcode_out_done)
  );

  logic tap_channel;  // for TAP controller to write to TDO
  logic r_output_selector_transmitter;  // 1 means TAP controller, 0 means byte transmitter

  assign tdo = r_output_selector_transmitter ? tap_channel : transmitter_channel;

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

  always @(negedge clk_tck) begin
    if (r_output_selector_transmitter) tap_channel <= 1'b0;
  end

  always @(posedge clk_tck) begin
    if (!trst_n) begin
      in_run_test_idle <= 1'b0;
      in_select_dr_scan <= 1'b0;
      in_capture_dr <= 1'b0;
      in_shift_dr <= 1'b0;
      in_exit1_dr <= 1'b0;

      current_state <= TestLogicReset;  // State 0
`ifdef FORMAL
      f_tms_reset_check <= 5'h0;
`endif
      current_ir_instruction <= IdCode;  // IDCODE is the default instruction.
      r_output_selector_transmitter <= 1'b1;  // by default the tap controller writes
      byte_transmitter_enable <= 1'b0;
      reset_byte_transmitter <= 1'b0;
    end else if (enable) begin
      in_run_test_idle <= 1'b0;
      in_select_dr_scan <= 1'b0;
      in_capture_dr <= 1'b0;
      in_shift_dr <= 1'b0;
      in_exit1_dr <= 1'b0;

      // TODO: Trying to set a default value here might backfire on me.
      current_state <= current_state;
`ifdef FORMAL
      f_tms_reset_check <= f_tms_reset_check << 1;
      f_tms_reset_check[0] <= tms;
`endif
      current_ir_instruction <= current_ir_instruction;
      r_output_selector_transmitter <= r_output_selector_transmitter;
      byte_transmitter_enable <= byte_transmitter_enable;
      reset_byte_transmitter <= reset_byte_transmitter;
      // TAP state machine
      unique case (current_state)
        TestLogicReset: begin  // 0
`ifdef FORMAL
          f_tms_reset_check <= 5'h0;
`endif
          unique case (tms)
            1: current_state <= TestLogicReset;
            default: current_state <= RunTestOrIdle;
          endcase
        end
        RunTestOrIdle: begin  // 1
          in_run_test_idle <= 1'b1;
          unique case (tms)
            1: current_state <= SelectDrScan;
            default: current_state <= RunTestOrIdle;
          endcase
        end
        SelectDrScan: begin  // 2
          in_select_dr_scan <= 1'b1;
          unique case (tms)
            1: current_state <= SelectIrScan;
            default: current_state <= CaptureDr;
          endcase
        end
        SelectIrScan: begin  // 3
          unique case (tms)
            1: current_state <= TestLogicReset;
            default: current_state <= CaptureIr;
          endcase
        end
        CaptureDr: begin  // 4
          in_capture_dr <= 1'b1;
          unique case (tms)
            1: current_state <= Exit1Dr;
            default: begin
              current_state <= ShiftDr;
              unique case (current_ir_instruction)
                IdCode: begin
                  // place the byte transmitter with the IDCODE register and start to shift it onto TDO.
                  r_output_selector_transmitter <= 1'b0;
                  byte_transmitter_enable <= 1'b1;
                end
                Abort: begin
                  current_state <= ShiftDr;
                end
                Bypass: begin
                  // TODO: disable pins connected to the scan chain
                  current_state <= ShiftDr;
                end
                default: begin
                  current_state <= ShiftDr;
                end
              endcase
            end
          endcase
        end
        CaptureIr: begin  // 5
          unique case (tms)
            1: current_state <= Exit1Ir;
            default: current_state <= ShiftIr;
          endcase
        end
        ShiftDr: begin  // 6
          in_shift_dr <= 1'b1;
          // in the Shift-DR state, this data is shifted out, least significant bit first
          // Pretty sure this means connect a shift register to TDO and drain it
          unique case (tms)
            1: current_state <= Exit1Dr;
            default: begin
              unique case (current_ir_instruction)
                IdCode: begin
                  if (!idcode_out_done) begin
                    current_state <= ShiftDr;
                  end else begin
                    reset_byte_transmitter <= 1'b1;
                    byte_transmitter_enable <= 1'b0;
                    r_output_selector_transmitter <= 1'b1; // give the TAP controller write control.
                    current_state <= Exit1Dr;  // Not sure if this is correct.
                  end
                end
                default: begin
                  // If a bad instruction is given, go back to default state
                  current_state <= TestLogicReset;
                end
              endcase
            end
          endcase
        end
        ShiftIr: begin  // 7
          unique case (tms)
            1: current_state <= Exit1Ir;
            default: current_state <= ShiftIr;
          endcase
        end
        Exit1Dr: begin  // 8
          in_exit1_dr <= 1'b1;
          unique case (tms)
            1: current_state <= UpdateDr;
            default: current_state <= PauseDr;
          endcase
        end
        Exit1Ir: begin  // 9
          unique case (tms)
            1: current_state <= UpdateIr;
            default: current_state <= PauseIr;
          endcase
        end
        PauseDr: begin  // 10
          unique case (tms)
            1: current_state <= Exit2Dr;
            default: current_state <= PauseDr;
          endcase
        end
        PauseIr: begin  // 11
          unique case (tms)
            1: current_state <= Exit2Ir;
            default: current_state <= PauseIr;
          endcase
        end
        Exit2Dr: begin  // 12
          unique case (tms)
            1: current_state <= UpdateDr;
            default: current_state <= ShiftDr;
          endcase
        end
        Exit2Ir: begin  // 13
          unique case (tms)
            1: current_state <= UpdateIr;
            default: current_state <= ShiftIr;
          endcase
        end
        UpdateDr: begin  // 14
          unique case (tms)
            1: current_state <= SelectDrScan;
            default: current_state <= RunTestOrIdle;
          endcase
        end
        UpdateIr: begin  // 15
          unique case (tms)
            1: current_state <= SelectDrScan;
            default: current_state <= RunTestOrIdle;
          endcase
        end
        default: begin
          current_state <= TestLogicReset;
        end
      endcase
    end else begin
      current_state <= TestLogicReset;
    end
  end


`ifdef FORMAL
  logic f_past_valid;

  initial begin
    f_past_valid = 0;
  end

  always @(posedge clk_tck) f_past_valid <= 1;

  always @(posedge clk_tck) begin
    if (f_past_valid) begin
      // our state never overruns the enum values.
      cover (current_state <= UpdateIr);
    end

    if (f_past_valid && $past(!trst_n) && $past(trst_n)) begin
      // Checks that default values are making it out of reset.
      assert (current_state == 5'b0_0000);
      assert (r_output_selector_transmitter == 1'b1);
      assert (transmitter_channel == 1'b0);
      assert (tdo == 1'b0);
      assert (byte_transmitter_enable == 1'b0);
    end
  end

  always @(posedge clk_tck) begin
    // Whenever TMS is high for five cycles, the design is in reset
    if (f_past_valid && $past(~trst_n) && trst_n && ($past(f_tms_reset_check) == 5'b1_1111)) begin
      assert (current_state == TestLogicReset);
      assert (tdo != 1'bX);
    end

    // TRST_n low then high puts us in state 0
    if (f_past_valid && $past(!trst_n) && trst_n) begin
      initial_state : assert (current_state == TestLogicReset);
      assert (tdo != 1'bX);
      assert (r_output_selector_transmitter != 1'bX);
    end

    //
    // Checking that the documented TAP FSM state transitions are achievable.
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
    `HAPPENS_BEFORE(SelectIrScan, TestLogicReset)

    // Assert that we can leave each state of the Tap FSM
    `STATE_EXITS(TestLogicReset)
    `STATE_EXITS(RunTestOrIdle)
    `STATE_EXITS(SelectDrScan)
    `STATE_EXITS(SelectIrScan)
    `STATE_EXITS(CaptureDr)
    `STATE_EXITS(CaptureIr)
    `STATE_EXITS(ShiftDr)
    `STATE_EXITS(ShiftIr)
    `STATE_EXITS(Exit1Dr)
    `STATE_EXITS(Exit1Ir)
    `STATE_EXITS(PauseDr)
    `STATE_EXITS(PauseIr)
    `STATE_EXITS(Exit2Dr)
    `STATE_EXITS(Exit2Ir)
    `STATE_EXITS(UpdateDr)
    `STATE_EXITS(UpdateIr)

  end
`endif
  `undef HAPPENS_BEFORE
  `undef STATE_EXITS

endmodule
`endif
