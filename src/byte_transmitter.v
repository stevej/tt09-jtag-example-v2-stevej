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

`ifdef FORMAL
  reg [5:0] f_total_written;
`endif
  reg [5:0] byte_count;
  reg r_out;
  assign out = r_out;
  reg r_done;
  assign done = r_done;

  always @(posedge clk) begin
    if (reset) begin
      byte_count <= 6'h20;
      r_done <= 0;
      r_out <= 0;
`ifdef FORMAL
      f_total_written <= 0;
`endif
    end else begin
      if (enable) begin
        if (byte_count > 0) begin
`ifdef FORMAL
          f_total_written <= f_total_written + 1;
          assert(r_out != 1'bX);
`endif
          r_out <= in[byte_count - 1];
          byte_count <= byte_count - 1;
        end else begin
          byte_count <= 6'h20;
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

    if (f_past_valid && enable && done) begin
      assert(f_total_written == 32); // We've drained the entire buffer.
      assert(byte_count == 0);
      assert(r_out != 1'bX);
    end

    if (f_past_valid && enable && byte_count == 0) begin
      assert(done);
      assert(f_total_written == 32);
    end
  end

`endif
endmodule
`endif
