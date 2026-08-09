`timescale 1ns/1ps

// Tile-level controller for the Stage 2 weight-stationary datapath.
//
// WS clears the mesh/result tile, preloads stationary B weights, streams N
// output rows of A, and then waits for tagged partial sums to drain from the
// bottom edge. Results are written during drain, so no capture state is needed.
module control_fsm_ws #(
    parameter int N = 4
) (
    input  logic clk,
    input  logic rst,
    input  logic start,

    output logic array_clear,
    output logic weight_load,
    output logic stream_valid,
    output logic [((N > 1) ? $clog2(N) : 1)-1:0] stream_tag,
    output logic busy,
    output logic done
);

    localparam int TAG_WIDTH         = (N > 1) ? $clog2(N) : 1;
    localparam int DRAIN_CYCLES      = 3 * ((N > 1) ? (N - 1) : 0) + 1;
    localparam int DRAIN_COUNT_WIDTH = (DRAIN_CYCLES > 1) ? $clog2(DRAIN_CYCLES) : 1;

    localparam logic [31:0] LAST_STREAM_TAG_INT  = N - 1;
    localparam logic [31:0] LAST_DRAIN_COUNT_INT = DRAIN_CYCLES - 1;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_CLEAR,
        ST_PRELOAD,
        ST_STREAM,
        ST_DRAIN,
        ST_DONE
    } state_t;

    state_t state;
    logic [TAG_WIDTH-1:0] stream_count;
    logic [DRAIN_COUNT_WIDTH-1:0] drain_count;

    always_comb begin
        array_clear  = (state == ST_CLEAR);
        weight_load  = (state == ST_PRELOAD);
        stream_valid = (state == ST_STREAM);
        stream_tag   = stream_count;
        busy         = (state != ST_IDLE);
        done         = (state == ST_DONE);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state        <= ST_IDLE;
            stream_count <= '0;
            drain_count  <= '0;
        end else begin
            case (state)
                ST_IDLE: begin
                    stream_count <= '0;
                    drain_count  <= '0;
                    if (start)
                        state <= ST_CLEAR;
                end

                ST_CLEAR: begin
                    stream_count <= '0;
                    drain_count  <= '0;
                    state        <= ST_PRELOAD;
                end

                ST_PRELOAD: begin
                    stream_count <= '0;
                    state        <= ST_STREAM;
                end

                ST_STREAM: begin
                    if (stream_count == LAST_STREAM_TAG_INT[TAG_WIDTH-1:0]) begin
                        stream_count <= '0;
                        drain_count  <= '0;
                        state        <= ST_DRAIN;
                    end else begin
                        stream_count <= stream_count + 1'b1;
                    end
                end

                ST_DRAIN: begin
                    if (drain_count == LAST_DRAIN_COUNT_INT[DRAIN_COUNT_WIDTH-1:0]) begin
                        drain_count <= '0;
                        state       <= ST_DONE;
                    end else begin
                        drain_count <= drain_count + 1'b1;
                    end
                end

                ST_DONE: begin
                    state <= ST_IDLE;
                end

                default: begin
                    state        <= ST_IDLE;
                    stream_count <= '0;
                    drain_count  <= '0;
                end
            endcase
        end
    end

    initial begin
        if (N < 1)
            $fatal(1, "control_fsm_ws requires N to be positive (N=%0d)", N);
    end

endmodule : control_fsm_ws
