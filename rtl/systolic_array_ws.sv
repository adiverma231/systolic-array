`timescale 1ns/1ps

// Weight-stationary systolic mesh.
//
// Row r corresponds to reduction index k=r and column c corresponds to an
// output column.  During a parallel preload, PE [r][c] captures weights[r][c].
// In compute mode, activation tokens advance east while partial-sum/tag tokens
// advance south.  The west and north inputs are expected to be skewed by the
// feeder so their valid tokens meet at each PE.
module systolic_array_ws #(
    parameter int N          = 4,
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = 32,
    parameter int TAG_WIDTH  = (N <= 1) ? 1 : $clog2(N)
) (
    input logic clk,
    input logic rst,
    input logic clear,

    input logic                         weight_load,
    input logic signed [DATA_WIDTH-1:0] weights [0:N-1][0:N-1],

    input logic signed [DATA_WIDTH-1:0] a_west       [0:N-1],
    input logic                         a_west_valid [0:N-1],

    input logic signed [ACC_WIDTH-1:0] psum_north       [0:N-1],
    input logic                        psum_north_valid [0:N-1],
    input logic        [TAG_WIDTH-1:0] tag_north        [0:N-1],

    output wire signed [ACC_WIDTH-1:0] psum_south       [0:N-1],
    output wire                        psum_south_valid [0:N-1],
    output wire        [TAG_WIDTH-1:0] tag_south        [0:N-1]
);

    // a_link[r][c] enters PE [r][c] from the west.  The retained final
    // column models the unexposed east boundary and gives the final PE a
    // normal one-hop connection.
    wire signed [DATA_WIDTH-1:0] a_link       [0:N-1][0:N];
    wire                         a_link_valid [0:N-1][0:N];

    // psum_link[r][c] and tag_link[r][c] enter PE [r][c] from the north.
    // Their final row is the mesh's public south boundary.
    wire signed [ACC_WIDTH-1:0] psum_link       [0:N][0:N-1];
    wire                        psum_link_valid [0:N][0:N-1];
    wire        [TAG_WIDTH-1:0] tag_link        [0:N][0:N-1];

    wire pe_out_valid [0:N-1][0:N-1];

    genvar r;
    genvar c;
    generate
        for (r = 0; r < N; r = r + 1) begin : gen_west_boundary
            assign a_link[r][0]       = a_west[r];
            assign a_link_valid[r][0] = a_west_valid[r];
        end

        for (c = 0; c < N; c = c + 1) begin : gen_north_boundary
            assign psum_link[0][c]       = psum_north[c];
            assign psum_link_valid[0][c] = psum_north_valid[c];
            assign tag_link[0][c]        = tag_north[c];

            assign psum_south[c]       = psum_link[N][c];
            assign psum_south_valid[c] = psum_link_valid[N][c];
            assign tag_south[c]        = tag_link[N][c];
        end

        for (r = 0; r < N; r = r + 1) begin : gen_rows
            for (c = 0; c < N; c = c + 1) begin : gen_columns
                pe_ws #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH (ACC_WIDTH),
                    .TAG_WIDTH (TAG_WIDTH)
                ) u_pe_ws (
                    .clk          (clk),
                    .rst          (rst),
                    .clear        (clear),
                    .weight_load  (weight_load),
                    .weight_in    (weights[r][c]),
                    .compute_valid(a_link_valid[r][c] & psum_link_valid[r][c]),
                    .a_in         (a_link[r][c]),
                    .psum_in      (psum_link[r][c]),
                    .tag_in       (tag_link[r][c]),
                    .out_valid    (pe_out_valid[r][c]),
                    .a_out        (a_link[r][c + 1]),
                    .psum_out     (psum_link[r + 1][c]),
                    .tag_out      (tag_link[r + 1][c])
                );

                assign a_link_valid[r][c + 1] = pe_out_valid[r][c];
                assign psum_link_valid[r + 1][c] = pe_out_valid[r][c];
            end
        end
    endgenerate

endmodule : systolic_array_ws
