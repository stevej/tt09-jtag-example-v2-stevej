`ifndef _JTAG_
`define _JTAG_

`default_nettype none

`include "byte_transmitter.v"
`include "mux_2_1.v"

// Ensures that the first_state happens before the second_state.
// We use a label as a breadcrumb in case an invalid state is asserted
`define HAPPENS_BEFORE(first_state, second_state) \
  if (f_past_valid && $past(trst) && trst_n && current_state == second_state) begin \
    HA_``first_state``_to_``second_state : assert ($past(current_state) == first_state); \
  end;

module jtag (
    input  wire tck,
    /* verilator lint_off UNUSED */
    input  wire tdi,
    input  wire tms,
    input  wire trst_n,  /* RESET */
    input  wire enable,
    output wire tdo
);

  wire trst;
  assign trst = ~trst_n;

  // TAP controller state
  localparam bit [3:0] TestLogicReset = 4'h0;
  localparam bit [3:0] RunTestOrIdle = 4'h1;
  localparam bit [3:0] SelectDrScan = 4'h2;
  localparam bit [3:0] SelectIrScan = 4'h3;
  localparam bit [3:0] CaptureDr = 4'h4;
  localparam bit [3:0] CaptureIr = 4'h5;
  localparam bit [3:0] ShiftDr = 4'h6;
  localparam bit [3:0] ShiftIr = 4'h7;
  localparam bit [3:0] Exit1Dr = 4'h8;
  localparam bit [3:0] Exit1Ir = 4'h9;
  localparam bit [3:0] PauseDr = 4'hA;
  localparam bit [3:0] PauseIr = 4'hB;
  localparam bit [3:0] Exit2Dr = 4'hC;
  localparam bit [3:0] Exit2Ir = 4'hD;
  localparam bit [3:0] UpdateDr = 4'hE;
  localparam bit [3:0] UpdateIr = 4'hF;

  reg [3:0] current_state;

  // IR Instruction values
  localparam bit [3:0] Abort = 4'b1000;
  localparam bit [3:0] IdCode = 4'b1110;
  localparam bit [3:0] Bypass = 4'b1111;

  reg [3:0] current_ir_instruction;

  // DR Register containing the IDCODE of our jtag device.
  localparam bit [31:0] IdCodeDrRegister = 32'hFAF01;

  // whether a reset in the main design has been seen.
  //wire r_in_reset_from_main_clk;

  // for checking that the TAP state machine is in reset at the right time.
  // TODO: move this behind an `ifdef FORMAL and prefix with `f_`
  bit [4:0] tms_reset_check;
  bit [7:0] cycles;

  // Are we done writing the idcode?
  wire idcode_out_done;

  bit byte_transmitter_enable;
  bit reset_byte_transmitter;
  wire transmitter_channel;  // for byte_transmitter to write to TDO

  byte_transmitter id_byte_transmitter (
      .clk(tck),
      .reset(trst | reset_byte_transmitter),  // TODO: We need to be able to reset the byte_counter?
      .enable(byte_transmitter_enable),
      .in(IdCodeDrRegister),
      .out(transmitter_channel),  // make this another wire.
      .done(idcode_out_done)
  );

  bit tap_channel;  // for TAP controller to write to TDO
  bit r_output_selector_transmitter;  // 1 means TAP controller, 0 means byte transmitter
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
      tms_reset_check <= 5'b0_0000;
      cycles <= 8'b0000_0000;
      current_ir_instruction <= IdCode;  // IDCODE is the default instruction.
      r_output_selector_transmitter <= 1;  // by default the tap controller writes
      tap_channel <= 0;  // How can an X sneak in here?
      byte_transmitter_enable <= 0;
      reset_byte_transmitter <= 0;
    end else begin
      current_state <= current_state;
      tms_reset_check <= tms_reset_check << 1;
      tms_reset_check[0] <= tms;
      cycles <= cycles + 1'd1;
      current_ir_instruction <= current_ir_instruction;
      r_output_selector_transmitter <= r_output_selector_transmitter;
      tap_channel <= 0;
      byte_transmitter_enable <= byte_transmitter_enable;
      reset_byte_transmitter <= reset_byte_transmitter;
      // TAP state machine
      case (current_state)
        TestLogicReset: begin  // 0
          tms_reset_check <= 5'b0_0000;
          case (tms)
            1: current_state <= TestLogicReset;
            default: current_state <= RunTestOrIdle;
          endcase
        end
        RunTestOrIdle: begin  // 1
          case (tms)
            1: current_state <= SelectDrScan;
            default: current_state <= RunTestOrIdle;
          endcase
        end
        SelectDrScan: begin  // 2
          case (tms)
            1: current_state <= SelectIrScan;
            default: current_state <= CaptureDr;
          endcase
        end
        SelectIrScan: begin  // 3
          case (tms)
            1: current_state <= TestLogicReset;
            default: current_state <= CaptureIr;
          endcase
        end
        CaptureDr: begin  // 4
          case (tms)
            1: current_state <= Exit1Dr;
            default: current_state <= ShiftDr;
          endcase
        end
        CaptureIr: begin  // 5
          case (tms)
            1: current_state <= Exit1Ir;
            default: current_state <= ShiftIr;
          endcase
        end
        ShiftDr: begin  // 6
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
                    reset_byte_transmitter <= 1;
                    byte_transmitter_enable <= 0;
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
          case (tms)
            1: current_state <= Exit1Ir;
            default: current_state <= ShiftIr;
          endcase
        end
        Exit1Dr: begin  // 8
          case (tms)
            1: current_state <= UpdateDr;
            default: current_state <= PauseDr;
          endcase
        end
        Exit1Ir: begin  // 9
          case (tms)
            1: current_state <= UpdateIr;
            default: current_state <= PauseIr;
          endcase
        end
        PauseDr: begin  // 10
          case (tms)
            1: current_state <= Exit2Dr;
            default: current_state <= PauseDr;
          endcase
        end
        PauseIr: begin  // 11
          case (tms)
            1: current_state <= Exit2Ir;
            default: current_state <= PauseIr;
          endcase
        end
        Exit2Dr: begin  // 12
          case (tms)
            1: current_state <= UpdateDr;
            default: current_state <= ShiftDr;
          endcase
        end
        Exit2Ir: begin  // 13
          case (tms)
            1: current_state <= UpdateIr;
            default: current_state <= ShiftIr;
          endcase
        end
        UpdateDr: begin  // 14
          case (tms)
            1: current_state <= SelectDrScan;
            default: current_state <= RunTestOrIdle;
          endcase
        end
        UpdateIr: begin  // 15
          case (tms)
            1: current_state <= SelectDrScan;
            default: current_state <= RunTestOrIdle;
          endcase
        end
        default: begin
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

  always @(posedge tck) begin
    if (f_past_valid) begin
      // our state never overruns the enum values.
      assert (current_state < 5'h16);  // less-than or equals, not assignment
      cover (current_state <= UpdateIr);
    end

    if (f_past_valid && $past(~trst_n) && $past(trst_n)) begin
      // Checks that default values are making it out of reset.
      assert (current_state == 5'b0_0000);
      assert (r_output_selector_transmitter == 1'b1);
      assert (transmitter_channel == 1'b0);
      assert (tdo == 1'b0);
      assert (byte_transmitter_enable == 1'b0);
    end
  end


  /*
  always @(posedge tck) begin
    if (f_past_valid && $past(~trst_n) && trst_n) begin
      cover (current_state == ShiftDr);
      assert (tdo != 1'bX);
    end
  end
*/

  always @(posedge tck) begin
    // Whenever TMS is high for five cycles, the design is in reset
    if (f_past_valid && $past(~trst_n) && trst_n && ($past(tms_reset_check) == 5'b1_1111)) begin
      assert (current_state == TestLogicReset);
    end

    // TRST_n low then high puts us in state 0
    if (f_past_valid && $past(~trst_n) && trst_n) begin
      initial_state : assert (current_state == TestLogicReset);
      assert (tdo != 1'bX);
      assert (r_output_selector_transmitter != 1'bX);
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
    `HAPPENS_BEFORE(SelectIrScan, TestLogicReset)

  end
`endif
endmodule
`endif
