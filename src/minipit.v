`ifndef _MINIPIT_
`define _MINIPIT_

`default_nettype none

module minipit (
    input clk,
    input rst_n,
    input enable,
    input repeating,
    input [15:0] counter,
    output wire interrupting
);

  reg r_interrupting;
  assign interrupting = r_interrupting;

  reg [15:0] current_count;

  wire counter_tripped;
  assign counter_tripped = enable && (current_count == (counter - 16'h1));

  always @(posedge clk) begin
    if (!rst_n) begin
      current_count  <= 16'h0;
      r_interrupting <= 1'b0;
    end else begin
      current_count <= current_count + 16'h1;

      if (counter_tripped) begin
        // pull interrupt line high for one clock cycle
        r_interrupting <= 1'b1;
        if (repeating) begin
          current_count <= 16'h0;
        end
      end else begin
        r_interrupting <= 1'b0;
      end
    end
  end
endmodule
`endif
