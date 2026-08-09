`timescale 1ns/1ps

// Tile-level systolic accelerator wrapper.
//
// The public load/start/result interface is shared by both supported
// dataflows. DATAFLOW="OS" retains the Stage 1 output-stationary path;
// DATAFLOW="WS" selects the Stage 2 weight-stationary path. The latter maps
// PE rows to reduction indices and therefore requires a square K=N tile.
// See docs/TOP_INTERFACE_CONTRACT.md and docs/WS_STREAMING_CONTRACT.md.
module top #(
    parameter int N            = 4,
    parameter int K            = N,
    parameter int DATA_WIDTH   = 8,
    parameter int ACC_WIDTH    = 32,
    parameter     DATAFLOW     = "OS",
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

    localparam int BUFFER_N_LANES = (N > 1) ? N : 2;
    localparam int BUFFER_K_LANES = (K > 1) ? K : 2;

    wire                         busy_int;
    wire                         done_int;
    wire signed [ACC_WIDTH-1:0]  result_data_int;

    wire [K_ADDR_WIDTH-1:0]      selected_slice_index;
    wire [N_ADDR_WIDTH-1:0]      selected_a_row_index;

    // OS and WS share one input buffer.  Each dataflow consumes a different
    // read view, so the inactive pair is intentionally unused after
    // elaboration.
    /* verilator lint_off UNUSEDSIGNAL */
    wire signed [DATA_WIDTH-1:0] a_slice [0:BUFFER_N_LANES-1];
    wire signed [DATA_WIDTH-1:0] b_slice [0:BUFFER_N_LANES-1];
    wire signed [DATA_WIDTH-1:0] a_row_slice [0:BUFFER_K_LANES-1];
    wire signed [DATA_WIDTH-1:0] b_weights [0:BUFFER_K_LANES-1][0:BUFFER_N_LANES-1];
    /* verilator lint_on UNUSEDSIGNAL */

    assign busy        = busy_int;
    assign done        = done_int;
    assign result_data = result_data_int;

    // Gating writes during execution makes the simple register tile behave as
    // a transaction-local input buffer rather than a live programming port.
    input_buffer #(
        .N         (N),
        .K         (K),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_input_buffer (
        .clk        (clk),
        .rst        (rst),
        .load_a_en  (load_a_en & ~busy_int),
        .load_a_row (load_a_row),
        .load_a_col (load_a_col),
        .load_a_data(load_a_data),
        .load_b_en  (load_b_en & ~busy_int),
        .load_b_row (load_b_row),
        .load_b_col (load_b_col),
        .load_b_data(load_b_data),
        .slice_index(selected_slice_index),
        .a_row_index(selected_a_row_index),
        .a_slice    (a_slice),
        .b_slice    (b_slice),
        .a_row_slice(a_row_slice),
        .b_weights  (b_weights)
    );

    generate
        if (DATAFLOW == "OS") begin : gen_os
            if (N == 1) begin : gen_single_element
                // Icarus cannot elaborate a one-element unpacked-array
                // connection.  A scalar OS PE has the same clear/stream/
                // capture behavior as the one-cell mesh and supports any K.
                wire                         array_clear;
                wire                         stream_valid;
                wire [K_ADDR_WIDTH-1:0]      k_index;
                wire                         capture_results;
                wire signed [ACC_WIDTH-1:0]  acc_single;
                logic signed [ACC_WIDTH-1:0] result_register;

                assign selected_slice_index = k_index;
                assign selected_a_row_index = '0;
                assign result_data_int = ((result_row == '0) && (result_col == '0))
                                       ? result_register : '0;

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
                    .busy           (busy_int),
                    .done           (done_int)
                );

                pe_os #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH (ACC_WIDTH)
                ) u_pe_os (
                    .clk     (clk),
                    .rst     (rst),
                    .clear   (array_clear),
                    .in_valid(stream_valid),
                    .a_in    (a_slice[0]),
                    .w_in    (b_slice[0]),
                    /* verilator lint_off PINCONNECTEMPTY */
                    .out_valid(),
                    .a_out    (),
                    .w_out    (),
                    /* verilator lint_on PINCONNECTEMPTY */
                    .acc      (acc_single)
                );

                always_ff @(posedge clk) begin
                    if (rst)
                        result_register <= '0;
                    else if (capture_results)
                        result_register <= acc_single;
                end
            end else begin : gen_multi_element
            wire                         array_clear;
            wire                         stream_valid;
            wire [K_ADDR_WIDTH-1:0]      k_index;
            wire                         capture_results;

            wire signed [DATA_WIDTH-1:0] a_west [0:N-1];
            wire                         a_west_valid [0:N-1];
            wire signed [DATA_WIDTH-1:0] w_north [0:N-1];
            wire                         w_north_valid [0:N-1];
            wire signed [ACC_WIDTH-1:0]  acc [0:N-1][0:N-1];

            assign selected_slice_index = k_index;
            assign selected_a_row_index = '0;

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
                .busy           (busy_int),
                .done           (done_int)
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
                .result_data(result_data_int)
            );
            end
        end else if (DATAFLOW == "WS") begin : gen_ws
            if (K == N) begin : gen_square_tile
                if (N == 1) begin : gen_single_element
                    // Icarus cannot elaborate a one-element unpacked-array
                    // connection.  This scalar specialization is the same
                    // one-PE WS schedule: clear, preload B[0][0], stream
                    // A[0][0], then retain the tagged bottom result.
                    wire                         array_clear;
                    wire                         weight_load;
                    wire                         stream_valid;
                    wire [N_ADDR_WIDTH-1:0]      stream_tag;
                    wire                         pe_result_valid;
                    wire signed [ACC_WIDTH-1:0]  pe_result;
                    logic signed [ACC_WIDTH-1:0] result_register;

                    assign selected_slice_index = '0;
                    assign selected_a_row_index = stream_tag;
                    // The one-element C tile has one legal address.  Return
                    // zero for an out-of-range encoded address, matching the
                    // documented requirement that callers use valid indices.
                    assign result_data_int = ((result_row == '0) && (result_col == '0))
                                           ? result_register : '0;

                    control_fsm_ws #(
                        .N(N)
                    ) u_control_fsm_ws (
                        .clk         (clk),
                        .rst         (rst),
                        .start       (start),
                        .array_clear (array_clear),
                        .weight_load (weight_load),
                        .stream_valid(stream_valid),
                        .stream_tag  (stream_tag),
                        .busy        (busy_int),
                        .done        (done_int)
                    );

                    pe_ws #(
                        .DATA_WIDTH(DATA_WIDTH),
                        .ACC_WIDTH (ACC_WIDTH),
                        .TAG_WIDTH (N_ADDR_WIDTH)
                    ) u_pe_ws (
                        .clk          (clk),
                        .rst          (rst),
                        .clear        (array_clear),
                        .weight_load  (weight_load),
                        .weight_in    (b_weights[0][0]),
                        .compute_valid(stream_valid),
                        .a_in         (a_row_slice[0]),
                        .psum_in      ({ACC_WIDTH{1'b0}}),
                        .tag_in       (stream_tag),
                        .out_valid    (pe_result_valid),
                        /* verilator lint_off PINCONNECTEMPTY */
                        .a_out        (),
                        .psum_out     (pe_result),
                        .tag_out      ()
                        /* verilator lint_on PINCONNECTEMPTY */
                    );

                    always_ff @(posedge clk) begin
                        if (rst || array_clear)
                            result_register <= '0;
                        else if (pe_result_valid)
                            result_register <= pe_result;
                    end
                end else begin : gen_multi_element
                wire                         array_clear;
                wire                         weight_load;
                wire                         stream_valid;
                wire [N_ADDR_WIDTH-1:0]      stream_tag;

                // Icarus treats a one-element unpacked array at a module
                // boundary specially.  These explicitly N-shaped bridge
                // nets keep the WS-facing array dimensions exact for N=1
                // as well as for the normal square-tile configurations.
                logic signed [DATA_WIDTH-1:0] a_stream [0:N-1];
                logic signed [DATA_WIDTH-1:0] weights [0:N-1][0:N-1];
                wire signed [DATA_WIDTH-1:0] a_west [0:N-1];
                wire                         a_west_valid [0:N-1];
                wire signed [ACC_WIDTH-1:0]  psum_north [0:N-1];
                wire                         psum_north_valid [0:N-1];
                wire [N_ADDR_WIDTH-1:0]      tag_north [0:N-1];
                wire signed [ACC_WIDTH-1:0]  psum_south [0:N-1];
                wire                         psum_south_valid [0:N-1];
                wire [N_ADDR_WIDTH-1:0]      tag_south [0:N-1];

                assign selected_slice_index = '0;
                assign selected_a_row_index = stream_tag;

                always_comb begin
                    for (int k = 0; k < N; k++) begin
                        a_stream[k] = a_row_slice[k];
                        for (int c = 0; c < N; c++) begin
                            weights[k][c] = b_weights[k][c];
                        end
                    end
                end

                control_fsm_ws #(
                    .N(N)
                ) u_control_fsm_ws (
                    .clk         (clk),
                    .rst         (rst),
                    .start       (start),
                    .array_clear (array_clear),
                    .weight_load (weight_load),
                    .stream_valid(stream_valid),
                    .stream_tag  (stream_tag),
                    .busy        (busy_int),
                    .done        (done_int)
                );

                ws_skew_feeder #(
                    .N         (N),
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH (ACC_WIDTH),
                    .TAG_WIDTH (N_ADDR_WIDTH)
                ) u_ws_skew_feeder (
                    .clk             (clk),
                    .rst             (rst),
                    .clear           (array_clear),
                    .stream_valid    (stream_valid),
                    .stream_tag      (stream_tag),
                    .a_stream        (a_stream),
                    .a_west          (a_west),
                    .a_west_valid    (a_west_valid),
                    .psum_north      (psum_north),
                    .psum_north_valid(psum_north_valid),
                    .tag_north       (tag_north)
                );

                systolic_array_ws #(
                    .N         (N),
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH (ACC_WIDTH),
                    .TAG_WIDTH (N_ADDR_WIDTH)
                ) u_systolic_array_ws (
                    .clk             (clk),
                    .rst             (rst),
                    .clear           (array_clear),
                    .weight_load     (weight_load),
                    .weights         (weights),
                    .a_west          (a_west),
                    .a_west_valid    (a_west_valid),
                    .psum_north      (psum_north),
                    .psum_north_valid(psum_north_valid),
                    .tag_north       (tag_north),
                    .psum_south      (psum_south),
                    .psum_south_valid(psum_south_valid),
                    .tag_south       (tag_south)
                );

                output_buffer_ws #(
                    .N        (N),
                    .ACC_WIDTH(ACC_WIDTH),
                    .TAG_WIDTH(N_ADDR_WIDTH)
                ) u_output_buffer_ws (
                    .clk             (clk),
                    .rst             (rst),
                    .clear           (array_clear),
                    .result_valid    (psum_south_valid),
                    .result_tag      (tag_south),
                    .result_data     (psum_south),
                    .result_row      (result_row),
                    .result_col      (result_col),
                    .result_read_data(result_data_int)
                );
                end
            end else begin : gen_invalid_ws_dimensions
                // This mapping gives one PE row to each reduction index, so
                // rectangular reduction dimensions need a separate tiling
                // policy rather than a silent, incorrect elaboration.
                initial $fatal(1,
                    "top DATAFLOW=WS requires K == N (N=%0d, K=%0d)", N, K);
                assign selected_slice_index = '0;
                assign selected_a_row_index = '0;
                assign busy_int             = 1'b0;
                assign done_int             = 1'b0;
                assign result_data_int      = '0;
            end
        end else begin : gen_invalid_dataflow
            initial $fatal(1,
                "top DATAFLOW must be \"OS\" or \"WS\" (got %s)", DATAFLOW);
            assign selected_slice_index = '0;
            assign selected_a_row_index = '0;
            assign busy_int             = 1'b0;
            assign done_int             = 1'b0;
            assign result_data_int      = '0;
        end
    endgenerate

endmodule : top
