module fv_os_array (
    input logic        clk, clr, en, mode,
    input logic [15:0] a0_left, a1_left, w_top,
    input logic [3:0]  rd_addr
);
    logic [7:0] rd_data;
    logic       ovf;

    os_array dut (.*);

    logic past_valid = 0;
    always_ff @(posedge clk) past_valid <= 1;

    always_ff @(posedge clk) begin
        if (past_valid) begin
            if ($past(ovf) && !$past(clr))
                assert (ovf);
            if ($past(clr)) begin
                assert (rd_data == 0);
                assert (ovf == 0);
            end
        end
    end

    always_comb
        if (rd_addr >= 12) assert (rd_data == 0);
endmodule
