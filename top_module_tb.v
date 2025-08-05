`timescale 1ns / 1ps

module top_module_tb;

    
    // Testbench parameters (P_)
    
    //50Hz system clock
    parameter P_SYS_CLK_PERIOD = 20;

    //10 kHz (100us period) tick frequency
    parameter P_TICK_FREQ_HZ = 10000;

    //15 ms debounce time
    parameter P_DEBOUNCE_TIME_MS = 15;

    //scans all 8 rows. 
    parameter P_SCAN_TIMEOUT_CYCLES = 16;


    //constants (C_) for DUT configuration
    //Change P_ values and C_ values will change themselves.
    //value for clk_divider_limit_i to achieve the desired tick frequency.
    localparam C_CLK_DIV_LIMIT = (50_000_000 / P_TICK_FREQ_HZ) - 1;

    //value for debounce_limit_i to achieve the desired debounce time.
    localparam C_DEBOUNCE_LIMIT = (P_DEBOUNCE_TIME_MS * P_TICK_FREQ_HZ / 1000) - 1;

    //value for scan_timeout_limit_i
    localparam C_SCAN_TIMEOUT_LIMIT = P_SCAN_TIMEOUT_CYCLES - 1;

    
    //signal declarations

    //system clock and reset
    reg system_clk_i;
    reg system_rst_n_i;

    //configuration inputs
    reg [19:0] clk_divider_limit_i;
    reg [7:0]  debounce_limit_i;
    reg [3:0]  scan_timeout_limit_i;

    //keypad matrix
    reg  [7:0] keypad_matrix [0:7];
    wire [7:0] keypad_columns_i;
    wire [7:0] keypad_rows_o;

    //FIFO Interface
    wire       fifo_write_enable_o;
    wire [5:0] key_position_data_o;
    wire [7:0] key_ascii_data_o;
    reg        position_fifo_full_i;
    reg        keycode_fifo_full_i;

    //status outputs
    wire       key_press_interrupt_o;
    wire [1:0] controller_state_o;
    wire       key_detected_flag_o;
    wire       debounce_active_flag_o;

    
    //DUT Instantiation
    top_module #(
        .CLK_DIV_WIDTH(20),
        .DEBOUNCE_WIDTH(8),
        .SCAN_TIMEOUT_WIDTH(4)
    ) uut (
        .system_clk_i(system_clk_i),
        .system_rst_n_i(system_rst_n_i),
        .clk_divider_limit_i(clk_divider_limit_i),
        .debounce_limit_i(debounce_limit_i),
        .scan_timeout_limit_i(scan_timeout_limit_i),
        .keypad_columns_i(keypad_columns_i),
        .keypad_rows_o(keypad_rows_o),
        .fifo_write_enable_o(fifo_write_enable_o),
        .key_position_data_o(key_position_data_o),
        .key_ascii_data_o(key_ascii_data_o),
        .position_fifo_full_i(position_fifo_full_i),
        .keycode_fifo_full_i(keycode_fifo_full_i),
        .key_press_interrupt_o(key_press_interrupt_o),
        .controller_state_o(controller_state_o),
        .key_detected_flag_o(key_detected_flag_o),
        .debounce_active_flag_o(debounce_active_flag_o)
    );


    // cclock and reset generation
    initial begin
        system_clk_i = 0;
        forever #(P_SYS_CLK_PERIOD / 2) system_clk_i = ~system_clk_i;
    end

    initial begin
        system_rst_n_i = 1'b0;
        #100;
        system_rst_n_i = 1'b1;
    end


    // Keypad Matrix Simulation
    
    assign keypad_columns_i = (keypad_rows_o[0] === 1'b0) ? keypad_matrix[0] : 8'hFF &
                              (keypad_rows_o[1] === 1'b0) ? keypad_matrix[1] : 8'hFF &
                              (keypad_rows_o[2] === 1'b0) ? keypad_matrix[2] : 8'hFF &
                              (keypad_rows_o[3] === 1'b0) ? keypad_matrix[3] : 8'hFF &
                              (keypad_rows_o[4] === 1'b0) ? keypad_matrix[4] : 8'hFF &
                              (keypad_rows_o[5] === 1'b0) ? keypad_matrix[5] : 8'hFF &
                              (keypad_rows_o[6] === 1'b0) ? keypad_matrix[6] : 8'hFF &
                              (keypad_rows_o[7] === 1'b0) ? keypad_matrix[7] : 8'hFF;

    // task to press a key
    task press_key;
        input [2:0] row;
        input [2:0] col;
        begin
            $display("[%0t] TB: Pressing key at (Row: %d, Col: %d)", $time, row, col); 
            keypad_matrix[row] = ~(8'h01 << col); //0 is key press
        end
    endtask

    //task to release all keys
    task release_all_keys;
        integer i;
        begin
            $display("[%0t] TB: Releasing all keys.", $time);
            for (i = 0; i < 8; i = i + 1) begin
                keypad_matrix[i] = 8'hFF;
            end
        end
    endtask

    
    //test sequence
    
    initial begin
        //initialize all inputs
        clk_divider_limit_i  = C_CLK_DIV_LIMIT;
        debounce_limit_i     = C_DEBOUNCE_LIMIT;
        scan_timeout_limit_i = C_SCAN_TIMEOUT_LIMIT;
        position_fifo_full_i = 1'b0;
        keycode_fifo_full_i  = 1'b0;
        release_all_keys();

        //wait for the reset to finish
        @(posedge system_rst_n_i);
        #100;

        //TEST 1: Clean key press
        $display("\nTEST 1: Clean key press");
        press_key(2, 5); //Pressed U key
        #(P_DEBOUNCE_TIME_MS * 1_000_000); //hold for longer than debounce time
        release_all_keys();
        #10000;

        //TEST 2: Key released during debounce
        $display("\nTEST 2: Key released during Debounce");
        press_key(1, 1); // Pressed key 9
        #(P_DEBOUNCE_TIME_MS / 2 * 1_000_000);        //hold for half the debounce time
        release_all_keys();                           //release before debounce finishes
        #(P_DEBOUNCE_TIME_MS * 1_000_000);            // Wait to ensure no key was written
        #10000;

        //TEST 3: scan timeou
        $display("\nTEST 3: Scan timeout");
        press_key(4, 3); // Pressed K key 
        #100;            // Press for a very short time
        release_all_keys();
        #(P_SCAN_TIMEOUT_CYCLES * 100 * 1000 * 2); // Wait long enough for timeout
        #10000;

        //TEST 4: FIFO Full condition
        $display("\nTEST 4: FIFO full condition");
        position_fifo_full_i = 1'b1;        //FIFO is full
        keycode_fifo_full_i  = 1'b1;
        press_key(0, 0); // Pressed ESC
        #(P_DEBOUNCE_TIME_MS * 1_000_000); //hold for longer than debounce time
        release_all_keys();
        position_fifo_full_i = 1'b0; //FIFO available again
        keycode_fifo_full_i  = 1'b0;
        #10000;

        $display("\nAll tests complete.");
        $finish;
    end

    
    //monitor and verification Logic
    
    always @(posedge fifo_write_enable_o) begin
        $display("[%0t] MONITOR: Key captured!", $time);
        $display("    - Controller State: %b", controller_state_o);
        $display("    - Position (Row, Col): {%d, %d}", key_position_data_o[5:3], key_position_data_o[2:0]);
        $display("    - ASCII: 0x%h ('%c')", key_ascii_data_o, key_ascii_data_o);
    end

endmodule

