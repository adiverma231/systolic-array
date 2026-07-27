`timescale 1ns/1ps

// Stage 1 tile-level output-stationary accelerator wrapper.
//
// The wrapper accepts register writes for one A[N,K] and B[K,N] tile, runs a
// complete OS systolic computation after start, and exposes a stable,
// registered C[N,N] result tile. See docs/TOP_INTERFACE_CONTRACT.md.
module top #(
    parameter int N            = 4,
    parameter int K            = N,
    parameter int DATA_WIDTH   = 8,
    parameter int ACC_WIDTH    = 32,
    parameter int N_ADDR_WIDTH = (N > 1) ? $clog2(N) : 1,
    parameter int K_ADDR_WIDTH = (K > 1) ? $clog2(K) : 1
) (
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         start,

    input  logic                         load_a_en,
    input  logic [N_ADDR_WIDTH-1:0]      load_a_row,
    input  logic [K_ADDR_WIDTH-1:0]      load_a_col,
    input  logic signed [DATA_WIDTH-1:0] load_a_data,

    input  logic                         load_b_en,
    input  logic [K_ADDR_WIDTH-1:0]      load_b_row,
    input  logic [N_ADDR_WIDTH-1:0]      load_b_col,
    input  logic signed [DATA_WIDTH-1:0] load_b_data,

    output wire                          busy,
    output wire                          done,

    input  logic [N_ADDR_WIDTH-1:0]      result_row,
    input  logic [N_ADDR_WIDTH-1:0]      result_col,
    output wire signed [ACC_WIDTH-1:0]   result_data
);

    wire                         array_clear;
    wire                         stream_valid;
    wire [K_ADDR_WIDTH-1:0]      k_index;
    wire                         capture_results;

    wire signed [DATA_WIDTH-1:0] a_slice [0:N-1];
    wire signed [DATA_WIDTH-1:0] b_slice [0:N-1];

    wire signed [DATA_WIDTH-1:0] a_west [0:N-1];
    wire                         a_west_valid [0:N-1];
    wire signed [DATA_WIDTH-1:0] w_north [0:N-1];
    wire                         w_north_valid [0:N-1];
    wire signed [ACC_WIDTH-1:0]  acc [0:N-1][0:N-1];

    control_fsm #(
        .N(N),
        .K(K)
    ) u_control_fsm (
        .clk            (clk),
        .rst            (rst),
        .start          (start),
        .array_clear    (array_clear),
        .stream_valid   (stream_valid),
        .k_index        (k_index),
        .capture_results(capture_results),
        .busy           (busy),
        .done           (done)
    );

    // Gating writes during execution makes the simple register tile behave as
    // a transaction-local input buffer rather than a live programming port.
    input_buffer #(
        .N         (N),
        .K         (K),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_input_buffer (
        .clk        (clk),
        .rst        (rst),
        .load_a_en  (load_a_en & ~busy),
        .load_a_row (load_a_row),
        .load_a_col (load_a_col),
        .load_a_data(load_a_data),
        .load_b_en  (load_b_en & ~busy),
        .load_b_row (load_b_row),
        .load_b_col (load_b_col),
        .load_b_data(load_b_data),
        .slice_index(k_index),
        .a_slice    (a_slice),
        .b_slice    (b_slice)
    );

    skew_feeder #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_skew_feeder (
        .clk         (clk),
        .rst         (rst),
        .clear       (array_clear),
        .stream_valid(stream_valid),
        .a_stream    (a_slice),
        .b_stream    (b_slice),
        .a_west      (a_west),
        .a_west_valid(a_west_valid),
        .w_north     (w_north),
        .w_north_valid(w_north_valid)
    );

    systolic_array #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) u_systolic_array (
        .clk         (clk),
        .rst         (rst),
        .clear       (array_clear),
        .a_west      (a_west),
        .a_west_valid(a_west_valid),
        .w_north     (w_north),
        .w_north_valid(w_north_valid),
        .acc         (acc)
    );

    output_buffer #(
        .N        (N),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_output_buffer (
        .clk        (clk),
        .rst        (rst),
        .capture_en (capture_results),
        .acc_in     (acc),
        .result_row (result_row),
        .result_col (result_col),
        .result_data(result_data)
    );

endmodule : top
