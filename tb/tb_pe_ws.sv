`timescale 1ns/1ps

// Stage 2 unit test for the weight-stationary processing element.
//
// The PE owns one preloaded signed weight.  A valid compute token must cross
// the PE in one registered cycle: activation travels east, while the tag and
// psum + activation*weight travel south.  Preload, clear, and reset all form
// bubbles on those forwarding paths; reset and clear also erase the stored
// weight.
module tb_pe_ws #(
    parameter int DATA_WIDTH    = 8,
    parameter int ACC_WIDTH     = 32,
    parameter int TAG_WIDTH     = 2,
    parameter int RANDOM_VECTORS = 100
);

    localparam int PRODUCT_WIDTH = 2 * DATA_WIDTH;

    logic clk;
    logic rst;
    logic clear;
    logic weight_load;
    logic signed [DATA_WIDTH-1:0] weight_in;
    logic compute_valid;
    logic signed [DATA_WIDTH-1:0] a_in;
    logic signed [ACC_WIDTH-1:0] psum_in;
    logic [TAG_WIDTH-1:0] tag_in;

    logic out_valid;
    logic signed [DATA_WIDTH-1:0] a_out;
    logic signed [ACC_WIDTH-1:0] psum_out;
    logic [TAG_WIDTH-1:0] tag_out;

    logic signed [DATA_WIDTH-1:0] expected_weight;
    int checks;

    pe_ws #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH),
        .TAG_WIDTH (TAG_WIDTH)
    ) dut (
        .clk          (clk),
        .rst          (rst),
        .clear        (clear),
        .weight_load  (weight_load),
        .weight_in    (weight_in),
        .compute_valid(compute_valid),
        .a_in         (a_in),
        .psum_in      (psum_in),
        .tag_in       (tag_in),
        .out_valid    (out_valid),
        .a_out        (a_out),
        .psum_out     (psum_out),
        .tag_out      (tag_out)
    );

    always #5 clk = ~clk;

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

    task automatic expect_data(
        input string signal_name,
        input logic signed [DATA_WIDTH-1:0] actual,
        input logic signed [DATA_WIDTH-1:0] expected
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

    task automatic expect_psum(
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

    task automatic check_bubble(input string cycle_name);
        begin
            expect_valid({cycle_name, " out_valid"}, out_valid, 1'b0);
            expect_data ({cycle_name, " a_out"}, a_out, '0);
            expect_psum ({cycle_name, " psum_out"}, psum_out, '0);
            expect_tag  ({cycle_name, " tag_out"}, tag_out, '0);
        end
    endtask

    // Reset takes priority over every other PE input, including a load.
    task automatic reset_cycle(input logic signed [DATA_WIDTH-1:0] next_weight);
        begin
            @(negedge clk);
            rst           = 1'b1;
            clear         = 1'b0;
            weight_load   = 1'b1;
            weight_in     = next_weight;
            compute_valid = 1'b1;
            a_in          = -8'sd31;
            psum_in       = 32'sd99;
            tag_in        = {TAG_WIDTH{1'b1}};

            @(posedge clk);
            #1;
            expected_weight = '0;
            check_bubble("reset");
        end
    endtask

    // A preload occupies one full edge and cannot be mistaken for a compute
    // token even if compute_valid is asserted concurrently.
    task automatic preload_cycle(input logic signed [DATA_WIDTH-1:0] next_weight);
        begin
            @(negedge clk);
            rst           = 1'b0;
            clear         = 1'b0;
            weight_load   = 1'b1;
            weight_in     = next_weight;
            compute_valid = 1'b1;
            a_in          = 8'sd17;
            psum_in       = -32'sd71;
            tag_in        = {TAG_WIDTH{1'b1}};

            @(posedge clk);
            #1;
            expected_weight = next_weight;
            check_bubble("preload");
        end
    endtask

    task automatic compute_cycle(
        input logic signed [DATA_WIDTH-1:0] next_a,
        input logic signed [ACC_WIDTH-1:0]  next_psum,
        input logic [TAG_WIDTH-1:0]          next_tag,
        input logic                          next_valid
    );
        logic signed [PRODUCT_WIDTH-1:0] product;
        logic signed [ACC_WIDTH-1:0]     product_extended;
        logic signed [ACC_WIDTH-1:0]     expected_psum;
        begin
            @(negedge clk);
            rst           = 1'b0;
            clear         = 1'b0;
            weight_load   = 1'b0;
            // Deliberately perturb weight_in while loading is disabled.  The
            // expected result must still use the earlier stationary weight.
            weight_in     = ~expected_weight;
            compute_valid = next_valid;
            a_in          = next_a;
            psum_in       = next_psum;
            tag_in        = next_tag;

            @(posedge clk);
            #1;

            if (next_valid) begin
                product = $signed(next_a) * $signed(expected_weight);
                product_extended = {
                    {(ACC_WIDTH - PRODUCT_WIDTH){product[PRODUCT_WIDTH-1]}}, product
                };
                expected_psum = next_psum + product_extended;

                expect_valid("compute out_valid", out_valid, 1'b1);
                expect_data ("compute a_out", a_out, next_a);
                expect_psum ("compute psum_out", psum_out, expected_psum);
                expect_tag  ("compute tag_out", tag_out, next_tag);
            end else begin
                check_bubble("compute bubble");
            end
        end
    endtask

    // Clear is synchronous and must both flush registered traffic and erase
    // the previously stationary weight.
    task automatic clear_cycle;
        begin
            @(negedge clk);
            rst           = 1'b0;
            clear         = 1'b1;
            weight_load   = 1'b1;
            weight_in     = 8'sd127;
            compute_valid = 1'b1;
            a_in          = -8'sd128;
            psum_in       = -32'sd11;
            tag_in        = {TAG_WIDTH{1'b1}};

            @(posedge clk);
            #1;
            expected_weight = '0;
            check_bubble("clear");

            @(negedge clk);
            clear         = 1'b0;
            weight_load   = 1'b0;
            compute_valid = 1'b0;
            weight_in     = '0;
            a_in          = '0;
            psum_in       = '0;
            tag_in        = '0;
        end
    endtask

    initial begin : test_sequence
        int vector_index;
        int unsigned state;
        logic signed [DATA_WIDTH-1:0] random_a;
        logic signed [DATA_WIDTH-1:0] random_weight;
        logic signed [ACC_WIDTH-1:0]  random_psum;
        logic [TAG_WIDTH-1:0]         random_tag;

        if (DATA_WIDTH < 1 || ACC_WIDTH < PRODUCT_WIDTH || TAG_WIDTH < 1) begin
            $fatal(1,
                   "invalid test parameters: DATA_WIDTH=%0d ACC_WIDTH=%0d TAG_WIDTH=%0d",
                   DATA_WIDTH, ACC_WIDTH, TAG_WIDTH);
        end

        clk             = 1'b0;
        rst             = 1'b0;
        clear           = 1'b0;
        weight_load     = 1'b0;
        weight_in       = '0;
        compute_valid   = 1'b0;
        a_in            = '0;
        psum_in         = '0;
        tag_in          = '0;
        expected_weight = '0;
        checks          = 0;

        reset_cycle(8'sd73);
        reset_cycle(-8'sd128);

        @(negedge clk);
        rst = 1'b0;

        // Directed signed paths and tag forwarding.
        preload_cycle(-8'sd8);
        compute_cycle(8'sd3, -32'sd11, 2'd1, 1'b1);       // -35
        compute_cycle(-8'sd5, -32'sd20, 2'd2, 1'b1);      // +20
        compute_cycle(8'sd99, 32'sd99, 2'd3, 1'b0);

        preload_cycle(-8'sd128);
        compute_cycle(-8'sd128, -32'sd7, 2'd3, 1'b1);     // +16377
        preload_cycle(8'sd127);
        compute_cycle(-8'sd128, 32'sd1, 2'd0, 1'b1);      // -16255

        clear_cycle();
        // Proves clear erased the former 127 stationary weight.
        compute_cycle(8'sd127, 32'sd77, 2'd1, 1'b1);

        // Deterministic xorshift data supplies a broad signed and psum range
        // without relying on simulator-specific $urandom behavior.
        state = 32'h5a17_c0de;
        for (vector_index = 0; vector_index < RANDOM_VECTORS; vector_index++) begin
            state = state ^ (state << 13);
            state = state ^ (state >> 17);
            state = state ^ (state << 5);
            random_weight = state[DATA_WIDTH-1:0];

            if ((vector_index % 11) == 0)
                preload_cycle(random_weight);

            state = state ^ (state << 13);
            state = state ^ (state >> 17);
            state = state ^ (state << 5);
            random_a = state[DATA_WIDTH-1:0];

            state = state ^ (state << 13);
            state = state ^ (state >> 17);
            state = state ^ (state << 5);
            random_psum = state;
            random_tag = state[TAG_WIDTH-1:0];

            compute_cycle(random_a, random_psum, random_tag,
                          (vector_index % 7) != 0);
        end

        $display("PASS: tb_pe_ws completed %0d checks (%0d random compute vectors).",
                 checks, RANDOM_VECTORS);
        $finish;
    end

endmodule : tb_pe_ws
