`timescale 1ns/1ps

// Fixed-configuration macro wrapper for the Stage 4 nominal hardening point.
//
// The verification-facing `top` remains parameterized.  OpenLane hardens this
// explicit N=8, K=8 output-stationary instance so the physical-design result
// has a stable module name and stable scalar I/O widths.
module top_hardened (
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         start,

    input  logic                         load_a_en,
    input  logic [2:0]                   load_a_row,
    input  logic [2:0]                   load_a_col,
    input  logic signed [7:0]            load_a_data,

    input  logic                         load_b_en,
    input  logic [2:0]                   load_b_row,
    input  logic [2:0]                   load_b_col,
    input  logic signed [7:0]            load_b_data,

    output wire                         busy,
    output wire                         done,

    input  logic [2:0]                   result_row,
    input  logic [2:0]                   result_col,
    output wire signed [31:0]            result_data
);

    top #(
        .N         (8),
        .K         (8),
        .DATA_WIDTH(8),
        .ACC_WIDTH (32),
        .DATAFLOW  ("OS")
    ) u_top (
        .clk        (clk),
        .rst        (rst),
        .start      (start),
        .load_a_en  (load_a_en),
        .load_a_row (load_a_row),
        .load_a_col (load_a_col),
        .load_a_data(load_a_data),
        .load_b_en  (load_b_en),
        .load_b_row (load_b_row),
        .load_b_col (load_b_col),
        .load_b_data(load_b_data),
        .busy       (busy),
        .done        (done),
        .result_row (result_row),
        .result_col (result_col),
        .result_data(result_data)
    );

endmodule : top_hardened
