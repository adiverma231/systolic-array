// Shared defaults and sizing helpers for the systolic-array RTL.
package defines_pkg;

    parameter int DEFAULT_DATA_WIDTH = 8;
    parameter int DEFAULT_ACC_WIDTH  = 32;

    // An N-bit signed multiplication requires at most 2*N result bits.
    function automatic int product_width(input int data_width);
        return 2 * data_width;
    endfunction

endpackage : defines_pkg
