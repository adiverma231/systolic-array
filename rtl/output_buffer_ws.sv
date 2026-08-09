`timescale 1ns/1ps

// Streamed-result storage for the weight-stationary datapath.
//
// Each bottom-edge column independently supplies a valid result tagged with
// its output row.  A valid token writes C[result_tag[column]][column].
// The tile is cleared at the start of a transaction and supports a
// combinational addressed signed read through the common top-level interface.
module output_buffer_ws #(
    parameter int N         = 4,
    parameter int ACC_WIDTH = 32,
    parameter int TAG_WIDTH = (N > 1) ? $clog2(N) : 1
) (
    input  logic clk,
    input  logic rst,
    input  logic clear,

    input  logic                         result_valid [0:N-1],
    input  logic [TAG_WIDTH-1:0]         result_tag [0:N-1],
    input  logic signed [ACC_WIDTH-1:0]  result_data [0:N-1],

    input  logic [((N > 1) ? $clog2(N) : 1)-1:0] result_row,
    input  logic [((N > 1) ? $clog2(N) : 1)-1:0] result_col,
    output logic signed [ACC_WIDTH-1:0]          result_read_data
);

    logic signed [ACC_WIDTH-1:0] c_tile [0:N-1][0:N-1];

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            for (int row = 0; row < N; row++) begin
                for (int col = 0; col < N; col++) begin
                    c_tile[row][col] <= '0;
                end
            end
        end else begin
            for (int col = 0; col < N; col++) begin
                if (result_valid[col])
                    c_tile[result_tag[col]][col] <= result_data[col];
            end
        end
    end

    always_comb begin
        result_read_data = c_tile[result_row][result_col];
    end

    initial begin
        if (N < 1 || ACC_WIDTH < 1 || TAG_WIDTH < 1)
            $fatal(1,
                "output_buffer_ws parameters must be positive (N=%0d, ACC_WIDTH=%0d, TAG_WIDTH=%0d)",
                N, ACC_WIDTH, TAG_WIDTH);
    end

endmodule : output_buffer_ws
