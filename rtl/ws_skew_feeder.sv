`timescale 1ns/1ps

// Source-to-edge skew network for the weight-stationary mesh.
//
// A source cycle represents one output row m: a_stream[k] is A[m][k] and
// stream_tag is m.  Activation lane k is delayed by k edges before entering
// PE row k from the west.  In parallel, a zero partial sum and the row tag
// are delayed by c edges before entering PE column c from the north.  Thus
// PE [k][c] receives the matching activation and partial-sum token together.
module ws_skew_feeder #(
    parameter int N          = 4,
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = 32,
    parameter int TAG_WIDTH  = (N > 1) ? $clog2(N) : 1
) (
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         clear,
    input  logic                         stream_valid,
    input  logic [TAG_WIDTH-1:0]         stream_tag,
    input  logic signed [DATA_WIDTH-1:0] a_stream [0:N-1],

    output wire signed [DATA_WIDTH-1:0]  a_west [0:N-1],
    output wire                          a_west_valid [0:N-1],
    output wire signed [ACC_WIDTH-1:0]   psum_north [0:N-1],
    output wire                          psum_north_valid [0:N-1],
    output wire [TAG_WIDTH-1:0]          tag_north [0:N-1]
);

    // Keep one storage entry for N=1.  Row/column zero uses a combinational
    // bypass, so that entry is never selected in that configuration.
    localparam int MAX_DELAY = (N > 1) ? (N - 1) : 1;

    logic signed [DATA_WIDTH-1:0] a_delay [0:N-1][0:MAX_DELAY-1];
    logic                         a_delay_valid [0:N-1][0:MAX_DELAY-1];
    logic [TAG_WIDTH-1:0]         tag_delay [0:N-1][0:MAX_DELAY-1];
    logic                         tag_delay_valid [0:N-1][0:MAX_DELAY-1];

    // Each registered stage adds one full clock-edge delay.  Keeping a
    // rectangular storage shape avoids zero-length unpacked dimensions while
    // leaving unneeded tail stages harmless.
    always_ff @(posedge clk) begin
        if (rst || clear) begin
            for (int lane = 0; lane < N; lane++) begin
                for (int stage = 0; stage < MAX_DELAY; stage++) begin
                    a_delay[lane][stage]       <= '0;
                    a_delay_valid[lane][stage] <= 1'b0;
                    tag_delay[lane][stage]       <= '0;
                    tag_delay_valid[lane][stage] <= 1'b0;
                end
            end
        end else begin
            for (int lane = 0; lane < N; lane++) begin
                a_delay[lane][0]       <= a_stream[lane];
                a_delay_valid[lane][0] <= stream_valid;
                tag_delay[lane][0]       <= stream_tag;
                tag_delay_valid[lane][0] <= stream_valid;

                for (int stage = 1; stage < MAX_DELAY; stage++) begin
                    a_delay[lane][stage]       <= a_delay[lane][stage - 1];
                    a_delay_valid[lane][stage] <= a_delay_valid[lane][stage - 1];
                    tag_delay[lane][stage]       <= tag_delay[lane][stage - 1];
                    tag_delay_valid[lane][stage] <= tag_delay_valid[lane][stage - 1];
                end
            end
        end
    end

    // Index zero bypasses the delay storage.  For c > 0 the north boundary
    // carries a signed-zero partial sum, with validity and tag selected from
    // the same c-cycle token pipeline.
    genvar lane;
    generate
        for (lane = 0; lane < N; lane = lane + 1) begin : gen_edge_lanes
            assign psum_north[lane] = '0;

            if (lane == 0) begin : gen_bypass
                assign a_west[lane]          = a_stream[lane];
                assign a_west_valid[lane]    = stream_valid;
                assign psum_north_valid[lane] = stream_valid;
                assign tag_north[lane]       = stream_tag;
            end else begin : gen_delay_select
                assign a_west[lane]          = a_delay[lane][lane - 1];
                assign a_west_valid[lane]    = a_delay_valid[lane][lane - 1];
                assign psum_north_valid[lane] = tag_delay_valid[lane][lane - 1];
                assign tag_north[lane]       = tag_delay[lane][lane - 1];
            end
        end
    endgenerate

    initial begin
        if (N < 1 || DATA_WIDTH < 1 || ACC_WIDTH < 1 || TAG_WIDTH < 1)
            $fatal(1,
                "ws_skew_feeder parameters must be positive (N=%0d, DATA_WIDTH=%0d, ACC_WIDTH=%0d, TAG_WIDTH=%0d)",
                N, DATA_WIDTH, ACC_WIDTH, TAG_WIDTH);
    end

endmodule : ws_skew_feeder
