`timescale 1ns/1ps

// Output-stationary processing element.
//
// Every valid paired-operand token is multiply-accumulated at the rising edge
// and registered for forwarding. Registered forwarding makes each hop through
// an array take one clock cycle; invalid cycles are bubbles.
module pe_os #(
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = 32
) (
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         clear,
    input  logic                         in_valid,
    input  logic signed [DATA_WIDTH-1:0] a_in,
    input  logic signed [DATA_WIDTH-1:0] w_in,
    output logic                         out_valid,
    output logic signed [DATA_WIDTH-1:0] a_out,
    output logic signed [DATA_WIDTH-1:0] w_out,
    output logic signed [ACC_WIDTH-1:0]  acc
);

    localparam int PRODUCT_WIDTH = 2 * DATA_WIDTH;

    logic signed [PRODUCT_WIDTH-1:0] product;
    logic signed [ACC_WIDTH-1:0]     product_extended;

    // Keep the multiply in a precisely sized signed signal before explicitly
    // extending it to the accumulator width.
    assign product          = a_in * w_in;
    assign product_extended = {{(ACC_WIDTH - PRODUCT_WIDTH){product[PRODUCT_WIDTH-1]}}, product};

    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid <= 1'b0;
            a_out <= '0;
            w_out <= '0;
            acc   <= '0;
        end else if (clear) begin
            out_valid <= 1'b0;
            a_out <= '0;
            w_out <= '0;
            acc   <= '0;
        end else begin
            out_valid <= in_valid;

            if (in_valid) begin
                a_out <= a_in;
                w_out <= w_in;
                acc   <= acc + product_extended;
            end else begin
                a_out <= '0;
                w_out <= '0;
            end
        end
    end

endmodule : pe_os
