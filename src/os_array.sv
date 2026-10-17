`ifndef OS_ARRAY_V
`define OS_ARRAY_V

`timescale 1ns/1ps

module os_array (
    input  logic        clk,
    input  logic        clr,
    input  logic        en,
    input  logic        mode,
    input  logic [15:0] a0_left,
    input  logic [15:0] a1_left,
    input  logic [15:0] w_top,
    input  logic [3:0]  rd_addr,
    output logic [7:0]  rd_data,
    output logic        ovf
);
    logic signed [7:0] a0_00, a1_00, w_00;
    logic signed [7:0] a0_10, a1_10, w_01;
    logic signed [23:0] acc_00, acc_01, acc_10, acc_11;
    logic ovf_00, ovf_01, ovf_10, ovf_11;

    logic signed [7:0] unused_a0_01, unused_a1_01;
    logic signed [7:0] unused_w_10;
    logic signed [7:0] unused_a0_11, unused_a1_11, unused_w_11;

    os_pe pe_00 (
        .clk(clk),
        .clr(clr),
        .en(en),
        .mode(mode),
        .a0_in($signed(a0_left[7:0])),
        .a1_in($signed(a1_left[7:0])),
        .w_in($signed(w_top[7:0])),
        .a0_out(a0_00),
        .a1_out(a1_00),
        .w_out(w_00),
        .acc(acc_00),
        .ovf(ovf_00)
    );

    os_pe pe_01 (
        .clk(clk),
        .clr(clr),
        .en(en),
        .mode(mode),
        .a0_in(a0_00),
        .a1_in(a1_00),
        .w_in($signed(w_top[15:8])),
        .a0_out(unused_a0_01),
        .a1_out(unused_a1_01),
        .w_out(w_01),
        .acc(acc_01),
        .ovf(ovf_01)
    );

    os_pe pe_10 (
        .clk(clk),
        .clr(clr),
        .en(en),
        .mode(mode),
        .a0_in($signed(a0_left[15:8])),
        .a1_in($signed(a1_left[15:8])),
        .w_in(w_00),
        .a0_out(a0_10),
        .a1_out(a1_10),
        .w_out(unused_w_10),
        .acc(acc_10),
        .ovf(ovf_10)
    );

    os_pe pe_11 (
        .clk(clk),
        .clr(clr),
        .en(en),
        .mode(mode),
        .a0_in(a0_10),
        .a1_in(a1_10),
        .w_in(w_01),
        .a0_out(unused_a0_11),
        .a1_out(unused_a1_11),
        .w_out(unused_w_11),
        .acc(acc_11),
        .ovf(ovf_11)
    );

    assign ovf = ovf_00 | ovf_01 | ovf_10 | ovf_11;

    always_comb begin
        case (rd_addr)
            4'd0:  rd_data = acc_00[7:0];
            4'd1:  rd_data = acc_00[15:8];
            4'd2:  rd_data = acc_00[23:16];
            4'd3:  rd_data = acc_01[7:0];
            4'd4:  rd_data = acc_01[15:8];
            4'd5:  rd_data = acc_01[23:16];
            4'd6:  rd_data = acc_10[7:0];
            4'd7:  rd_data = acc_10[15:8];
            4'd8:  rd_data = acc_10[23:16];
            4'd9:  rd_data = acc_11[7:0];
            4'd10: rd_data = acc_11[15:8];
            4'd11: rd_data = acc_11[23:16];
            default: rd_data = '0;
        endcase
    end
endmodule

`endif
