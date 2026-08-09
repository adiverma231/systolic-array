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
    input  logic [((N > 1) ? $clog2(N) : 1)-1:0] a_row_index,
    output logic signed [DATA_WIDTH-1:0]          a_slice [0:((N > 1) ? N : 2)-1],
    output logic signed [DATA_WIDTH-1:0]          b_slice [0:((N > 1) ? N : 2)-1],
    output logic signed [DATA_WIDTH-1:0]          a_row_slice [0:((K > 1) ? K : 2)-1],
    output logic signed [DATA_WIDTH-1:0]          b_weights [0:((K > 1) ? K : 2)-1][0:((N > 1) ? N : 2)-1]
);

    // Icarus Verilog does not accept a one-element unpacked array at every
    // module boundary.  Keep public tile semantics at N/K entries, while
    // exposing a harmless spare lane for the singleton configuration.
    localparam int N_LANES = (N > 1) ? N : 2;
    localparam int K_LANES = (K > 1) ? K : 2;

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

    // Combinational reads let either dataflow select its source values before
    // a source clock edge without adding a buffer-read bubble. OS consumes an
    // A column plus B row; WS consumes an A row and the full stationary B
    // tile during its preload phase.
    always_comb begin
        for (int row = 0; row < N_LANES; row++) begin
            a_slice[row] = '0;
            b_slice[row] = '0;
        end
        for (int col = 0; col < K_LANES; col++) begin
            a_row_slice[col] = '0;
            for (int row = 0; row < N_LANES; row++) begin
                b_weights[col][row] = '0;
            end
        end

        for (int row = 0; row < N; row++) begin
            a_slice[row] = a_tile[row][slice_index];
            b_slice[row] = b_tile[slice_index][row];
        end

        for (int col = 0; col < K; col++) begin
            a_row_slice[col] = a_tile[a_row_index][col];
        end

        for (int k = 0; k < K; k++) begin
            for (int col = 0; col < N; col++) begin
                b_weights[k][col] = b_tile[k][col];
            end
        end
    end

endmodule : input_buffer
