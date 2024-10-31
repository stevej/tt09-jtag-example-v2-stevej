`ifndef _MINIPIT_
`define _MINIPIT_

`default_nettype none

module minipit (
    input clk,
    input rst_n,
    input enable,
    input write_enable,
    input repeating,
    input [7:0] counter_high,
    input [7:0] counter_low,
    output wire interrupting
);

  wire counter_set;
  reg  r_counter_set;
  assign counter_set = r_counter_set;

  reg r_interrupting;
  assign interrupting = r_interrupting;

  // counter derived from config byte 1 concatenated with config byte 0
  reg [15:0] counter;
  reg [15:0] current_count;

  always @(posedge clk) begin
    if (!rst_n) begin
      counter <= 16'd10;  // TODO: don't auto-set a counter
      current_count <= 16'd0;
      r_counter_set <= 1;  // TODO: don't auto-enable a default counter
      r_interrupting <= 0;
    end else if (enable) begin
      if (write_enable) begin
        counter <= {counter_high, counter_low};
      end else begin
        r_counter_set <= 1;
      end

      if (counter_set) begin
        current_count <= current_count + 1;
      end else begin
        current_count <= current_count;
      end

      if (counter_set && (current_count == (counter - 1))) begin
        // pull interrupt line high for one clock cycle
        r_interrupting <= 1;
        if (repeating) begin
          current_count <= 0;
        end

      end else begin
        r_interrupting <= 0;
      end
    end
  end
endmodule
`endif
