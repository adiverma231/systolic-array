`timescale 1ns/1ps

// Reuse the public-interface tile test for the WS implementation.  Keeping
// the stimulus in tb_top ensures OS and WS are checked against the identical
// load/start/done/result contract and golden model.
module tb_top_ws #(
    parameter int N            = 4,
    parameter int K            = N,
    parameter int DATA_WIDTH   = 8,
    parameter int ACC_WIDTH    = 32,
    parameter int RANDOM_TILES = 3
);

    initial begin
        if (K != N)
            $fatal(1, "tb_top_ws requires K == N (N=%0d, K=%0d)", N, K);
    end

    tb_top #(
        .N           (N),
        .K           (K),
        .DATA_WIDTH  (DATA_WIDTH),
        .ACC_WIDTH   (ACC_WIDTH),
        .DATAFLOW    ("WS"),
        .RANDOM_TILES(RANDOM_TILES)
    ) u_tb_top ();

endmodule : tb_top_ws
