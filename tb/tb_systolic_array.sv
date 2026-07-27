`timescale 1ns/1ps

// Stage 1 end-to-end test for the output-stationary mesh.
//
// A source reduction slice is driven on every valid cycle as specified in
// docs/OS_STREAMING_CONTRACT.md:
//   a_stream[r] = A[r][k]
//   b_stream[c] = B[k][c]
// The skew_feeder must align those values at the mesh, and each mesh
// accumulator must equal the local signed int8 x int8 -> int32 golden model.
//
// N and K are elaboration parameters so this test can exercise both square
// and non-square reduction tiles.  The project defaults are N=4 and K=N.
module tb_systolic_array #(
    parameter int N            = 4,
    parameter int K            = N,
    parameter int DATA_WIDTH   = 8,
    parameter int ACC_WIDTH    = 32,
    parameter int RANDOM_TILES = 3
);

    localparam int PRODUCT_WIDTH = 2 * DATA_WIDTH;
    localparam int DRAIN_CYCLES  = 2 * (N - 1) + 1;

    logic clk;
    logic rst;
    logic clear;
    logic stream_valid;

    logic signed [DATA_WIDTH-1:0] a_stream [0:N-1];
    logic signed [DATA_WIDTH-1:0] b_stream [0:N-1];

    wire signed [DATA_WIDTH-1:0]  a_west [0:N-1];
    wire                          a_west_valid [0:N-1];
    wire signed [DATA_WIDTH-1:0]  w_north [0:N-1];
    wire                          w_north_valid [0:N-1];
    wire signed [ACC_WIDTH-1:0]  acc [0:N-1][0:N-1];

    logic signed [DATA_WIDTH-1:0] a_matrix [0:N-1][0:K-1];
    logic signed [DATA_WIDTH-1:0] b_matrix [0:K-1][0:N-1];
    logic signed [ACC_WIDTH-1:0]  golden   [0:N-1][0:N-1];

    int checks;
    int tiles_run;

    skew_feeder #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH)
    ) feeder (
        .clk         (clk),
        .rst         (rst),
        .clear       (clear),
        .stream_valid(stream_valid),
        .a_stream    (a_stream),
        .b_stream    (b_stream),
        .a_west      (a_west),
        .a_west_valid(a_west_valid),
        .w_north     (w_north),
        .w_north_valid(w_north_valid)
    );

    systolic_array #(
        .N         (N),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) dut (
        .clk         (clk),
        .rst         (rst),
        .clear       (clear),
        .a_west      (a_west),
        .a_west_valid(a_west_valid),
        .w_north     (w_north),
        .w_north_valid(w_north_valid),
        .acc         (acc)
    );

    always #5 clk = ~clk;

    function automatic logic signed [DATA_WIDTH-1:0] directed_a(input int index);
        begin
            // Covers zero, positive/negative values, and both int8 extrema.
            case (index % 8)
                0:       directed_a = '0;
                1:       directed_a = 1;
                2:       directed_a = -1;
                3:       directed_a = 127;
                4:       directed_a = -128;
                5:       directed_a = 64;
                6:       directed_a = -64;
                default: directed_a = 13;
            endcase
        end
    endfunction

    function automatic logic signed [DATA_WIDTH-1:0] directed_b(input int index);
        begin
            case (index % 8)
                0:       directed_b = '0;
                1:       directed_b = -1;
                2:       directed_b = 1;
                3:       directed_b = -128;
                4:       directed_b = 127;
                5:       directed_b = -64;
                6:       directed_b = 64;
                default: directed_b = -7;
            endcase
        end
    endfunction

    task automatic drive_idle;
        int r;
        begin
            stream_valid = 1'b0;
            for (r = 0; r < N; r++) begin
                a_stream[r] = '0;
                b_stream[r] = '0;
            end
        end
    endtask

    task automatic load_zero_tile;
        int r;
        int c;
        int k;
        begin
            for (r = 0; r < N; r++) begin
                for (k = 0; k < K; k++)
                    a_matrix[r][k] = '0;
            end
            for (k = 0; k < K; k++) begin
                for (c = 0; c < N; c++)
                    b_matrix[k][c] = '0;
            end
        end
    endtask

    task automatic load_directed_tile;
        int r;
        int c;
        int k;
        begin
            for (r = 0; r < N; r++) begin
                for (k = 0; k < K; k++)
                    a_matrix[r][k] = directed_a(r * K + k);
            end
            for (k = 0; k < K; k++) begin
                for (c = 0; c < N; c++)
                    b_matrix[k][c] = directed_b(k * N + c + 3);
            end
        end
    endtask

    task automatic load_random_tile(input int unsigned seed);
        int r;
        int c;
        int k;
        int unsigned state;
        begin
            // Xorshift32 is deterministic across simulators, unlike relying on
            // a simulator-specific $urandom sequence.
            state = seed;
            for (r = 0; r < N; r++) begin
                for (k = 0; k < K; k++) begin
                    state = state ^ (state << 13);
                    state = state ^ (state >> 17);
                    state = state ^ (state << 5);
                    a_matrix[r][k] = state[DATA_WIDTH-1:0];
                end
            end
            for (k = 0; k < K; k++) begin
                for (c = 0; c < N; c++) begin
                    state = state ^ (state << 13);
                    state = state ^ (state >> 17);
                    state = state ^ (state << 5);
                    b_matrix[k][c] = state[DATA_WIDTH-1:0];
                end
            end
        end
    endtask

    task automatic build_golden;
        int r;
        int c;
        int k;
        logic signed [PRODUCT_WIDTH-1:0] product;
        logic signed [ACC_WIDTH-1:0]     sum;
        begin
            for (r = 0; r < N; r++) begin
                for (c = 0; c < N; c++) begin
                    sum = '0;
                    for (k = 0; k < K; k++) begin
                        product = $signed(a_matrix[r][k]) * $signed(b_matrix[k][c]);
                        sum = sum + {{(ACC_WIDTH - PRODUCT_WIDTH){product[PRODUCT_WIDTH-1]}}, product};
                    end
                    golden[r][c] = sum;
                end
            end
        end
    endtask

    task automatic check_cleared(input string check_name);
        int r;
        int c;
        begin
            for (r = 0; r < N; r++) begin
                for (c = 0; c < N; c++) begin
                    checks++;
                    if (acc[r][c] !== '0) begin
                        $error("%s: C[%0d][%0d] was not cleared at %0t: got %0d (0x%h)",
                               check_name, r, c, $time, acc[r][c], acc[r][c]);
                        $fatal(1);
                    end
                end
            end
        end
    endtask

    task automatic check_results(input string tile_name);
        int r;
        int c;
        begin
            for (r = 0; r < N; r++) begin
                for (c = 0; c < N; c++) begin
                    checks++;
                    if (acc[r][c] !== golden[r][c]) begin
                        $error("%s: C[%0d][%0d] mismatch at %0t: got %0d (0x%h), expected %0d (0x%h)",
                               tile_name, r, c, $time,
                               acc[r][c], acc[r][c], golden[r][c], golden[r][c]);
                        $fatal(1);
                    end
                end
            end
        end
    endtask

    task automatic clear_array;
        begin
            // clear is synchronous, so hold it through a complete rising edge
            // before starting a new tile.  It also flushes feeder delays.
            @(negedge clk);
            clear = 1'b1;
            drive_idle();

            @(posedge clk);
            #1;
            check_cleared("clear");

            @(negedge clk);
            clear = 1'b0;
        end
    endtask

    task automatic run_current_tile(input string tile_name);
        int r;
        int c;
        int k;
        begin
            build_golden();
            clear_array();

            // K consecutive valid source slices implement the reduction axis.
            for (k = 0; k < K; k++) begin
                @(negedge clk);
                stream_valid = 1'b1;
                for (r = 0; r < N; r++)
                    a_stream[r] = a_matrix[r][k];
                for (c = 0; c < N; c++)
                    b_stream[c] = b_matrix[k][c];
                @(posedge clk);
            end

            @(negedge clk);
            drive_idle();

            // The documented conservative observation point is one cycle
            // beyond the final bottom-right PE update.
            repeat (DRAIN_CYCLES) @(posedge clk);
            #1;
            check_results(tile_name);
            tiles_run++;
        end
    endtask

    initial begin : test_sequence
        int random_index;

        if (N < 1 || K < 1) begin
            $fatal(1, "N and K must both be positive (N=%0d, K=%0d)", N, K);
        end
        if (ACC_WIDTH < PRODUCT_WIDTH) begin
            $fatal(1, "ACC_WIDTH (%0d) must be at least product width (%0d)",
                   ACC_WIDTH, PRODUCT_WIDTH);
        end

        clk       = 1'b0;
        rst       = 1'b1;
        clear     = 1'b0;
        checks    = 0;
        tiles_run = 0;
        drive_idle();

        // Synchronous reset also establishes a known state before the first
        // clear-and-compute transaction.
        repeat (2) @(posedge clk);
        #1;
        check_cleared("reset");
        @(negedge clk);
        rst = 1'b0;

        load_zero_tile();
        run_current_tile("all-zero tile");

        load_directed_tile();
        run_current_tile("directed signed/extreme tile");

        for (random_index = 0; random_index < RANDOM_TILES; random_index++) begin
            load_random_tile(32'h1bad_f00d + random_index);
            run_current_tile($sformatf("random tile %0d", random_index));
        end

        $display("PASS: tb_systolic_array completed %0d checks across %0d tiles (N=%0d, K=%0d).",
                 checks, tiles_run, N, K);
        $finish;
    end

endmodule : tb_systolic_array
