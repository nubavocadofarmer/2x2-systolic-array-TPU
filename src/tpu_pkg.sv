`timescale 1ns/1ps

package tpu_pkg;
    /* verilator lint_off UNUSEDPARAM */
    localparam int AW = 24;

    localparam logic MODE_INT8 = 1'b0;
    localparam logic MODE_W4A8 = 1'b1;
    /* verilator lint_on UNUSEDPARAM */

    typedef enum logic [2:0] {
        CMD_NOP,
        CMD_PUSH,
        CMD_CLEAR,
        CMD_DRAIN,
        CMD_SET_CFG,
        CMD_RD_PTR,
        CMD_RD_NEXT,
        CMD_RSVD
    } cmd_t;
endpackage
