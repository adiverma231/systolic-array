`timescale 1ns/1ps

// Source-to-edge skew network for the output-stationary mesh.
//
// A source presents one A column and one B row per valid reduction cycle.
// The activation for row r and weight for column c are delayed by r and c
// clock edges, respectively.  Index zero is deliberately a combinational
// bypass: it is available to the mesh on the same source edge.
module skew_feeder #(
    parameter int N          = 4,
    parameter int DATA_WIDTH = 8
) (
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         clear,
    input  logic signed [DATA_WIDTH-1:0] a_stream [0:N-1],
    input  logic signed [DATA_WIDTH-1:0] b_stream [0:N-1],
    input  logic                         stream_valid,
    output wire signed [DATA_WIDTH-1:0]  a_west [0:N-1],
    output wire                          a_west_valid [0:N-1],
    output wire signed [DATA_WIDTH-1:0]  w_north [0:N-1],
    output wire                          w_north_valid [0:N-1]
);

    // Keep one storage entry even for N=1 so that the module remains a legal
    // elaboration; row/column zero never reads this storage.
    localparam int MAX_DELAY = (N > 1) ? (N - 1) : 1;

    logic signed [DATA_WIDTH-1:0] a_delay [0:N-1][0:MAX_DELAY-1];
    logic                         a_delay_valid [0:N-1][0:MAX_DELAY-1];
    logic signed [DATA_WIDTH-1:0] b_delay [0:N-1][0:MAX_DELAY-1];
    logic                         b_delay_valid [0:N-1][0:MAX_DELAY-1];

    // Each stage is a one-cycle registered delay.  Pipelines beyond a row or
    // column's required delay are harmless unused state; retaining a regular
    // rectangular declaration avoids zero-length dimensions for N=1.
    always_ff @(posedge clk) begin
        if (rst || clear) begin
            for (int index = 0; index < N; index++) begin
                for (int stage = 0; stage < MAX_DELAY; stage++) begin
                    a_delay[index][stage]       <= '0;
                    a_delay_valid[index][stage] <= 1'b0;
                    b_delay[index][stage]       <= '0;
                    b_delay_valid[index][stage] <= 1'b0;
                end
            end
        end else begin
            for (int index = 0; index < N; index++) begin
                a_delay[index][0]       <= a_stream[index];
                a_delay_valid[index][0] <= stream_valid;
                b_delay[index][0]       <= b_stream[index];
                b_delay_valid[index][0] <= stream_valid;

                for (int stage = 1; stage < MAX_DELAY; stage++) begin
                    a_delay[index][stage]       <= a_delay[index][stage - 1];
                    a_delay_valid[index][stage] <= a_delay_valid[index][stage - 1];
                    b_delay[index][stage]       <= b_delay[index][stage - 1];
                    b_delay_valid[index][stage] <= b_delay_valid[index][stage - 1];
                end
            end
        end
    end

    // Row zero and column zero are combinational bypasses. All other edge
    // lanes select the final register of their index-specific delay line.
    // Generate-time continuous assignments avoid simulator-dependent
    // sensitivity handling for variable-index unpacked-array selects.
    genvar lane;
    generate
        for (lane = 0; lane < N; lane = lane + 1) begin : gen_edge_lanes
            if (lane == 0) begin : gen_bypass
                assign a_west[lane]       = a_stream[lane];
                assign a_west_valid[lane] = stream_valid;
                assign w_north[lane]      = b_stream[lane];
                assign w_north_valid[lane] = stream_valid;
            end else begin : gen_delay_select
                assign a_west[lane]       = a_delay[lane][lane - 1];
                assign a_west_valid[lane] = a_delay_valid[lane][lane - 1];
                assign w_north[lane]      = b_delay[lane][lane - 1];
                assign w_north_valid[lane] = b_delay_valid[lane][lane - 1];
            end
        end
    endgenerate

endmodule : skew_feeder
