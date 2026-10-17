`timescale 1ns/1ps

module tb_host_if;
    import tpu_pkg::*;

    logic clk = 0;
    logic rst_n = 0;
    logic [7:0] data = 0;
    logic [2:0] cmd = CMD_NOP;
    logic valid = 0;
    logic arr_en, arr_clr, mode;
    logic [15:0] a0_left, a1_left, w_top;
    logic [3:0] rd_addr;
    logic [7:0] rd_data;
    logic ovf;

    int ref_data = 0, ref_cmd = 0, ref_count = 0, ref_ptr = 0;
    bit ref_valid = 0, ref_cfg = 0, ref_mode = 0, ref_drain = 0;
    int bytes_in [0:5];
    int skew_a0 = 0, skew_a1 = 0, skew_w = 0;
    int sums [0:1][0:1];
    int saved_a0 [0:1][0:1], saved_a1 [0:1][0:1], saved_w [0:1][0:1];
    bit flags [0:1][0:1];
    int matrix_a [0:1][0:9], matrix_w [0:9][0:1];
    int n_cycles = 0, n_steps = 0, n_matrices = 0;
    int random_cmd, random_valid, random_data;

    host_if dut (.*);
    os_array array_dut (.*,.en(arr_en),.clr(arr_clr));

    function automatic logic [15:0] pair_bytes(int low_value, int high_value);
        return {8'(high_value), 8'(low_value)};
    endfunction

    function automatic int product_model(int a0, int a1, int weight, bit packed_mode);
        int low_weight, high_weight;
        if (!packed_mode) return a0 * weight;
        low_weight = weight & 15;
        high_weight = (weight >> 4) & 15;
        if (low_weight >= 8) low_weight -= 16;
        if (high_weight >= 8) high_weight -= 16;
        return a0 * low_weight + a1 * high_weight;
    endfunction

    task automatic cycle(bit valid_value, logic [2:0] cmd_value, int data_value);
        bit expected_en, expected_clr, arithmetic_mode;
        logic [15:0] raw_a0, raw_a1, raw_w, left_a0, left_a1, top_w;
        int row, col, a0, a1, weight, total, expected_byte;

        clk = 0;
        valid = valid_value;
        cmd = cmd_value;
        data = 8'(data_value);
        #5;

        expected_en = 0;
        expected_clr = !rst_n;
        arithmetic_mode = ref_mode;
        raw_a0 = 0; raw_a1 = 0; raw_w = 0;
        if (rst_n) begin
            if (ref_drain) begin
                expected_en = 1;
                ref_drain = 0;
            end
            else if (ref_valid) begin
                case (ref_cmd)
                    1: begin
                        bytes_in[ref_count] = ref_data;
                        ref_count++;
                        if (ref_count == (ref_mode ? 6 : 4)) begin
                            expected_en = 1;
                            ref_count = 0;
                            if (ref_mode) begin
                                raw_a0 = pair_bytes(bytes_in[0], bytes_in[2]);
                                raw_a1 = pair_bytes(bytes_in[1], bytes_in[3]);
                                raw_w = pair_bytes(bytes_in[4], bytes_in[5]);
                            end
                            else begin
                                raw_a0 = pair_bytes(bytes_in[0], bytes_in[1]);
                                raw_w = pair_bytes(bytes_in[2], bytes_in[3]);
                            end
                        end
                    end
                    2: begin
                        expected_clr = 1;
                        ref_mode = ref_cfg;
                        ref_count = 0;
                    end
                    3: begin
                        expected_en = 1;
                        ref_count = 0;
                        ref_drain = 1;
                    end
                    4: begin
                        ref_cfg = (ref_data & 1) != 0;
                        ref_count = 0;
                    end
                    5: ref_ptr = ref_data & 15;
                    6: ref_ptr = (ref_ptr + 1) & 15;
                    default: begin
                    end
                endcase
            end
        end

        left_a0 = pair_bytes(int'($signed(raw_a0[7:0])), skew_a0);
        left_a1 = pair_bytes(int'($signed(raw_a1[7:0])), skew_a1);
        top_w = pair_bytes(int'($signed(raw_w[7:0])), skew_w);
        if (arr_en !== expected_en || arr_clr !== expected_clr ||
            (n_cycles > 0 && (a0_left !== left_a0 || a1_left !== left_a1 || w_top !== top_w)))
            $fatal(1, "Cycle %0d: step/clear or staged/skewed operands differ from protocol", n_cycles+1);

        if (expected_clr) begin
            skew_a0 = 0; skew_a1 = 0; skew_w = 0;
            for (row = 0; row < 2; row++) begin
                for (col = 0; col < 2; col++) begin
                    sums[row][col] = 0;
                    saved_a0[row][col] = 0;
                    saved_a1[row][col] = 0;
                    saved_w[row][col] = 0;
                    flags[row][col] = 0;
                end
            end
        end
        else if (expected_en) begin
            for (row = 1; row >= 0; row--) begin
                for (col = 1; col >= 0; col--) begin
                    a0 = col == 0 ? int'($signed(left_a0[row*8 +: 8])) : saved_a0[row][col-1];
                    a1 = col == 0 ? int'($signed(left_a1[row*8 +: 8])) : saved_a1[row][col-1];
                    weight = row == 0 ? int'($signed(top_w[col*8 +: 8])) : saved_w[row-1][col];
                    total = sums[row][col] + product_model(a0, a1, weight, arithmetic_mode);
                    if (total > 8388607 || total < -8388608) flags[row][col] = 1;
                    sums[row][col] = total & 16777215;
                    if (sums[row][col] >= 8388608) sums[row][col] -= 16777216;
                    saved_a0[row][col] = a0;
                    saved_a1[row][col] = a1;
                    saved_w[row][col] = weight;
                end
            end
            skew_a0 = int'($signed(raw_a0[15:8]));
            skew_a1 = int'($signed(raw_a1[15:8]));
            skew_w = int'($signed(raw_w[15:8]));
            n_steps++;
        end

        if (!rst_n) begin
            ref_data = 0; ref_cmd = 0; ref_valid = 0;
            ref_cfg = 0; ref_mode = 0; ref_count = 0; ref_ptr = 0; ref_drain = 0;
            for (int i = 0; i < 6; i++) bytes_in[i] = 0;
        end
        else begin
            ref_data = data_value & 255;
            ref_cmd = int'(cmd_value);
            ref_valid = valid_value;
        end

        clk = 1;
        #1;
        n_cycles++;
        if (mode !== ref_mode || rd_addr !== 4'(ref_ptr))
            $fatal(1, "Cycle %0d: mode or pointer changed at wrong edge", n_cycles);
        if (int'(array_dut.acc_00) != sums[0][0] || int'(array_dut.acc_01) != sums[0][1] ||
            int'(array_dut.acc_10) != sums[1][0] || int'(array_dut.acc_11) != sums[1][1])
            $fatal(1, "Cycle %0d: array sums differ from reference", n_cycles);
        if (ovf !== (flags[0][0] | flags[0][1] | flags[1][0] | flags[1][1]))
            $fatal(1, "Cycle %0d: overflow differs from reference", n_cycles);
        expected_byte = 0;
        if (ref_ptr < 12)
            expected_byte = (sums[(ref_ptr/3)/2][(ref_ptr/3)%2] >> (8*(ref_ptr%3))) & 255;
        if (rd_data !== 8'(expected_byte)) $fatal(1, "Cycle %0d: result byte mismatch", n_cycles);
        clk = 0;
        #4;
    endtask

    task automatic send_command(logic [2:0] command_value, int value = 0);
        cycle(1, command_value, value);
    endtask

    task automatic idle(int clocks = 1);
        repeat (clocks) cycle(0, CMD_PUSH, 255);
    endtask

    task automatic drain();
        send_command(CMD_DRAIN);
        idle(2);
    endtask

    task automatic matrix_test(bit packed_mode, int inner_size, bit clear_first);
        int expected [0:1][0:1];
        int w0, w1, old_steps;
        if (clear_first) begin
            send_command(CMD_SET_CFG, int'(packed_mode));
            send_command(CMD_CLEAR);
            idle();
        end
        old_steps = n_steps;
        for (int row = 0; row < 2; row++) begin
            for (int col = 0; col < 2; col++) begin
                expected[row][col] = sums[row][col];
                for (int k = 0; k < inner_size; k++)
                    expected[row][col] += matrix_a[row][k] * matrix_w[k][col];
            end
        end

        for (int k = 0; k < inner_size; k += packed_mode ? 2 : 1) begin
            send_command(CMD_PUSH, matrix_a[0][k]);
            if (packed_mode) send_command(CMD_PUSH, k+1 < inner_size ? matrix_a[0][k+1] : 0);
            send_command(CMD_PUSH, matrix_a[1][k]);
            if (packed_mode) send_command(CMD_PUSH, k+1 < inner_size ? matrix_a[1][k+1] : 0);
            w0 = matrix_w[k][0];
            w1 = matrix_w[k][1];
            if (packed_mode) begin
                w0 &= 15; w1 &= 15;
                if (k+1 < inner_size) begin
                    w0 |= (matrix_w[k+1][0] & 15) << 4;
                    w1 |= (matrix_w[k+1][1] & 15) << 4;
                end
            end
            send_command(CMD_PUSH, w0);
            send_command(CMD_PUSH, w1);
        end
        drain();
        if (n_steps-old_steps != (packed_mode ? (inner_size+1)/2 : inner_size)+2)
            $fatal(1, "Wrong number of array steps");
        for (int row = 0; row < 2; row++)
            for (int col = 0; col < 2; col++)
                if (sums[row][col] != expected[row][col])
                    $fatal(1, "Matrix mode=%b K=%0d C[%0d][%0d]=%0d expected=%0d",
                           packed_mode, inner_size, row, col, sums[row][col], expected[row][col]);
        for (int address = 0; address < 16; address++) begin
            send_command(CMD_RD_PTR, address);
            idle();
        end
        send_command(CMD_RD_NEXT);
        idle();
        if (rd_addr !== 0) $fatal(1, "Read pointer did not wrap");
        n_matrices++;
    endtask

    initial begin
        cycle(1, CMD_PUSH, 99);
        rst_n = 1;
        idle();
        for (int packed_mode = 0; packed_mode < 2; packed_mode++) begin
            for (int inner_size = 1; inner_size <= 9; inner_size++) begin
                for (int trial = 0; trial < 10; trial++) begin
                    for (int row = 0; row < 2; row++)
                        for (int k = 0; k < inner_size; k++)
                            matrix_a[row][k] = int'($urandom_range(0, 255))-128;
                    for (int k = 0; k < inner_size; k++)
                        for (int col = 0; col < 2; col++)
                            matrix_w[k][col] = packed_mode != 0 ? int'($urandom_range(0, 15))-8 : int'($urandom_range(0, 255))-128;
                    matrix_test(packed_mode != 0, inner_size, 1);
                    matrix_test(packed_mode != 0, inner_size, 0);
                end
            end
        end
        $display("PASS: %0d matrix products, staging, skew, back-to-back commands, odd padding, bursts, and read timing", n_matrices);

        send_command(CMD_SET_CFG, 0);
        send_command(CMD_CLEAR);
        idle();
        for (int partial = 1; partial < 4; partial++) begin
            repeat (partial) send_command(CMD_PUSH, 127);
            drain();
            matrix_test(0, 3, 0);
        end
        send_command(CMD_PUSH, 77);
        send_command(CMD_SET_CFG, 1);
        idle();
        if (mode !== 0) $fatal(1, "SET_CFG changed active mode before CLEAR");
        matrix_test(0, 3, 0);
        send_command(CMD_CLEAR);
        idle();
        if (mode !== 1) $fatal(1, "CLEAR did not apply pending mode");
        for (int partial = 1; partial < 6; partial++) begin
            repeat (partial) send_command(CMD_PUSH, 127);
            drain();
            matrix_test(1, 3, 0);
        end
        $display("PASS: partial DRAIN in both modes and SET_CFG discarding partial staging without applying mode");

        repeat (10000) begin
            if (ref_drain || (ref_valid && ref_cmd == 3)) idle();
            else begin
                random_cmd = int'($urandom_range(0, 7));
                random_valid = int'($urandom_range(0, 1));
                random_data = int'($urandom_range(0, 255));
                if (random_cmd == 4) random_data &= 1;
                cycle(random_valid != 0, 3'(random_cmd), random_data);
            end
        end
        idle(3);
        send_command(CMD_PUSH, 127);
        send_command(CMD_DRAIN);
        rst_n = 0;
        cycle(1, CMD_SET_CFG, 1);
        rst_n = 1;
        idle(3);
        if (mode !== 0 || rd_addr !== 0 || ovf !== 0) $fatal(1, "Reset did not clear state");
        $display("PASS: 10000 random command cycles, reserved NOP, VALID-low gaps, and reset during pending work");
        $display("PASS: %0d cycle checks and %0d array steps", n_cycles, n_steps);
        $finish;
    end
endmodule
