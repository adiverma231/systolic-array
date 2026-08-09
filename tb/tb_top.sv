`timescale 1ns/1ps

// Stage 1 tile-level verification for the load/start/done top-level wrapper.
//
// This test intentionally drives only the public contract documented in
// docs/TOP_INTERFACE_CONTRACT.md.  It writes complete A[N,K] and B[K,N]
// tiles while idle, starts one operation, waits for the one-cycle `done`
// notification, then reads and checks every entry of C[N,N].
module tb_top #(
    parameter int N            = 4,
    parameter int K            = N,
    parameter int DATA_WIDTH   = 8,
    parameter int ACC_WIDTH    = 32,
    parameter     DATAFLOW     = "OS",
    parameter int RANDOM_TILES = 3
);

    localparam int ADDR_N             = (N <= 1) ? 1 : $clog2(N);
    localparam int ADDR_K             = (K <= 1) ? 1 : $clog2(K);
    localparam int PRODUCT_WIDTH      = 2 * DATA_WIDTH;
    localparam int DONE_TIMEOUT_CYCLES = K + (4 * N) + 32;

    logic clk;
    logic rst;
    logic start;

    logic load_a_en;
    logic [ADDR_N-1:0] load_a_row;
    logic [ADDR_K-1:0] load_a_col;
    logic signed [DATA_WIDTH-1:0] load_a_data;

    logic load_b_en;
    logic [ADDR_K-1:0] load_b_row;
    logic [ADDR_N-1:0] load_b_col;
    logic signed [DATA_WIDTH-1:0] load_b_data;

    wire busy;
    wire done;

    logic [ADDR_N-1:0] result_row;
    logic [ADDR_N-1:0] result_col;
    wire signed [ACC_WIDTH-1:0] result_data;

    logic signed [DATA_WIDTH-1:0] a_tile [0:N-1][0:K-1];
    logic signed [DATA_WIDTH-1:0] b_tile [0:K-1][0:N-1];
    logic signed [ACC_WIDTH-1:0]  golden [0:N-1][0:N-1];

    int checks;
    int tiles_run;

    top #(
        .N         (N),
        .K         (K),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH),
        .DATAFLOW (DATAFLOW)
    ) dut (
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
        .done       (done),

        .result_row (result_row),
        .result_col (result_col),
        .result_data(result_data)
    );

    always #5 clk = ~clk;

    function automatic logic signed [DATA_WIDTH-1:0] directed_a(input int index);
        begin
            // Zero, sign, and both signed int8 extrema all occur in each
            // default 4x4 tile.
            case (index % 8)
                0:       directed_a = 0;
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
                0:       directed_b = 0;
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
        begin
            start       = 1'b0;
            load_a_en   = 1'b0;
            load_a_row  = '0;
            load_a_col  = '0;
            load_a_data = '0;
            load_b_en   = 1'b0;
            load_b_row  = '0;
            load_b_col  = '0;
            load_b_data = '0;
            result_row  = '0;
            result_col  = '0;
        end
    endtask

    task automatic load_zero_tile;
        int r;
        int c;
        int k;
        begin
            for (r = 0; r < N; r++) begin
                for (k = 0; k < K; k++)
                    a_tile[r][k] = '0;
            end
            for (k = 0; k < K; k++) begin
                for (c = 0; c < N; c++)
                    b_tile[k][c] = '0;
            end
        end
    endtask

    task automatic load_signed_extreme_tile;
        int r;
        int c;
        int k;
        begin
            for (r = 0; r < N; r++) begin
                for (k = 0; k < K; k++)
                    a_tile[r][k] = directed_a(r * K + k);
            end
            for (k = 0; k < K; k++) begin
                for (c = 0; c < N; c++)
                    b_tile[k][c] = directed_b(k * N + c + 3);
            end
        end
    endtask

    task automatic load_random_tile(input int unsigned seed);
        int r;
        int c;
        int k;
        int unsigned state;
        begin
            // Xorshift32 makes the stimulus deterministic across simulators.
            state = seed;
            for (r = 0; r < N; r++) begin
                for (k = 0; k < K; k++) begin
                    state = state ^ (state << 13);
                    state = state ^ (state >> 17);
                    state = state ^ (state << 5);
                    a_tile[r][k] = state[DATA_WIDTH-1:0];
                end
            end
            for (k = 0; k < K; k++) begin
                for (c = 0; c < N; c++) begin
                    state = state ^ (state << 13);
                    state = state ^ (state >> 17);
                    state = state ^ (state << 5);
                    b_tile[k][c] = state[DATA_WIDTH-1:0];
                end
            end
        end
    endtask

    task automatic build_golden;
        int r;
        int c;
        int k;
        logic signed [PRODUCT_WIDTH-1:0] product;
        logic signed [ACC_WIDTH-1:0] sum;
        begin
            for (r = 0; r < N; r++) begin
                for (c = 0; c < N; c++) begin
                    sum = '0;
                    for (k = 0; k < K; k++) begin
                        product = $signed(a_tile[r][k]) * $signed(b_tile[k][c]);
                        sum = sum + {{(ACC_WIDTH - PRODUCT_WIDTH){product[PRODUCT_WIDTH-1]}}, product};
                    end
                    golden[r][c] = sum;
                end
            end
        end
    endtask

    task automatic write_current_tile(input string tile_name);
        int index;
        begin
            if (busy !== 1'b0) begin
                $error("%s: expected idle before loading, busy=%b at %0t",
                       tile_name, busy, $time);
                $fatal(1);
            end

            // A[N,K] and B[K,N] have equal entry counts, so write one entry
            // of each memory on every load cycle.  The contract permits both
            // writes in the same cycle.
            for (index = 0; index < N * K; index++) begin
                @(negedge clk);
                load_a_en   = 1'b1;
                load_a_row  = ADDR_N'(index / K);
                load_a_col  = ADDR_K'(index % K);
                load_a_data = a_tile[index / K][index % K];

                load_b_en   = 1'b1;
                load_b_row  = ADDR_K'(index / N);
                load_b_col  = ADDR_N'(index % N);
                load_b_data = b_tile[index / N][index % N];

                @(posedge clk);
            end

            @(negedge clk);
            load_a_en = 1'b0;
            load_b_en = 1'b0;
        end
    endtask

    task automatic wait_for_done(input string tile_name);
        int elapsed_cycles;
        begin
            @(negedge clk);
            start = 1'b1;

            // `start` is accepted on this edge.  The contract requires busy
            // to assert for the transaction beginning here.
            @(posedge clk);
            #1;
            if (busy !== 1'b1) begin
                $error("%s: busy did not assert after start at %0t (busy=%b)",
                       tile_name, $time, busy);
                $fatal(1);
            end

            @(negedge clk);
            start = 1'b0;

            elapsed_cycles = 0;
            while ((done !== 1'b1) && (elapsed_cycles < DONE_TIMEOUT_CYCLES)) begin
                @(posedge clk);
                #1;
                elapsed_cycles = elapsed_cycles + 1;

                // busy must remain asserted until the done notification.
                if ((done !== 1'b1) && (busy !== 1'b1)) begin
                    $error("%s: busy deasserted before done at %0t", tile_name, $time);
                    $fatal(1);
                end
            end

            if (done !== 1'b1) begin
                $error("%s: timed out waiting for done after %0d cycles at %0t",
                       tile_name, DONE_TIMEOUT_CYCLES, $time);
                $fatal(1);
            end

            // The capture must precede the done notification, so results are
            // readable immediately after observing done.
            #1;

            // Verify the documented pulse width before moving on to result
            // reads.  `busy` is expected to return low with the controller
            // back in its idle/load state.
            @(posedge clk);
            #1;
            if (done !== 1'b0) begin
                $error("%s: done was not a one-cycle pulse at %0t", tile_name, $time);
                $fatal(1);
            end
            if (busy !== 1'b0) begin
                $error("%s: expected idle after completion at %0t (busy=%b)",
                       tile_name, $time, busy);
                $fatal(1);
            end
        end
    endtask

    task automatic check_results(input string tile_name);
        int r;
        int c;
        begin
            for (r = 0; r < N; r++) begin
                for (c = 0; c < N; c++) begin
                    @(negedge clk);
                    result_row = ADDR_N'(r);
                    result_col = ADDR_N'(c);
                    #1;

                    checks = checks + 1;
                    if (result_data !== golden[r][c]) begin
                        $error("%s: C[%0d][%0d] mismatch at %0t: got %0d (0x%h), expected %0d (0x%h)",
                               tile_name, r, c, $time,
                               result_data, result_data, golden[r][c], golden[r][c]);
                        $fatal(1);
                    end
                end
            end

        end
    endtask

    task automatic run_current_tile(input string tile_name);
        begin
            build_golden();
            write_current_tile(tile_name);
            wait_for_done(tile_name);
            check_results(tile_name);
            tiles_run = tiles_run + 1;
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
        checks    = 0;
        tiles_run = 0;
        drive_idle();

        // Reset is synchronous.  Do not issue writes or start until it has
        // been held through complete rising edges and then released.
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        load_zero_tile();
        run_current_tile("all-zero tile");

        load_signed_extreme_tile();
        run_current_tile("directed signed/extreme tile");

        for (random_index = 0; random_index < RANDOM_TILES; random_index++) begin
            load_random_tile(32'h1bad_f00d + random_index);
            run_current_tile($sformatf("deterministic random tile %0d", random_index));
        end

        $display("PASS: tb_top completed %0d result checks across %0d tiles (N=%0d, K=%0d).",
                 checks, tiles_run, N, K);
        $finish;
    end

endmodule : tb_top
