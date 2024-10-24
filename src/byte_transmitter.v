`ifndef _BYTE_TRANSMITTER_
`define _BYTE_TRANSMITTER_

`default_nettype none
`timescale 1us / 100 ns

// Given a byte, writes out 1 bit at a time while enable is high.
// Assumes the caller is tracking when 8 bits is sent.
module byte_transmitter (
    input clk,
    input reset,
    input enable,
    // TODO: make [31:0] configurable
    input wire [31:0] in,  // byte_buffer
    output wire out,
    output wire done
);

  reg [5:0] byte_count;
  reg r_out;
  assign out = r_out;
  reg r_done;
  assign done = r_done;

  always @(posedge clk) begin
    if (reset) begin
      byte_count <= 6'h20;
      r_done <= 0;
    end else begin
      if (enable) begin
        if (byte_count > 0) begin
          r_out <= in[byte_count - 1];
          byte_count <= byte_count - 1;
       end else begin
         r_done <= 1;
       end
      end
    end
  end

`ifdef FORMAL
  logic f_past_valid;

  initial begin
    f_past_valid = 0;
  end

  always @(posedge clk) f_past_valid <= 1;

  always @(posedge clk) begin
    assume(reset);

    if (f_past_valid && done) begin
      assert(byte_count == 0);
    end

    if (f_past_valid && byte_count == 0) begin
      assert(done);
    end
  end

`endif
endmodule
`endif
