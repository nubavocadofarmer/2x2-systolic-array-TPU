module fv_os_pe (
    input logic              clk, clr, en, mode,
    input logic signed [7:0] a0_in, a1_in, w_in
);
    logic signed [7:0]  a0_out, a1_out, w_out;
    logic signed [23:0] acc;
    logic               ovf;

    os_pe dut (.*);

    logic past_valid = 0;
    always_ff @(posedge clk) past_valid <= 1;

    always_ff @(posedge clk) begin
        if (past_valid) begin
            if ($past(ovf) && !$past(clr))
                assert (ovf);
            if ($past(clr)) begin
                assert (acc == 0);
                assert (ovf == 0);
                assert (a0_out == 0 && a1_out == 0 && w_out == 0);
            end
            if (!$past(clr) && !$past(en))
                assert (acc == $past(acc) && ovf == $past(ovf) && a0_out == $past(a0_out));
        end
    end
endmodule
