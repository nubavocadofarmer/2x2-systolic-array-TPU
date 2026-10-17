`timescale 1ns/1ps

module tb_os_array;
    logic clk = 0;
    logic clr = 0;
    logic en = 0;
    logic mode = 0;
    logic [15:0] a0_left = 0, a1_left = 0, w_top = 0;
    logic [3:0] rd_addr = 0;
    logic [7:0] rd_data;
    logic ovf;

    int sums [0:1][0:1];
    int saved_a0 [0:1][0:1];
    int saved_a1 [0:1][0:1];
    int saved_w [0:1][0:1];
    bit flags [0:1][0:1];
    int matrix_a [0:1][0:9];
    int matrix_w [0:9][0:1];
    int n_steps = 0;
    int n_bytes = 0;
    int n_matrices = 0;
    int random_mode, random_enable;
    logic [15:0] random_a0, random_a1, random_w;

    os_array dut (.*);

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

    task automatic check_readout();
        int address, expected_byte;
        bit expected_ovf;
        expected_ovf = flags[0][0] | flags[0][1] | flags[1][0] | flags[1][1];
        if (ovf !== expected_ovf)
            $fatal(1, "Step %0d: ovf=%b expected=%b", n_steps, ovf, expected_ovf);
        for (address = 0; address < 16; address++) begin
            rd_addr = 4'(address);
            #1;
            expected_byte = 0;
            if (address < 12)
                expected_byte = (sums[(address/3)/2][(address/3)%2] >> (8*(address%3))) & 255;
            if (rd_data !== 8'(expected_byte))
                $fatal(1, "Step %0d address %0d: byte=%02h expected=%02h",
                       n_steps, address, rd_data, 8'(expected_byte));
            n_bytes++;
        end
    endtask

    task automatic step(bit clear_value, bit enable_value, bit mode_value,
                        logic [15:0] lane0, logic [15:0] lane1, logic [15:0] weights);
        int row, col, a0, a1, weight, total;
        clk = 0;
        clr = clear_value;
        en = enable_value;
        mode = mode_value;
        a0_left = lane0;
        a1_left = lane1;
        w_top = weights;
        #5;

        if (clear_value) begin
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
        else if (enable_value) begin
            for (row = 1; row >= 0; row--) begin
                for (col = 1; col >= 0; col--) begin
                    if (col == 0) begin
                        a0 = int'($signed(lane0[row*8 +: 8]));
                        a1 = int'($signed(lane1[row*8 +: 8]));
                    end
                    else begin
                        a0 = saved_a0[row][col-1];
                        a1 = saved_a1[row][col-1];
                    end
                    if (row == 0) weight = int'($signed(weights[col*8 +: 8]));
                    else weight = saved_w[row-1][col];
                    total = sums[row][col] + product_model(a0, a1, weight, mode_value);
                    if (total > 8388607 || total < -8388608) flags[row][col] = 1;
                    sums[row][col] = total & 16777215;
                    if (sums[row][col] >= 8388608) sums[row][col] -= 16777216;
                    saved_a0[row][col] = a0;
                    saved_a1[row][col] = a1;
                    saved_w[row][col] = weight;
                end
            end
        end

        clk = 1;
        #1;
        n_steps++;
        check_readout();
        clk = 0;
        #4;
    endtask

    task automatic matrix_test(bit packed_mode, int inner_size, bit clear_first);
        int row, col, k, tick, n_inputs, index0, index1;
        int expected [0:1][0:1];
        int lane0 [0:1];
        int lane1 [0:1];
        int weights [0:1];

        if (clear_first) step(1, 0, packed_mode, 0, 0, 0);
        for (row = 0; row < 2; row++) begin
            for (col = 0; col < 2; col++) begin
                expected[row][col] = sums[row][col];
                for (k = 0; k < inner_size; k++)
                    expected[row][col] += matrix_a[row][k] * matrix_w[k][col];
            end
        end

        n_inputs = packed_mode ? (inner_size+1)/2 : inner_size;
        for (tick = 0; tick < n_inputs+2; tick++) begin
            for (row = 0; row < 2; row++) begin
                index0 = packed_mode ? 2*(tick-row) : tick-row;
                index1 = index0 + 1;
                lane0[row] = 0;
                lane1[row] = 0;
                if (index0 >= 0 && index0 < inner_size) lane0[row] = matrix_a[row][index0];
                if (packed_mode && index1 >= 0 && index1 < inner_size) lane1[row] = matrix_a[row][index1];
            end
            for (col = 0; col < 2; col++) begin
                index0 = packed_mode ? 2*(tick-col) : tick-col;
                index1 = index0 + 1;
                weights[col] = 0;
                if (index0 >= 0 && index0 < inner_size) begin
                    if (packed_mode) weights[col] = matrix_w[index0][col] & 15;
                    else weights[col] = matrix_w[index0][col];
                end
                if (packed_mode && index1 >= 0 && index1 < inner_size)
                    weights[col] |= (matrix_w[index1][col] & 15) << 4;
            end

            step(0, 0, packed_mode, 16'h7f80, 16'h807f, 16'h8877);
            step(0, 1, packed_mode, pair_bytes(lane0[0], lane0[1]),
                 pair_bytes(lane1[0], lane1[1]), pair_bytes(weights[0], weights[1]));
        end

        for (row = 0; row < 2; row++)
            for (col = 0; col < 2; col++)
                if (sums[row][col] != expected[row][col])
                    $fatal(1, "Matrix mode=%b K=%0d C[%0d][%0d]=%0d expected=%0d",
                           packed_mode, inner_size, row, col, sums[row][col], expected[row][col]);
        n_matrices++;
    endtask

    initial begin
        step(1, 0, 0, 0, 0, 0);
        matrix_a[0][0] = 1; matrix_a[0][1] = 2;
        matrix_a[1][0] = 3; matrix_a[1][1] = 4;
        matrix_w[0][0] = 5; matrix_w[0][1] = 6;
        matrix_w[1][0] = 7; matrix_w[1][1] = 8;
        matrix_test(0, 2, 1);
        if (sums[0][0] != 19 || sums[0][1] != 22 || sums[1][0] != 43 || sums[1][1] != 50)
            $fatal(1, "Known matrix product failed");

        for (int packed_mode = 0; packed_mode < 2; packed_mode++) begin
            for (int inner_size = 1; inner_size <= 9; inner_size++) begin
                for (int trial = 0; trial < 10; trial++) begin
                    for (int row = 0; row < 2; row++)
                        for (int k = 0; k < inner_size; k++)
                            matrix_a[row][k] = int'($urandom_range(0, 255)) - 128;
                    for (int k = 0; k < inner_size; k++)
                        for (int col = 0; col < 2; col++)
                            matrix_w[k][col] = packed_mode != 0 ? int'($urandom_range(0, 15))-8 : int'($urandom_range(0, 255))-128;
                    matrix_test(packed_mode != 0, inner_size, 1);
                    matrix_test(packed_mode != 0, inner_size, 0);
                end
            end
        end
        $display("PASS: %0d matrix products, odd W4A8 padding, two tail steps, stalls, and accumulation across bursts", n_matrices);

        for (int row = 0; row < 2; row++) begin
            for (int col = 0; col < 2; col++) begin
                step(1, 1, 0, 16'h8080, 0, 16'h8080);
                repeat (514)
                    step(0, 1, 0, row == 0 ? 16'h0080 : 16'h8000,
                         0, col == 0 ? 16'h0080 : 16'h8000);
                if (!ovf || !flags[row][col]) $fatal(1, "Missing overflow at PE(%0d,%0d)", row, col);
                step(0, 0, 0, 0, 0, 0);
                step(0, 1, 0, 0, 0, 0);
                if (!ovf) $fatal(1, "Overflow did not remain sticky");
            end
        end
        step(1, 0, 1, 0, 0, 0);
        repeat (4098) step(0, 1, 1, 16'h8080, 16'h8080, 16'h8888);
        if (!ovf) $fatal(1, "Missing W4A8 array overflow");
        $display("PASS: isolated overflow from each PE, W4A8 overflow, sticky flags, and clear priority");

        step(1, 0, 0, 0, 0, 0);
        repeat (1000) begin
            random_mode = $urandom_range(0, 1);
            random_enable = $urandom_range(0, 1);
            random_a0 = 16'($urandom);
            random_a1 = 16'($urandom);
            random_w = 16'($urandom);
            step(0, random_enable != 0, random_mode != 0, random_a0, random_a1, random_w);
        end
        step(1, 1, 0, 16'h7f7f, 16'h7f7f, 16'h7f7f);
        repeat (3) step(0, 1, 0, 0, 0, 0);
        $display("PASS: %0d clock checks and %0d result-byte checks", n_steps, n_bytes);
        $finish;
    end
endmodule
