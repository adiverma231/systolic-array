`timescale 1ns/1ps

// Register-based storage for one input tile pair.
//
// A is stored as A[N,K] and B as B[K,N].  A selected reduction index
// exposes the A column and B row required by one OS source cycle:
//   a_slice[row] = A[row][slice_index]
//   b_slice[col] = B[slice_index][col]
// Both load ports are independently writable on the same rising edge.
module input_buffer #(
    parameter int N          = 4,
    parameter int K          = N,
    parameter int DATA_WIDTH = 8
) (
    input  logic clk,
    input  logic rst,

    input  logic load_a_en,
    input  logic [((N > 1) ? $clog2(N) : 1)-1:0] load_a_row,
    input  logic [((K > 1) ? $clog2(K) : 1)-1:0] load_a_col,
    input  logic signed [DATA_WIDTH-1:0]          load_a_data,

    input  logic load_b_en,
    input  logic [((K > 1) ? $clog2(K) : 1)-1:0] load_b_row,
    input  logic [((N > 1) ? $clog2(N) : 1)-1:0] load_b_col,
    input  logic signed [DATA_WIDTH-1:0]          load_b_data,

    input  logic [((K > 1) ? $clog2(K) : 1)-1:0] slice_index,
    output logic signed [DATA_WIDTH-1:0]          a_slice [0:N-1],
    output logic signed [DATA_WIDTH-1:0]          b_slice [0:N-1]
);

    logic signed [DATA_WIDTH-1:0] a_tile [0:N-1][0:K-1];
    logic signed [DATA_WIDTH-1:0] b_tile [0:K-1][0:N-1];

    // The external interface guarantees in-range addresses.  Keeping the
    // writes independent deliberately permits one A and one B entry to be
    // loaded on the same edge.
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int row = 0; row < N; row++) begin
                for (int col = 0; col < K; col++) begin
                    a_tile[row][col] <= '0;
                end
            end
            for (int row = 0; row < K; row++) begin
                for (int col = 0; col < N; col++) begin
                    b_tile[row][col] <= '0;
                end
            end
        end else begin
            if (load_a_en)
                a_tile[load_a_row][load_a_col] <= load_a_data;
            if (load_b_en)
                b_tile[load_b_row][load_b_col] <= load_b_data;
        end
    end

    // Combinational reads let the controller select each reduction slice
    // before its source clock edge without adding a buffer-read bubble.
    always_comb begin
        for (int row = 0; row < N; row++) begin
            a_slice[row] = a_tile[row][slice_index];
            b_slice[row] = b_tile[slice_index][row];
        end
    end

endmodule : input_buffer
