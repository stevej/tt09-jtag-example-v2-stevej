`ifndef _BYTE_TRANSMITTER_
`define _BYTE_TRANSMITTER_

`default_nettype none

// Given a byte, writes out 1 bit at a time while enable is high.
// Assumes the caller is tracking when 8 bits is sent.
module byte_transmitter (
`ifdef FORMAL (*gclk*)
`endif
    input logic clk_tck,
    input logic reset,
    input logic enable,
    // TODO: make size configurable
    input logic [31:0] in,  // byte_buffer
    output logic out,
    output logic done
);

`ifdef FORMAL
  logic [5:0] f_total_written;
`endif
  logic [5:0] byte_count;
  logic r_out;
  assign out = r_out;
  logic r_done;
  assign done = r_done;

  // TDO must be written on the falling edge
  // to avoid hold violations.
  always_ff @(negedge clk_tck) begin
    if (reset) begin
      byte_count <= 6'h20;
      r_done <= 1'b0;
      r_out <= 1'b0;
`ifdef FORMAL
      f_total_written <= 6'h0;
`endif
    end else if (enable) begin
      if (byte_count > 6'h0) begin
`ifdef FORMAL
        f_total_written <= f_total_written + 6'h1;
        assert (r_out != 1'bX);
        assert (byte_count != 5'bX_XXXX);
        assert (byte_count[0] != 1'bX);
        assert (byte_count[1] != 1'bX);
        assert (byte_count[2] != 1'bX);
        assert (byte_count[3] != 1'bX);
        assert (byte_count[4] != 1'bX);
        assert (in[byte_count:(byte_count-1)] != 1'bX);
`endif
        r_out <= in[byte_count-1];
        byte_count <= (byte_count - 6'd1);
      end else begin
        byte_count <= 6'h20;
        r_done <= 1'b1;
        r_out <= 1'b0;
      end
    end else begin
      byte_count <= 6'h20;
      r_done <= 1'b0;
      r_out <= 1'b0;
    end
  end

`ifdef FORMAL
  logic f_past_valid;

  initial begin
    f_past_valid = 0;
  end

  always @(posedge clk_tck) f_past_valid <= 1;

  always @(posedge clk_tck) begin
    assume (reset);

    if (f_past_valid && enable && done) begin
      assert (f_total_written == 32);  // We've drained the entire buffer.
      assert (byte_count == 0);
      assert (r_out != 1'bX);
      assert (done != 1'bX);
    end

    if (f_past_valid && enable && byte_count == 0) begin
      assert (f_total_written == 32);
      assert (done);
      assert (r_out != 1'bX);
    end
  end

`endif
endmodule
`endif
