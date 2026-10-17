module fv_host_if (
    input logic       clk, rst_n,
    input logic [7:0] data,
    input logic [2:0] cmd,
    input logic       valid
);
    logic        arr_en, arr_clr, mode;
    logic [15:0] a0_left, a1_left, w_top;
    logic [3:0]  rd_addr;

    host_if dut (.*);

    localparam logic [2:0] PUSH = 3'd1, CLEAR = 3'd2, DRAIN = 3'd3, SET_CFG = 3'd4;

    logic past_valid = 0;
    always_ff @(posedge clk) past_valid <= 1;

    always_comb
        if (!past_valid) assume (!rst_n);

    logic       valid_q = 0;
    logic [2:0] cmd_q = 0;
    always_ff @(posedge clk) begin
        valid_q <= rst_n ? valid : 1'b0;
        cmd_q   <= cmd;
    end

    logic push_now, clear_now, drain_now, cfg_now;
    assign push_now  = rst_n && valid_q && cmd_q == PUSH;
    assign clear_now = rst_n && valid_q && cmd_q == CLEAR;
    assign drain_now = rst_n && valid_q && cmd_q == DRAIN;
    assign cfg_now   = rst_n && valid_q && cmd_q == SET_CFG;

    logic drain_sent_1 = 0, drain_sent_2 = 0;
    always_ff @(posedge clk) begin
        drain_sent_1 <= valid && cmd == DRAIN;
        drain_sent_2 <= drain_sent_1;
    end
    always_comb
        if (drain_sent_1 || drain_sent_2) assume (!valid);

    always_ff @(posedge clk) begin
        if (past_valid) begin
            if ($past(rst_n) && !$past(clear_now))
                assert (mode == $past(mode));
            if ($past(arr_clr))
                assert (a0_left[15:8] == 0 && a1_left[15:8] == 0 && w_top[15:8] == 0);
        end
    end

    always_comb
        if (past_valid) assert (arr_clr == (!rst_n || clear_now));

`ifdef CHECK_STAGING
    logic [2:0] count = 0;
    logic [2:0] full;
    assign full = mode ? 3'd6 : 3'd4;
    always_ff @(posedge clk) begin
        if (!rst_n || clear_now || drain_now || cfg_now)
            count <= 0;
        else if (push_now)
            count <= (count == full - 1) ? 3'd0 : count + 3'd1;
    end

    logic drain_was = 0;
    always_ff @(posedge clk) drain_was <= drain_now;
    logic drain_second;
    assign drain_second = drain_was && rst_n;

    always_comb
        if (past_valid)
            assert (arr_en == ((push_now && count == full - 1) || drain_now || drain_second));
`endif
endmodule
