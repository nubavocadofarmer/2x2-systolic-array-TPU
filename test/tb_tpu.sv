`timescale 1ns/1ps

module tb_tpu;
    import tpu_pkg::*;

    logic [7:0] ui_in = 0;
    logic [7:0] uo_out;
    logic [7:0] uio_in = 0;
    logic [7:0] uio_out, uio_oe;
    logic ena = 1;
    logic clk = 0;
    logic rst_n = 0;
    bit single_step = 0;

    int matrix_a [0:1][0:8], matrix_w [0:8][0:1];
    int expected [0:1][0:1];
    int n_cycles = 0, n_results = 0, n_matrices = 0;
    int saved_value;

    tt_um_nubavocadofarmer_systolic_tpu dut (.*);

    task automatic cycle(bit valid_value, logic [2:0] command_value, int data_value = 0);
        clk = 0;
        ui_in = 8'(data_value);
        uio_in = {4'($urandom), valid_value, command_value};
        ena = 1'($urandom);
        if (single_step) begin
            repeat ($urandom_range(1, 10)) #10;
        end
        #5;
        clk = 1;
        #1;
        n_cycles++;
        if (uio_oe !== 8'h40 || (uio_out & 8'hbf) !== 0)
            $fatal(1, "Cycle %0d: incorrect Tiny Tapeout pin mapping", n_cycles);
        #4;
        clk = 0;
    endtask

    task automatic send_command(logic [2:0] command_value, int value = 0);
        cycle(1, command_value, value);
    endtask

    task automatic idle(int clocks = 1);
        repeat (clocks) cycle(0, CMD_PUSH, 255);
    endtask

    task automatic configure(bit packed_mode);
        send_command(CMD_SET_CFG, int'(packed_mode));
        send_command(CMD_CLEAR);
        idle();
        for (int row = 0; row < 2; row++)
            for (int col = 0; col < 2; col++) expected[row][col] = 0;
        if (uio_out[6] !== 0) $fatal(1, "CLEAR did not reset OVF");
    endtask

    task automatic drain();
        send_command(CMD_DRAIN);
        idle(2);
    endtask

    task automatic check_results(bit expected_overflow = 0);
        int expected_byte, index, byte_index;
        send_command(CMD_RD_PTR, 0);
        idle();
        for (int address = 0; address < 16; address++) begin
            expected_byte = 0;
            if (address < 12) begin
                index = address/3;
                byte_index = address%3;
                expected_byte = (expected[index/2][index%2] >> (8*byte_index)) & 255;
            end
            if (uo_out !== 8'(expected_byte))
                $fatal(1, "Result address %0d: got=%02h expected=%02h", address, uo_out, 8'(expected_byte));
            if (uio_out[6] !== expected_overflow) $fatal(1, "Incorrect OVF at result address %0d", address);
            n_results++;
            send_command(CMD_RD_NEXT);
            idle();
        end
        if (uo_out !== 8'(expected[0][0])) $fatal(1, "RD_NEXT did not wrap to address 0");
        for (int address = 15; address >= 0; address--) begin
            send_command(CMD_RD_PTR, address);
            idle();
            expected_byte = 0;
            if (address < 12)
                expected_byte = (expected[(address/3)/2][(address/3)%2] >> (8*(address%3))) & 255;
            if (uo_out !== 8'(expected_byte)) $fatal(1, "RD_PTR address %0d mismatch", address);
            n_results++;
        end
    endtask

    task automatic matrix_test(bit packed_mode, int inner_size);
        int w0, w1;
        for (int row = 0; row < 2; row++)
            for (int col = 0; col < 2; col++)
                for (int k = 0; k < inner_size; k++)
                    expected[row][col] += matrix_a[row][k] * matrix_w[k][col];

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
        check_results();
        n_matrices++;
    endtask

    task automatic extreme_step(bit packed_mode);
        send_command(CMD_PUSH, -128);
        if (packed_mode) send_command(CMD_PUSH, -128);
        send_command(CMD_PUSH, -128);
        if (packed_mode) send_command(CMD_PUSH, -128);
        send_command(CMD_PUSH, packed_mode ? -120 : -128);
        send_command(CMD_PUSH, packed_mode ? -120 : -128);
    endtask

    initial begin
        cycle(1, CMD_PUSH, 99);
        rst_n = 1;
        idle();

        for (int clock_style = 0; clock_style < 2; clock_style++) begin
            single_step = clock_style != 0;
            for (int packed_mode = 0; packed_mode < 2; packed_mode++) begin
                for (int inner_size = 1; inner_size <= 9; inner_size++) begin
                    for (int trial = 0; trial < 10; trial++) begin
                        for (int row = 0; row < 2; row++)
                            for (int k = 0; k < inner_size; k++)
                                matrix_a[row][k] = int'($urandom_range(0, 255))-128;
                        for (int k = 0; k < inner_size; k++)
                            for (int col = 0; col < 2; col++)
                                matrix_w[k][col] = packed_mode != 0 ? int'($urandom_range(0, 15))-8 : int'($urandom_range(0, 255))-128;
                        configure(packed_mode != 0);
                        matrix_test(packed_mode != 0, inner_size);
                        matrix_test(packed_mode != 0, inner_size);
                    end
                end
            end
        end
        $display("PASS: %0d pin-level matrix products, both modes and clock styles, odd padding, bursts, and readout", n_matrices);

        saved_value = int'(uo_out);
        idle(5);
        send_command(CMD_RSVD, 255);
        send_command(CMD_NOP, 255);
        idle();
        if (uo_out !== 8'(saved_value)) $fatal(1, "Idle/NOP/reserved command changed the result");

        for (int packed_mode = 0; packed_mode < 2; packed_mode++) begin
            configure(packed_mode != 0);
            repeat (packed_mode != 0 ? 4095 : 511) extreme_step(packed_mode != 0);
            drain();
            for (int row = 0; row < 2; row++)
                for (int col = 0; col < 2; col++)
                    expected[row][col] = packed_mode != 0 ? 8386560 : 8372224;
            check_results(0);
            extreme_step(packed_mode != 0);
            drain();
            for (int row = 0; row < 2; row++)
                for (int col = 0; col < 2; col++) expected[row][col] = -8388608;
            check_results(1);
            idle(5);
            check_results(1);
            configure(packed_mode != 0);
            check_results(0);
        end
        $display("PASS: INT8 511/512 and W4A8 4095/4096 step boundaries, sticky OVF, and CLEAR");

        send_command(CMD_PUSH, 127);
        send_command(CMD_SET_CFG, 1);
        rst_n = 0;
        cycle(1, CMD_PUSH, 127);
        rst_n = 1;
        idle(3);
        for (int row = 0; row < 2; row++)
            for (int col = 0; col < 2; col++) expected[row][col] = 0;
        check_results(0);
        matrix_a[0][0] = 2; matrix_a[1][0] = -3;
        matrix_w[0][0] = 5; matrix_w[0][1] = -7;
        matrix_test(0, 1);
        $display("PASS: reset restores INT8 and clears pending work");
        $display("PASS: %0d pin-level cycles, %0d result-byte checks", n_cycles, n_results);
        $finish;
    end
endmodule
