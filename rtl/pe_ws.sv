`timescale 1ns/1ps

// Weight-stationary processing element.
//
// A weight is captured during a dedicated preload cycle and remains local to
// the PE for the following computation.  During compute cycles, a valid token
// carries an activation east and an accumulating partial sum/tag south.  All
// forwarding is registered, so one PE traversal takes one clock cycle.
module pe_ws #(
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = 32,
    parameter int TAG_WIDTH  = 1
) (
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         clear,
    input  logic                         weight_load,
    input  logic signed [DATA_WIDTH-1:0] weight_in,
    input  logic                         compute_valid,
    input  logic signed [DATA_WIDTH-1:0] a_in,
    input  logic signed [ACC_WIDTH-1:0]  psum_in,
    input  logic        [TAG_WIDTH-1:0]  tag_in,
    output logic                         out_valid,
    output logic signed [DATA_WIDTH-1:0] a_out,
    output logic signed [ACC_WIDTH-1:0]  psum_out,
    output logic        [TAG_WIDTH-1:0]  tag_out
);

    localparam int PRODUCT_WIDTH = 2 * DATA_WIDTH;

    logic signed [DATA_WIDTH-1:0] weight;
    logic signed [PRODUCT_WIDTH-1:0] product;
    logic signed [ACC_WIDTH-1:0]     product_extended;

    // Preserve the signed multiply in its natural width, then explicitly
    // extend it before adding it to the accumulator-width partial sum.
    assign product          = a_in * weight;
    generate
        if (ACC_WIDTH >= PRODUCT_WIDTH) begin : gen_product_sign_extension
            assign product_extended = {
                {(ACC_WIDTH - PRODUCT_WIDTH){product[PRODUCT_WIDTH-1]}}, product
            };
        end else begin : gen_product_truncation
            // A narrower accumulator intentionally retains the low-order
            // ACC_WIDTH bits of the signed product.
            assign product_extended = product[ACC_WIDTH-1:0];
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            weight    <= '0;
            out_valid <= 1'b0;
            a_out     <= '0;
            psum_out  <= '0;
            tag_out   <= '0;
        end else if (weight_load) begin
            // Preload is a dedicated cycle.  It updates only the stationary
            // state and deliberately injects a bubble into the data paths.
            weight    <= weight_in;
            out_valid <= 1'b0;
            a_out     <= '0;
            psum_out  <= '0;
            tag_out   <= '0;
        end else begin
            out_valid <= compute_valid;

            if (compute_valid) begin
                a_out    <= a_in;
                psum_out <= psum_in + product_extended;
                tag_out  <= tag_in;
            end else begin
                a_out    <= '0;
                psum_out <= '0;
                tag_out  <= '0;
            end
        end
    end

endmodule : pe_ws
