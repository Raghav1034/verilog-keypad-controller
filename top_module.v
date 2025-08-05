`timescale 1ns / 1ps

module top_module(
    // APB Interface
    input           pclk,
    input           presetn,
    input           psel,
    input           penable,
    input   [7:0]   paddr,
    input           pwrite,
    input   [31:0]  pwdata,
    output  [31:0]  prdata,
    output          pready,
    
    //System Interface
    input           system_clk,
    input           system_rst_n,
    
    //Keypad Matrix interface
    input   [7:0]   keypad_columns_i,
    output  [7:0]   keypad_rows_o,
    
    //Interrupt
    output          interrupt_o
);
    
    
    //Configuration Wires from APB Slave to Keypad Controller
    wire [19:0] clk_divider_limit;
    wire [7:0]  debounce_limit;
    wire [3:0]  scan_timeout_limit;
    
    //Keypad Controller to FIFO signals
    wire        fifo_write_enable;
    wire [5:0]  key_position;
    wire [7:0]  key_ascii;
    
    //Position FIFO Signals
    wire        position_fifo_full;
    wire        position_fifo_empty;
    wire [5:0]  position_fifo_data;
    
    // ASCII FIFO Signals
    wire        ascii_fifo_full;
    wire        ascii_fifo_empty;
    wire [7:0]  ascii_fifo_data;
    
    // Controller status
    wire        key_press_interrupt;
    
    // FIFO control
    wire        fifo_read_enable;

    wire        fifos_are_full;
    assign fifos_are_full = position_fifo_full | ascii_fifo_full;

    // Keypad controller instance
    keypad_controller #(
        .CLK_DIV_WIDTH(20),
        .DEBOUNCE_WIDTH(8),
        .SCAN_TIMEOUT_WIDTH(4)
    ) u_keypad_controller (
        .system_clk_i(system_clk),
        .system_rst_n_i(system_rst_n),
        .clk_divider_limit_i(clk_divider_limit),
        .debounce_limit_i(debounce_limit),
        .scan_timeout_limit_i(scan_timeout_limit),
        .keypad_columns_i(keypad_columns_i),
        .keypad_rows_o(keypad_rows_o),
        .fifo_write_enable_o(fifo_write_enable),
        .key_position_data_o(key_position),
        .key_ascii_data_o(key_ascii),
        .position_fifo_full_i(fifos_are_full),
        .keycode_fifo_full_i(fifos_are_full),
        .key_press_interrupt_o(key_press_interrupt)
    );
    
    
    // Position FIFO
    async_fifo #(
        .DATA_WIDTH(6),
        .DEPTH(16),
        .ADDR_WIDTH(4)
    ) u_position_fifo (
        // Write interface (system_clk domain)
        .wclk(system_clk),
        .wrstn_n(system_rst_n),
        .winc(fifo_write_enable),
        .wdata(key_position),
        .wfull(position_fifo_full),
        .wcount(), //not used
        
        // Read interface (pclk domain)
        .rclk(pclk),
        .rrst_n(presetn),
        .rinc(fifo_read_enable),
        .rdata(position_fifo_data),
        .rempty(position_fifo_empty),
        .rcount() //not used
    );
        
        
    // ASCII FIFO
    async_fifo #(
        .DATA_WIDTH(8),
        .DEPTH(16),
        .ADDR_WIDTH(4)
    ) u_ascii_fifo (
        // Write interface (system_clk domain)
        .wclk(system_clk),
        .wrstn_n(system_rst_n),
        .winc(fifo_write_enable),
        .wdata(key_ascii),
        .wfull(ascii_fifo_full),
        .wcount(), //not used
        
        // Read interface (pclk domain)
        .rclk(pclk),
        .rrst_n(presetn),
        .rinc(fifo_read_enable),
        .rdata(ascii_fifo_data),
        .rempty(ascii_fifo_empty),
        .rcount() //not used
    );
        
    // APB Slave interface instance
    APB_Slave u_APB_Slave (
        .pclk(pclk),
        .presetn(presetn),
        .psel(psel),
        .penable(penable),
        .paddr(paddr),
        .pwrite(pwrite),
        .pwdata(pwdata),
        .prdata(prdata),
        .pready(pready),
        .system_clk(system_clk),
        .sys_resetn(system_rst_n),
        .clk_divider_limit_o(clk_divider_limit),
        .debounce_limit_o(debounce_limit),
        .scan_timeout_limit_o(scan_timeout_limit),
        
        // Position FIFO status
        .position_fifo_empty_i(position_fifo_empty),
        .position_fifo_full_i(position_fifo_full),
        .position_fifo_data_i(position_fifo_data),
        
        // ASCII FIFO status
        .ascii_fifo_empty_i(ascii_fifo_empty),
        .ascii_fifo_full_i(ascii_fifo_full),
        .ascii_fifo_data_i(ascii_fifo_data),
        
        // Interrupts
        .key_press_interrupt_i(key_press_interrupt),
        .fifo_read_enable_o(fifo_read_enable),
        .key_press_interrupt_o(interrupt_o)
    );
        
endmodule
