`timescale 1ns/1ps

// Stage 0 unit test for the output-stationary processing element.
//
// Interface contract exercised here:
//   * rst and clear are synchronous and flush accumulator/forwarding state.
//   * a_out/w_out/out_valid are registered (one clock of forwarding latency).
//   * A bubble (in_valid=0) cannot modify the accumulator.
//   * acc accumulates valid signed int8 products into a signed int32 register.
module tb_pe_os;
    localparam int DATA_WIDTH = 8;
    localparam int ACC_WIDTH  = 32;
    localparam int RANDOM_VECTORS = 100;

    logic clk;
    logic rst;
    logic clear;
    logic in_valid;
    logic signed [DATA_WIDTH-1:0] a_in;
    logic signed [DATA_WIDTH-1:0] w_in;
    logic out_valid;
    logic signed [DATA_WIDTH-1:0] a_out;
    logic signed [DATA_WIDTH-1:0] w_out;
    logic signed [ACC_WIDTH-1:0]  acc;

    logic signed [ACC_WIDTH-1:0] expected_acc;
    int checks;

    pe_os #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) dut (
        .clk  (clk),
        .rst  (rst),
        .clear(clear),
        .in_valid (in_valid),
        .a_in (a_in),
        .w_in (w_in),
        .out_valid(out_valid),
        .a_out(a_out),
        .w_out(w_out),
        .acc  (acc)
    );

    always #5 clk = ~clk;

    task automatic expect_equal(
        input string                 signal_name,
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
        input logic  actual,
        input logic  expected
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

    // Drive input during the low half-cycle, then check registered state just
    // after the following rising edge.
    task automatic mac_cycle(
        input logic signed [DATA_WIDTH-1:0] next_a,
        input logic signed [DATA_WIDTH-1:0] next_w,
        input logic                          next_valid,
        input logic                          next_clear
    );
        logic signed [ACC_WIDTH-1:0] product;
        begin
            @(negedge clk);
            a_in  = next_a;
            w_in  = next_w;
            in_valid = next_valid;
            clear = next_clear;

            @(posedge clk);
            #1;

            product = $signed(next_a) * $signed(next_w);
            if (next_clear)
                expected_acc = '0;
            else if (next_valid)
                expected_acc = expected_acc + product;

            if (next_clear) begin
                expect_equal("a_out after clear",
                             {{(ACC_WIDTH-DATA_WIDTH){a_out[DATA_WIDTH-1]}}, a_out}, '0);
                expect_equal("w_out after clear",
                             {{(ACC_WIDTH-DATA_WIDTH){w_out[DATA_WIDTH-1]}}, w_out}, '0);
                expect_valid("out_valid after clear", out_valid, 1'b0);
            end
            else if (next_valid) begin
                expect_equal("a_out", {{(ACC_WIDTH-DATA_WIDTH){a_out[DATA_WIDTH-1]}}, a_out},
                             {{(ACC_WIDTH-DATA_WIDTH){next_a[DATA_WIDTH-1]}}, next_a});
                expect_equal("w_out", {{(ACC_WIDTH-DATA_WIDTH){w_out[DATA_WIDTH-1]}}, w_out},
                             {{(ACC_WIDTH-DATA_WIDTH){next_w[DATA_WIDTH-1]}}, next_w});
                expect_valid("out_valid", out_valid, 1'b1);
            end
            else begin
                // The PE must explicitly flush the forwarding payload on a
                // bubble so downstream PEs cannot consume stale operands.
                expect_equal("a_out for bubble",
                             {{(ACC_WIDTH-DATA_WIDTH){a_out[DATA_WIDTH-1]}}, a_out}, '0);
                expect_equal("w_out for bubble",
                             {{(ACC_WIDTH-DATA_WIDTH){w_out[DATA_WIDTH-1]}}, w_out}, '0);
                expect_valid("out_valid for bubble", out_valid, 1'b0);
            end
            expect_equal("acc", acc, expected_acc);
        end
    endtask

    task automatic reset_cycle(
        input logic signed [DATA_WIDTH-1:0] next_a,
        input logic signed [DATA_WIDTH-1:0] next_w
    );
        begin
            @(negedge clk);
            rst   = 1'b1;
            clear = 1'b0;
            in_valid = 1'b1;
            a_in  = next_a;
            w_in  = next_w;

            @(posedge clk);
            #1;
            expected_acc = '0;
            expect_equal("a_out after rst",
                         {{(ACC_WIDTH-DATA_WIDTH){a_out[DATA_WIDTH-1]}}, a_out}, '0);
            expect_equal("w_out after rst",
                         {{(ACC_WIDTH-DATA_WIDTH){w_out[DATA_WIDTH-1]}}, w_out}, '0);
            expect_valid("out_valid after rst", out_valid, 1'b0);
            expect_equal("acc after rst", acc, '0);
        end
    endtask

    initial begin : test_sequence
        int vector_index;
        logic signed [DATA_WIDTH-1:0] random_a;
        logic signed [DATA_WIDTH-1:0] random_w;

        clk          = 1'b0;
        rst          = 1'b0;
        clear        = 1'b0;
        in_valid     = 1'b0;
        a_in         = '0;
        w_in         = '0;
        expected_acc = '0;
        checks       = 0;

        // Reset must take priority, be synchronous, and clear forwarding regs.
        reset_cycle(8'sd37, -8'sd11);
        reset_cycle(-8'sd128, 8'sd127);

        @(negedge clk);
        rst      = 1'b0;
        clear    = 1'b0;
        in_valid = 1'b0;
        a_in     = '0;
        w_in     = '0;

        // Directed signed MAC and forwarding checks.
        mac_cycle(8'sd3,     8'sd4,     1'b1, 1'b0); // +12
        mac_cycle(-8'sd5,    8'sd7,     1'b1, 1'b0); // -35
        mac_cycle(-8'sd128, -8'sd128,  1'b1, 1'b0); // +16384
        mac_cycle(8'sd127,  -8'sd128,  1'b1, 1'b0); // -16256

        // A bubble drives invalid/zero forwards and leaves the accumulator unchanged.
        mac_cycle(-8'sd9,    8'sd13,    1'b0, 1'b0);

        // clear flushes the accumulator and forwarding state regardless of input.
        mac_cycle(-8'sd9,    8'sd13,    1'b1, 1'b1);
        mac_cycle(8'sd1,    -8'sd1,     1'b1, 1'b0);

        // Deterministic pseudo-random signed int8 vectors.
        for (vector_index = 0; vector_index < RANDOM_VECTORS; vector_index++) begin
            random_a = $signed(DATA_WIDTH'($urandom));
            random_w = $signed(DATA_WIDTH'($urandom));
            mac_cycle(random_a, random_w, (vector_index % 7) != 0, 1'b0);
        end

        $display("PASS: tb_pe_os completed %0d checks (%0d random MAC vectors).",
                 checks, RANDOM_VECTORS);
        $finish;
    end
endmodule
