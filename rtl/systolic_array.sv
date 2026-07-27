`timescale 1ns/1ps

// Output-stationary systolic mesh.
//
// The mesh receives already-skewed operand streams at its west and north
// edges.  Each pe_os registers its forwarded operands, so a_link and w_link
// below model distinct one-hop registered networks: activations travel east
// and weights travel south.  A PE only consumes an operand pair when the two
// corresponding link-valid bits are both asserted.
module systolic_array #(
    parameter int N          = 4,
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = 32
) (
    input logic clk,
    input logic rst,
    input logic clear,
    input logic signed [DATA_WIDTH-1:0] a_west [0:N-1],
    input logic                         a_west_valid [0:N-1],
    input logic signed [DATA_WIDTH-1:0] w_north [0:N-1],
    input logic                         w_north_valid [0:N-1],
    output wire signed [ACC_WIDTH-1:0]  acc [0:N-1][0:N-1]
);

    // a_link[r][c] enters PE [r][c] from the west.  Its last column is
    // retained as the east-facing output boundary of the mesh.
    wire signed [DATA_WIDTH-1:0] a_link       [0:N-1][0:N];
    wire                         a_link_valid [0:N-1][0:N];

    // w_link[r][c] enters PE [r][c] from the north.  Its last row is
    // retained as the south-facing output boundary of the mesh.
    wire signed [DATA_WIDTH-1:0] w_link       [0:N][0:N-1];
    wire                         w_link_valid [0:N][0:N-1];

    // A PE has one paired-token valid output.  It fans out into the two
    // separately named operand-valid networks, matching pe_os forwarding.
    wire pe_out_valid [0:N-1][0:N-1];

    genvar r;
    genvar c;
    generate
        for (r = 0; r < N; r = r + 1) begin : gen_west_boundary
            assign a_link[r][0]       = a_west[r];
            assign a_link_valid[r][0] = a_west_valid[r];
        end

        for (c = 0; c < N; c = c + 1) begin : gen_north_boundary
            assign w_link[0][c]       = w_north[c];
            assign w_link_valid[0][c] = w_north_valid[c];
        end

        for (r = 0; r < N; r = r + 1) begin : gen_rows
            for (c = 0; c < N; c = c + 1) begin : gen_columns
                pe_os #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH (ACC_WIDTH)
                ) u_pe_os (
                    .clk      (clk),
                    .rst      (rst),
                    .clear    (clear),
                    .in_valid (a_link_valid[r][c] & w_link_valid[r][c]),
                    .a_in     (a_link[r][c]),
                    .w_in     (w_link[r][c]),
                    .out_valid(pe_out_valid[r][c]),
                    .a_out    (a_link[r][c + 1]),
                    .w_out    (w_link[r + 1][c]),
                    .acc      (acc[r][c])
                );

                assign a_link_valid[r][c + 1] = pe_out_valid[r][c];
                assign w_link_valid[r + 1][c] = pe_out_valid[r][c];
            end
        end
    endgenerate

endmodule : systolic_array
