`ifndef OS_PE_V
`define OS_PE_V

`timescale 1ns/1ps

module os_pe (
    input  logic               clk,
    input  logic               clr,
    input  logic               en,
    input  logic               mode,
    input  logic signed [7:0]  a0_in,
    input  logic signed [7:0]  a1_in,
    input  logic signed [7:0]  w_in,
    output logic signed [7:0]  a0_out,
    output logic signed [7:0]  a1_out,
    output logic signed [7:0]  w_out,
    output logic signed [23:0] acc,
    output logic               ovf
);
    logic signed [4:0] weight_high;
    logic signed [4:0] weight_low;
    logic signed [7:0] activation_high;

    logic signed [12:0] product_high;
    logic signed [12:0] product_low;
    logic signed [15:0] extended_high;
    logic signed [15:0] extended_low;
    logic signed [15:0] mult_out;
    logic signed [23:0] extended_product;
    logic signed [23:0] mac_out;
    logic overflow;

    always_comb begin
        weight_high = {w_in[7], w_in[7:4]};

        if (mode) begin
            weight_low = {w_in[3], w_in[3:0]};
            activation_high = a1_in;
        end
        else begin
            weight_low = {1'b0, w_in[3:0]};
            activation_high = a0_in;
        end
    end

    assign product_high = activation_high * weight_high;
    assign product_low = a0_in * weight_low;
    assign extended_high = {{3{product_high[12]}}, product_high};
    assign extended_low = {{3{product_low[12]}}, product_low};

    always_comb begin
        if (mode)
            mult_out = extended_high + extended_low;
        else
            mult_out = (extended_high <<< 4) + extended_low;
    end

    assign extended_product = {{8{mult_out[15]}}, mult_out};
    assign mac_out = acc + extended_product;
    assign overflow = (acc[23] == extended_product[23]) &&
                      (mac_out[23] != acc[23]);

    always_ff @(posedge clk) begin
        if (clr) begin
            acc    <= '0;
            ovf    <= 1'b0;
            a0_out <= '0;
            a1_out <= '0;
            w_out  <= '0;
        end
        else if (!en) begin
        end
        else begin
            acc    <= mac_out;
            ovf    <= ovf | overflow;
            a0_out <= a0_in;
            a1_out <= a1_in;
            w_out  <= w_in;
        end
    end
endmodule

`endif
