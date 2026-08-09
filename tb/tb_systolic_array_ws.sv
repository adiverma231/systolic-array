`timescale 1ns/1ps

// Stage 2 integration test for the direct weight-stationary datapath.
//
// This test intentionally stops below the public tile wrapper.  It composes
// the WS feeder, mesh, and streamed-result buffer exactly as the Stage 2
// contract defines: clear, one-edge B preload, N tagged A-row source tokens,
// then a conservative drain.  Results are checked through the output buffer's
// ordinary row/column read interface against a local signed int8 x int8 ->
// int32 golden model.
module tb_systolic_array_ws #(
    parameter int N            = 4,
    parameter int DATA_WIDTH   = 8,
    parameter int ACC_WIDTH    = 32,
    parameter int RANDOM_TILES = 3
);

    localparam int PRODUCT_WIDTH = 2 * DATA_WIDTH;
    localparam int TAG_WIDTH     = (N > 1) ? $clog2(N) : 1;
    localparam int ADDR_WIDTH    = (N > 1) ? $clog2(N) : 1;
    // One cycle beyond the contract's minimum leaves time for the final
    // bottom-edge result to be captured by output_buffer_ws.
    localparam int DRAIN_CYCLES  = 3 * (N - 1) + 2;

    logic clk;
    logic rst;
    logic clear;
    logic weight_load;
    logic stream_valid;
    logic [TAG_WIDTH-1:0] stream_tag;

    logic signed [DATA_WIDTH-1:0] a_stream [0:N-1];
    logic signed [DATA_WIDTH-1:0] weights  [0:N-1][0:N-1];

    wire signed [DATA_WIDTH-1:0] a_west       [0:N-1];
    wire                         a_west_valid [0:N-1];
    wire signed [ACC_WIDTH-1:0] psum_north       [0:N-1];
    wire                        psum_north_valid [0:N-1];
    wire [TAG_WIDTH-1:0]        tag_north        [0:N-1];

    wire signed [ACC_WIDTH-1:0] psum_south       [0:N-1];
    wire                        psum_south_valid [0:N-1];
    wire [TAG_WIDTH-1:0]        tag_south        [0:N-1];

    logic [ADDR_WIDTH-1:0] result_row;
    logic [ADDR_WIDTH-1:0] result_col;
    logic signed [ACC_WIDTH-1:0] result_read_data;

    logic signed [DATA_WIDTH-1:0] a_matrix [0:N-1][0:N-1];
    logic signed [ACC_WIDTH-1:0]  golden   [0:N-1][0:N-1];

    int checks;
    int tiles_run;

    ws_skew_feeder #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH),
        .TAG_WIDTH (TAG_WIDTH)
    ) feeder (
        .clk             (clk),
        .rst             (rst),
        .clear           (clear),
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
        .TAG_WIDTH (TAG_WIDTH)
    ) mesh (
        .clk             (clk),
        .rst             (rst),
        .clear           (clear),
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
        .TAG_WIDTH(TAG_WIDTH)
    ) result_buffer (
        .clk             (clk),
        .rst             (rst),
        .clear           (clear),
        .result_valid    (psum_south_valid),
        .result_tag      (tag_south),
        .result_data     (psum_south),
        .result_row      (result_row),
        .result_col      (result_col),
        .result_read_data(result_read_data)
    );

    always #5 clk = ~clk;

    function automatic logic signed [DATA_WIDTH-1:0] directed_a(input int index);
        begin
            // Includes zeros, both signed extremes, signs, and values that
            // give nontrivial partial sums through all mesh rows.
            case (index % 10)
                0:       directed_a = '0;
                1:       directed_a = 1;
                2:       directed_a = -1;
                3:       directed_a = 127;
                4:       directed_a = -128;
                5:       directed_a = 64;
                6:       directed_a = -64;
                7:       directed_a = 13;
                8:       directed_a = -37;
                default: directed_a = 91;
            endcase
        end
    endfunction

    function automatic logic signed [DATA_WIDTH-1:0] directed_b(input int index);
        begin
            case (index % 10)
                0:       directed_b = -128;
                1:       directed_b = 127;
                2:       directed_b = '0;
                3:       directed_b = 1;
                4:       directed_b = -1;
                5:       directed_b = -64;
                6:       directed_b = 64;
                7:       directed_b = -17;
                8:       directed_b = 39;
                default: directed_b = -91;
            endcase
        end
    endfunction

    task automatic expect_acc(
        input string signal_name,
        input logic signed [ACC_WIDTH-1:0] actual,
        input logic signed [ACC_WIDTH-1:0] expected
    );
        begin
            checks++;
            if (actual !== expected) begin
                $error("%s mismatch at %0t: got %0d (0x%h), expected %0d (0x%h)",
                       signal_name, $time, actual, actual, expected, expected);
                $fatal(1);
            end
        end
    endtask

    task automatic expect_valid(
        input string signal_name,
        input logic actual,
        input logic expected
    );
        begin
            checks++;
            if (actual !== expected) begin
                $error("%s mismatch at %0t: got %b, expected %b",
                       signal_name, $time, actual, expected);
                $fatal(1);
            end
        end
    endtask

    task automatic expect_tag(
        input string signal_name,
        input logic [TAG_WIDTH-1:0] actual,
        input logic [TAG_WIDTH-1:0] expected
    );
        begin
            checks++;
            if (actual !== expected) begin
                $error("%s mismatch at %0t: got 0x%h, expected 0x%h",
                       signal_name, $time, actual, expected);
                $fatal(1);
            end
        end
    endtask

    task automatic drive_idle;
        int lane;
        begin
            stream_valid = 1'b0;
            stream_tag   = '0;
            for (lane = 0; lane < N; lane++)
                a_stream[lane] = '0;
        end
    endtask

    task automatic load_zero_tile;
        int row;
        int col;
        begin
            for (row = 0; row < N; row++) begin
                for (col = 0; col < N; col++) begin
                    a_matrix[row][col] = '0;
                    weights[row][col]  = '0;
                end
            end
        end
    endtask

    task automatic load_directed_tile;
        int row;
        int col;
        begin
            for (row = 0; row < N; row++) begin
                for (col = 0; col < N; col++) begin
                    a_matrix[row][col] = directed_a(row * N + col);
                    weights[row][col]  = directed_b(row * N + col + 3);
                end
            end
        end
    endtask

    task automatic load_random_tile(input int unsigned seed);
        int row;
        int col;
        int unsigned state;
        begin
            // A local xorshift generator is deterministic in Icarus and
            // both supported simulators, unlike depending on $urandom's seed.
            state = seed;
            for (row = 0; row < N; row++) begin
                for (col = 0; col < N; col++) begin
                    state = state ^ (state << 13);
                    state = state ^ (state >> 17);
                    state = state ^ (state << 5);
                    a_matrix[row][col] = state[DATA_WIDTH-1:0];
                end
            end
            for (row = 0; row < N; row++) begin
                for (col = 0; col < N; col++) begin
                    state = state ^ (state << 13);
                    state = state ^ (state >> 17);
                    state = state ^ (state << 5);
                    weights[row][col] = state[DATA_WIDTH-1:0];
                end
            end
        end
    endtask

    task automatic build_golden;
        int row;
        int col;
        int k;
        logic signed [PRODUCT_WIDTH-1:0] product;
        logic signed [ACC_WIDTH-1:0] sum;
        begin
            for (row = 0; row < N; row++) begin
                for (col = 0; col < N; col++) begin
                    sum = '0;
                    for (k = 0; k < N; k++) begin
                        product = $signed(a_matrix[row][k]) * $signed(weights[k][col]);
                        sum = sum + {
                            {(ACC_WIDTH - PRODUCT_WIDTH){product[PRODUCT_WIDTH-1]}}, product
                        };
                    end
                    golden[row][col] = sum;
                end
            end
        end
    endtask

    task automatic check_result_tile(input string tile_name);
        int row;
        int col;
        begin
            for (row = 0; row < N; row++) begin
                for (col = 0; col < N; col++) begin
                    result_row = ADDR_WIDTH'(row);
                    result_col = ADDR_WIDTH'(col);
                    #1;
                    expect_acc($sformatf("%s C[%0d][%0d]", tile_name, row, col),
                               result_read_data, golden[row][col]);
                end
            end
        end
    endtask

    task automatic check_result_buffer_zero(input string check_name);
        int row;
        int col;
        begin
            for (row = 0; row < N; row++) begin
                for (col = 0; col < N; col++) begin
                    result_row = ADDR_WIDTH'(row);
                    result_col = ADDR_WIDTH'(col);
                    #1;
                    expect_acc($sformatf("%s C[%0d][%0d]", check_name, row, col),
                               result_read_data, '0);
                end
            end
        end
    endtask

    task automatic check_mesh_bubble(input string check_name);
        int col;
        begin
            for (col = 0; col < N; col++) begin
                expect_valid($sformatf("%s south_valid[%0d]", check_name, col),
                             psum_south_valid[col], 1'b0);
                expect_acc($sformatf("%s south_psum[%0d]", check_name, col),
                           psum_south[col], '0);
                expect_tag($sformatf("%s south_tag[%0d]", check_name, col),
                           tag_south[col], '0);
            end
        end
    endtask

    task automatic clear_datapath;
        begin
            // Hold clear through an edge and keep all other commands idle so
            // no preload can occur in the first cycle after clear releases.
            @(negedge clk);
            clear       = 1'b1;
            weight_load = 1'b0;
            drive_idle();

            @(posedge clk);
            #1;
            check_mesh_bubble("clear");
            check_result_buffer_zero("clear");

            @(negedge clk);
            clear       = 1'b0;
            weight_load = 1'b0;
            drive_idle();
        end
    endtask

    task automatic preload_weights;
        begin
            @(negedge clk);
            clear       = 1'b0;
            weight_load = 1'b1;
            drive_idle();

            @(posedge clk);
            #1;
            // Weight load is a dedicated bubble, not a compute stream.
            check_mesh_bubble("preload");

            @(negedge clk);
            weight_load = 1'b0;
            drive_idle();
        end
    endtask

    task automatic stream_activation_rows;
        int row;
        int k;
        begin
            for (row = 0; row < N; row++) begin
                @(negedge clk);
                weight_load = 1'b0;
                stream_valid = 1'b1;
                stream_tag   = TAG_WIDTH'(row);
                for (k = 0; k < N; k++)
                    a_stream[k] = a_matrix[row][k];
                @(posedge clk);
            end

            @(negedge clk);
            weight_load = 1'b0;
            drive_idle();
        end
    endtask

    task automatic run_current_tile(input string tile_name);
        begin
            build_golden();
            clear_datapath();
            preload_weights();
            stream_activation_rows();

            // The contract requires at least 3*(N-1)+1 quiet drain cycles.
            // The local constant has one additional capture-observation edge.
            repeat (DRAIN_CYCLES) @(posedge clk);
            #1;
            check_result_tile(tile_name);
            tiles_run++;
        end
    endtask

    initial begin : test_sequence
        int random_index;

        if (N < 1 || DATA_WIDTH < 1 || ACC_WIDTH < PRODUCT_WIDTH) begin
            $fatal(1,
                   "invalid test parameters: N=%0d DATA_WIDTH=%0d ACC_WIDTH=%0d",
                   N, DATA_WIDTH, ACC_WIDTH);
        end

        clk         = 1'b0;
        rst         = 1'b1;
        clear       = 1'b0;
        weight_load = 1'b0;
        result_row  = '0;
        result_col  = '0;
        checks      = 0;
        tiles_run   = 0;
        drive_idle();
        load_zero_tile();

        // Reset establishes all three direct datapath blocks.  Check both
        // streamed mesh outputs and addressed result storage before use.
        repeat (2) @(posedge clk);
        #1;
        check_mesh_bubble("reset");
        check_result_buffer_zero("reset");

        @(negedge clk);
        rst = 1'b0;

        load_zero_tile();
        run_current_tile("all-zero tile");

        load_directed_tile();
        run_current_tile("directed signed/extreme tile");

        for (random_index = 0; random_index < RANDOM_TILES; random_index++) begin
            load_random_tile(32'h7d30_9a51 + random_index);
            run_current_tile($sformatf("random tile %0d", random_index));
        end

        $display("PASS: tb_systolic_array_ws completed %0d checks across %0d tiles (N=%0d).",
                 checks, tiles_run, N);
        $finish;
    end

endmodule : tb_systolic_array_ws
