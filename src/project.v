/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */
`ifndef _PROJECT_
`define _PROJECT_

`default_nettype none

`include "jtag.v"
`include "minipit.v"

module tt_um_jtag_example_stevej (
    input wire [7:0] ui_in,  // Dedicated inputs
    output wire [7:0] uo_out,  // Dedicated outputs
    input wire [7:0] uio_in,  // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,  // IOs: Enable path (active high: 0=input, 1=output)
    input wire ena,  // always 1 when the design is powered, so you can ignore it
    input wire clk,  // clock
    input wire rst_n  // reset_n - low to reset
);

  // All output pins must be assigned. If not used, assign to 0.
  //assign uo_out  = ui_in + uio_in;  // Example: ou_out is the sum of ui_in and uio_in
  assign uio_out = 0;
  assign uio_oe  = 0;

  wire tdo;
  wire interrupting;
  assign uo_out[7] = interrupting;
  assign uo_out[6] = interrupting;
  assign uo_out[5] = interrupting;
  assign uo_out[4] = interrupting;
  assign uo_out[3] = interrupting;
  assign uo_out[2] = interrupting;
  assign uo_out[1] = interrupting;
  assign uo_out[0] = tdo;

  jtag jtag0 (
      .tck(ui_in[0]),
      .tdi(ui_in[1]),
      .tms(ui_in[2]),
      .trst_n(ui_in[3]),
      .enable(ena),
      .tdo(tdo)
  );

  // A hard configured interrupt rising high every 10 cycles for 1 cycle.
  minipit minipit0 (
      .clk(clk),
      .rst_n(rst_n),
      .enable(ena),
      .repeating(1'b1),
      .counter(16'hA),
      .interrupting(interrupting)
  );

  // Set unused wires
  assign uio_out[7:1] = 7'b000_0000;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, ui_in, uio_in};

endmodule
`endif
