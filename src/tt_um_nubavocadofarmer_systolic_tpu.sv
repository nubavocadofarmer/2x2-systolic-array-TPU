`ifndef TT_UM_NUBAVOCADOFARMER_SYSTOLIC_TPU_V
`define TT_UM_NUBAVOCADOFARMER_SYSTOLIC_TPU_V

`timescale 1ns/1ps

module tt_um_nubavocadofarmer_systolic_tpu (
    input  logic [7:0] ui_in,
    output logic [7:0] uo_out,
    input  logic [7:0] uio_in,
    output logic [7:0] uio_out,
    output logic [7:0] uio_oe,
    input  logic       ena,
    input  logic       clk,
    input  logic       rst_n
);
    logic arr_en, arr_clr, mode;
    logic [15:0] a0_left, a1_left, w_top;
    logic [3:0] rd_addr;
    logic [7:0] rd_data;
    logic ovf;
    logic unused_inputs;

    host_if u_host_if (
        .clk(clk),
        .rst_n(rst_n),
        .data(ui_in),
        .cmd(uio_in[2:0]),
        .valid(uio_in[3]),
        .arr_en(arr_en),
        .arr_clr(arr_clr),
        .mode(mode),
        .a0_left(a0_left),
        .a1_left(a1_left),
        .w_top(w_top),
        .rd_addr(rd_addr)
    );

    os_array u_os_array (
        .clk(clk),
        .clr(arr_clr),
        .en(arr_en),
        .mode(mode),
        .a0_left(a0_left),
        .a1_left(a1_left),
        .w_top(w_top),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .ovf(ovf)
    );

    assign uo_out = rd_data;
    assign uio_out = {1'b0, ovf, 6'b000000};
    assign uio_oe = 8'b0100_0000;
    assign unused_inputs = &{ena, uio_in[7:4]};
endmodule

`endif
