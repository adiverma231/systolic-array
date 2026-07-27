`timescale 1ns/1ps

// Register-based result tile storage for the Stage 1 OS wrapper.
//
// The complete mesh accumulator tile is captured on capture_en, then a host
// selects one signed result with a combinational row/column read.
module output_buffer #(
    parameter int N         = 4,
    parameter int ACC_WIDTH = 32
) (
    input  logic clk,
    input  logic rst,
    input  logic capture_en,
    input  logic signed [ACC_WIDTH-1:0] acc_in [0:N-1][0:N-1],

    input  logic [((N > 1) ? $clog2(N) : 1)-1:0] result_row,
    input  logic [((N > 1) ? $clog2(N) : 1)-1:0] result_col,
    output logic signed [ACC_WIDTH-1:0]          result_data
);

    logic signed [ACC_WIDTH-1:0] c_tile [0:N-1][0:N-1];

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int row = 0; row < N; row++) begin
                for (int col = 0; col < N; col++) begin
                    c_tile[row][col] <= '0;
                end
            end
        end else if (capture_en) begin
            for (int row = 0; row < N; row++) begin
                for (int col = 0; col < N; col++) begin
                    c_tile[row][col] <= acc_in[row][col];
                end
            end
        end
    end

    always_comb begin
        result_data = c_tile[result_row][result_col];
    end

endmodule : output_buffer
