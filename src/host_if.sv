`ifndef HOST_IF_V
`define HOST_IF_V

`timescale 1ns/1ps

module host_if (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [7:0]  data,
    input  logic [2:0]  cmd,
    input  logic        valid,
    output logic        arr_en,
    output logic        arr_clr,
    output logic        mode,
    output logic [15:0] a0_left,
    output logic [15:0] a1_left,
    output logic [15:0] w_top,
    output logic [3:0]  rd_addr
);

    logic [7:0] data_reg;
    logic [2:0] cmd_reg;
    logic valid_reg;

    logic cfg_mode;
    logic [7:0] staging [0:5];
    logic [2:0] sptr;
    logic drain_pending;

    logic [15:0] a0_raw, a1_raw, w_raw;
    logic [7:0] a0_skew, a1_skew, w_skew;

    always_comb begin
        arr_en = 1'b0;
        arr_clr = 1'b0;
        a0_raw = '0;
        a1_raw = '0;
        w_raw = '0;

        if (!rst_n)
            arr_clr = 1'b1;
        else if (drain_pending)
            arr_en = 1'b1;
        else if (valid_reg) begin
            case (cmd_reg)
                tpu_pkg::CMD_CLEAR: arr_clr = 1'b1;
                tpu_pkg::CMD_DRAIN: arr_en = 1'b1;
                tpu_pkg::CMD_PUSH: begin
                    if (!mode && sptr == 3'd3) begin
                        arr_en = 1'b1;
                        a0_raw = {staging[1], staging[0]};
                        w_raw = {data_reg, staging[2]};
                    end
                    else if (mode && sptr == 3'd5) begin
                        arr_en = 1'b1;
                        a0_raw = {staging[2], staging[0]};
                        a1_raw = {staging[3], staging[1]};
                        w_raw = {data_reg, staging[4]};
                    end
                end
                default: begin
                end
            endcase
        end
    end

    assign a0_left = {a0_skew, a0_raw[7:0]};
    assign a1_left = {a1_skew, a1_raw[7:0]};
    assign w_top = {w_skew, w_raw[7:0]};

    always_ff @(posedge clk) begin
        if (!rst_n || arr_clr) begin
            a0_skew <= '0;
            a1_skew <= '0;
            w_skew <= '0;
        end
        else if (arr_en) begin
            a0_skew <= a0_raw[15:8];
            a1_skew <= a1_raw[15:8];
            w_skew <= w_raw[15:8];
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            data_reg <= '0;
            cmd_reg <= tpu_pkg::CMD_NOP;
            valid_reg <= 1'b0;
            cfg_mode <= tpu_pkg::MODE_INT8;
            mode <= tpu_pkg::MODE_INT8;
            sptr <= '0;
            drain_pending <= 1'b0;
            rd_addr <= '0;
            for (int i = 0; i < 6; i++)
                staging[i] <= '0;
        end
        else begin
            data_reg <= data;
            cmd_reg <= cmd;
            valid_reg <= valid;

            if (drain_pending)
                drain_pending <= 1'b0;
            else if (valid_reg) begin
                case (cmd_reg)
                    tpu_pkg::CMD_PUSH: begin
                        staging[sptr] <= data_reg;
                        if ((!mode && sptr == 3'd3) || (mode && sptr == 3'd5))
                            sptr <= '0;
                        else
                            sptr <= sptr + 3'd1;
                    end
                    tpu_pkg::CMD_CLEAR: begin
                        mode <= cfg_mode;
                        sptr <= '0;
                        drain_pending <= 1'b0;
                        for (int i = 0; i < 6; i++)
                            staging[i] <= '0;
                    end
                    tpu_pkg::CMD_DRAIN: begin
                        sptr <= '0;
                        drain_pending <= 1'b1;
                    end
                    tpu_pkg::CMD_SET_CFG: begin
                        cfg_mode <= data_reg[0];
                        sptr <= '0;
                    end
                    tpu_pkg::CMD_RD_PTR: rd_addr <= data_reg[3:0];
                    tpu_pkg::CMD_RD_NEXT: rd_addr <= rd_addr + 4'd1;
                    default: begin
                    end
                endcase
            end
        end
    end
endmodule

`endif
