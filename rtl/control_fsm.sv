`timescale 1ns/1ps

// Tile-level controller for the Stage 1 output-stationary datapath.
//
// A transaction consists of one synchronous clear edge, K consecutive source
// reduction slices, a conservative mesh-drain interval, one result-capture
// edge, and a one-cycle done notification.  The controller intentionally has
// no ready handshake: start is accepted only while idle and is ignored in all
// other states.
module control_fsm #(
    parameter int N = 4,
    parameter int K = N
) (
    input  logic clk,
    input  logic rst,
    input  logic start,

    output logic array_clear,
    output logic stream_valid,
    output logic [(K > 1 ? $clog2(K) : 1)-1:0] k_index,
    output logic capture_results,
    output logic busy,
    output logic done
);

    // Keep every vector at least one bit wide so N=1 and K=1 are legal.
    localparam int K_INDEX_WIDTH     = (K > 1) ? $clog2(K) : 1;
    localparam int DRAIN_CYCLES      = 2 * ((N > 1) ? (N - 1) : 0) + 1;
    localparam int DRAIN_COUNT_WIDTH = (DRAIN_CYCLES > 1) ? $clog2(DRAIN_CYCLES) : 1;

    localparam logic [31:0] LAST_K_INDEX_INT     = K - 1;
    localparam logic [31:0] LAST_DRAIN_COUNT_INT = DRAIN_CYCLES - 1;
    localparam logic [K_INDEX_WIDTH-1:0] LAST_K_INDEX =
        LAST_K_INDEX_INT[K_INDEX_WIDTH-1:0];
    localparam logic [DRAIN_COUNT_WIDTH-1:0] LAST_DRAIN_COUNT =
        LAST_DRAIN_COUNT_INT[DRAIN_COUNT_WIDTH-1:0];

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_CLEAR,
        ST_STREAM,
        ST_DRAIN,
        ST_CAPTURE,
        ST_DONE
    } state_t;

    state_t state;
    logic [K_INDEX_WIDTH-1:0]     k_count;
    logic [DRAIN_COUNT_WIDTH-1:0] drain_count;

    // The state outputs are Moore-style so every action is held for a full
    // clock period.  k_index is meaningful only while stream_valid is high.
    always_comb begin
        array_clear    = (state == ST_CLEAR);
        stream_valid   = (state == ST_STREAM);
        k_index        = k_count;
        capture_results = (state == ST_CAPTURE);
        busy           = (state != ST_IDLE);
        done           = (state == ST_DONE);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state       <= ST_IDLE;
            k_count     <= '0;
            drain_count <= '0;
        end else begin
            case (state)
                ST_IDLE: begin
                    k_count     <= '0;
                    drain_count <= '0;
                    if (start)
                        state <= ST_CLEAR;
                end

                // array_clear is asserted for this entire state and is
                // therefore sampled on the edge that exits ST_CLEAR.
                ST_CLEAR: begin
                    k_count     <= '0;
                    drain_count <= '0;
                    state       <= ST_STREAM;
                end

                // k_count starts at zero and presents exactly K reduction
                // indices: 0, 1, ..., K-1.  The final slice is consumed on
                // the edge that changes state to ST_DRAIN.
                ST_STREAM: begin
                    if (k_count == LAST_K_INDEX) begin
                        k_count     <= '0;
                        drain_count <= '0;
                        state       <= ST_DRAIN;
                    end else begin
                        k_count <= k_count + 1'b1;
                    end
                end

                // The feeder and mesh need 2*(N-1)+1 quiet cycles after the
                // final source slice.  Result capture begins only after that
                // conservative wait has elapsed.
                ST_DRAIN: begin
                    if (drain_count == LAST_DRAIN_COUNT) begin
                        drain_count <= '0;
                        state       <= ST_CAPTURE;
                    end else begin
                        drain_count <= drain_count + 1'b1;
                    end
                end

                // capture_results is high for this complete cycle; the
                // output buffer samples it on the following edge.
                ST_CAPTURE: begin
                    state <= ST_DONE;
                end

                // done is a one-cycle pulse. busy remains asserted through
                // this notification so a caller cannot mistake ST_DONE for
                // an immediately start-accepting idle state.
                ST_DONE: begin
                    state <= ST_IDLE;
                end

                default: begin
                    state       <= ST_IDLE;
                    k_count     <= '0;
                    drain_count <= '0;
                end
            endcase
        end
    end

    // Invalid tile dimensions are outside the interface contract.  Make a
    // bad elaboration fail clearly in simulation instead of silently creating
    // an unusable counter configuration.
    initial begin
        if (N < 1 || K < 1)
            $fatal(1, "control_fsm requires N and K to be positive (N=%0d, K=%0d)", N, K);
    end

endmodule : control_fsm
