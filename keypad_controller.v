`timescale 1ns / 1ps 
//===========================================================================
 === 
// Keypad Controller  
//===========================================================================
 === 
//===========================================================================
 === 
 
module keypad_controller #( 
    // Width of the clock divider counter. 20 bits for up to 1MHz -> 1ms tick. 
    parameter CLK_DIV_WIDTH = 20, 
    // Width of debounce counter  
    parameter DEBOUNCE_WIDTH = 8, 
    // Width of scan timeout counter  
    parameter SCAN_TIMEOUT_WIDTH = 4 
)( 
    // System Interfaces 
    input  wire                            system_clk_i, 
    input  wire                            system_rst_n_i, 
 
    // Configuration from APB Slave (Runtime Adjustable) 
    // clk_divider_limit should be programmed to (f_sys_clk_hz / 1000) - 1 
    input  wire [CLK_DIV_WIDTH-1:0]        clk_divider_limit_i, 
    // debounce_limit should be programmed to desired debounce time in ms - 1 
    input  wire [DEBOUNCE_WIDTH-1:0]       debounce_limit_i, 
    // scan_timeout_limit should be programmed to number of rows - 1  
    input  wire [SCAN_TIMEOUT_WIDTH-1:0]   scan_timeout_limit_i, 
 
    // Keypad Matrix Interface 
    input  wire [7:0]                      keypad_columns_i, 
    output reg  [7:0]                      keypad_rows_o, 
 
    // FIFO Interface Outputs 
    output wire                            fifo_write_enable_o, 
    output wire [5:0]                      key_position_data_o, 
    output wire [7:0]                      key_ascii_data_o, 
 
    // FIFO Status Inputs 
    input  wire                            position_fifo_full_i, 
    input  wire                            keycode_fifo_full_i, 
 
    // Status and Control Outputs 
    output wire                            key_press_interrupt_o, 
    output wire [1:0]                      controller_state_o, 
    output wire                            key_detected_flag_o, 
    output wire                            debounce_active_flag_o 
); 
//===========================================================================
 === 
// FSM State Definitions 
//===========================================================================
 === 
localparam [1:0] STATE_SLEEP    = 2'b00; 
localparam [1:0] STATE_SCAN     = 2'b01; 
localparam [1:0] STATE_DEBOUNCE = 2'b10; 
localparam [1:0] STATE_STORE    = 2'b11; 
//===========================================================================
 === 
// Internal Registers 
//===========================================================================
 === 
reg [CLK_DIV_WIDTH-1:0]        
clk_div_counter_r; 
reg [DEBOUNCE_WIDTH-1:0]       debounce_counter_r; 
reg [SCAN_TIMEOUT_WIDTH-1:0]   scan_tick_counter_r; 
reg [2:0]                      
row_counter_r; 
reg [1:0]                      
reg [2:0]                      
reg [2:0]                      
reg                            
reg                            
current_state_r, next_state_r; 
detected_row_r; 
detected_col_r; 
f
 ifo_write_enable_r; 
key_press_interrupt_r; 
//===========================================================================
 === 
// Internal Wires 
//===========================================================================
 === 
wire      keypad_tick_en; 
wire      any_key_pressed; 
reg [2:0] priority_encoded_column; 
wire      key_still_pressed; 
wire      debounce_finished; 
wire      scan_timeout; 
wire      fifos_ready_for_write; 
//===========================================================================
 === 
// Combinational Logic 
//===========================================================================
 === 
// Generate the 1ms tick from the (variable) system clock 
assign keypad_tick_en = (clk_div_counter_r >= clk_divider_limit_i); 
assign any_key_pressed = (keypad_columns_i != 8'hFF); 
assign debounce_finished = (debounce_counter_r >= debounce_limit_i); 
assign scan_timeout = (scan_tick_counter_r >= scan_timeout_limit_i); 
assign fifos_ready_for_write = ~position_fifo_full_i & ~keycode_fifo_full_i; 
assign key_still_pressed = ~keypad_columns_i[detected_col_r]; 
 
// Priority Encoder for column detection 
always @(*) begin 
    if      (~keypad_columns_i[0]) priority_encoded_column = 3'b000; 
    else if (~keypad_columns_i[1]) priority_encoded_column = 3'b001; 
    else if (~keypad_columns_i[2]) priority_encoded_column = 3'b010; 
    else if (~keypad_columns_i[3]) priority_encoded_column = 3'b011; 
    else if (~keypad_columns_i[4]) priority_encoded_column = 3'b100; 
    else if (~keypad_columns_i[5]) priority_encoded_column = 3'b101; 
    else if (~keypad_columns_i[6]) priority_encoded_column = 3'b110; 
    else if (~keypad_columns_i[7]) priority_encoded_column = 3'b111; 
    else                           priority_encoded_column = 3'b000; 
end 
 
//===========================================================================
 === 
// Tick Generator (Clock Divider) 
//===========================================================================
 === 
always @(posedge system_clk_i or negedge system_rst_n_i) begin 
    if (!system_rst_n_i) begin 
        clk_div_counter_r <= {CLK_DIV_WIDTH{1'b0}}; 
    end else if (keypad_tick_en) begin 
        clk_div_counter_r <= {CLK_DIV_WIDTH{1'b0}}; 
    end else begin 
        clk_div_counter_r <= clk_div_counter_r + 1; 
    end 
end 
 
//===========================================================================
 === 
// FSM Next State Logic 
//===========================================================================
 === 
always @(*) begin 
    next_state_r = current_state_r; 
    case (current_state_r) 
        STATE_SLEEP: begin 
            if (any_key_pressed) begin 
                next_state_r = STATE_SCAN; 
            end 
        end 
        STATE_SCAN: begin 
            if (any_key_pressed) begin 
                next_state_r = STATE_DEBOUNCE; 
            end else if (scan_timeout) begin 
                next_state_r = STATE_SLEEP; 
            end 
        end 
        STATE_DEBOUNCE: begin 
            if (!key_still_pressed) begin // Key was released prematurely 
                next_state_r = STATE_SLEEP; 
            end else if (debounce_finished) begin 
                if (fifos_ready_for_write) begin 
                    next_state_r = STATE_STORE; 
                end else begin // FIFO full, abort and go to sleep 
                    next_state_r = STATE_SLEEP; 
                end 
            end 
        end 
        STATE_STORE: begin 
            next_state_r = STATE_SLEEP; 
        end 
        default: begin 
            next_state_r = STATE_SLEEP; 
        end 
    endcase 
end 
 
//===========================================================================
 === 
// Main Sequential Logic: FSM, Timers, and Data Registers 
//===========================================================================
 === 
always @(posedge system_clk_i or negedge system_rst_n_i) begin 
    if (!system_rst_n_i) begin 
        // Reset all state 
        current_state_r       <= STATE_SLEEP; 
        row_counter_r         <= 3'h0; 
        scan_tick_counter_r   <= {SCAN_TIMEOUT_WIDTH{1'b0}}; 
        debounce_counter_r    <= {DEBOUNCE_WIDTH{1'b0}}; 
        detected_row_r        <= 3'h0; 
        detected_col_r        <= 3'h0; 
        fifo_write_enable_r   <= 1'b0; 
        key_press_interrupt_r <= 1'b0; 
    end else begin 
        // Default assignments for each cycle 
        current_state_r <= next_state_r; 
        fifo_write_enable_r <= 1'b0; 
        key_press_interrupt_r <= 1'b0; 
 
        // updates only on the keypad tick 
        if (keypad_tick_en) begin 
            // FSM Transitions and Counter Management 
            if (current_state_r == STATE_SLEEP && next_state_r == STATE_SCAN) begin 
                // Entering SCAN: Reset scan counters 
                scan_tick_counter_r <= {SCAN_TIMEOUT_WIDTH{1'b0}}; 
                row_counter_r       <= 3'h0; 
            end 
             
            if (current_state_r == STATE_SCAN && next_state_r == STATE_DEBOUNCE) begin 
                // Entering DEBOUNCE: Capture key and reset debounce counter 
                detected_row_r     <= row_counter_r; 
                detected_col_r     <= priority_encoded_column; 
                debounce_counter_r <= {DEBOUNCE_WIDTH{1'b0}}; 
            end 
 
            // Counter increments based on CURRENT state 
            case (current_state_r) 
                STATE_SCAN: begin 
                    // Continuously scan rows and count towards timeout 
                    if (row_counter_r == 3'h7) begin 
                        row_counter_r <= 3'h0; 
                    end else begin 
                        row_counter_r <= row_counter_r + 1; 
                    end 
                    scan_tick_counter_r <= scan_tick_counter_r + 1; 
                end 
                STATE_DEBOUNCE: begin 
                    // Count towards debounce confirmation 
                    debounce_counter_r <= debounce_counter_r + 1; 
                end 
                STATE_STORE: begin 
                    // Assert write signals for one system clock cycle 
                    fifo_write_enable_r   <= 1'b1; 
                    key_press_interrupt_r <= 1'b1; 
                end 
            endcase 
        end 
         
        // STORE state actions happen immediately (not on tick) 
        if (current_state_r == STATE_STORE) begin 
            fifo_write_enable_r   <= 1'b1; 
            key_press_interrupt_r <= 1'b1; 
        end 
    end 
end 
 
//===========================================================================
 === 
// Row Driver Logic (Combinational) 
//===========================================================================
 === 
always @(*) begin 
    case (current_state_r) 
        STATE_SLEEP:    keypad_rows_o = 8'h00; // Drive all rows low to detect any press 
        STATE_SCAN:     keypad_rows_o = ~(8'h01 << row_counter_r); 
        STATE_DEBOUNCE: keypad_rows_o = ~(8'h01 << detected_row_r); 
        STATE_STORE:    keypad_rows_o = ~(8'h01 << detected_row_r); 
        default:        keypad_rows_o = 8'hFF; 
    endcase 
end 
 
//===========================================================================
 === 
// ASCII Lookup Function (ROM) 
//===========================================================================
 === 
function [7:0] ascii_lookup; 
    input [5:0] key_position; // {row[2:0], col[2:0]} 
    begin 
        case (key_position) 
            // Row 0: Function and Numbers 
            6'b000_000: ascii_lookup = 8'h1B; // ESC 
            6'b000_001: ascii_lookup = 8'h31; // '1' 
            6'b000_010: ascii_lookup = 8'h32; // '2' 
            6'b000_011: ascii_lookup = 8'h33; // '3' 
            6'b000_100: ascii_lookup = 8'h34; // '4' 
            6'b000_101: ascii_lookup = 8'h35; // '5' 
            6'b000_110: ascii_lookup = 8'h36; // '6' 
            6'b000_111: ascii_lookup = 8'h37; // '7' 
 
            // Row 1: QWERTY Row 
            6'b001_000: ascii_lookup = 8'h09; // TAB 
            6'b001_001: ascii_lookup = 8'h51; // 'Q' 
            6'b001_010: ascii_lookup = 8'h57; // 'W' 
            6'b001_011: ascii_lookup = 8'h45; // 'E' 
            6'b001_100: ascii_lookup = 8'h52; // 'R' 
            6'b001_101: ascii_lookup = 8'h54; // 'T' 
            6'b001_110: ascii_lookup = 8'h59; // 'Y' 
            6'b001_111: ascii_lookup = 8'h55; // 'U' 
 
            // Row 2: ASDF Row (Home Row) 
            6'b010_000: ascii_lookup = 8'h14; // CAPS LOCK 
            6'b010_001: ascii_lookup = 8'h41; // 'A' 
            6'b010_010: ascii_lookup = 8'h53; // 'S' 
            6'b010_011: ascii_lookup = 8'h44; // 'D' 
            6'b010_100: ascii_lookup = 8'h46; // 'F' 
            6'b010_101: ascii_lookup = 8'h47; // 'G' 
            6'b010_110: ascii_lookup = 8'h48; // 'H' 
            6'b010_111: ascii_lookup = 8'h4A; // 'J' 
 
            // Row 3: ZXCV Row 
            6'b011_000: ascii_lookup = 8'h10; // LEFT SHIFT 
            6'b011_001: ascii_lookup = 8'h5A; // 'Z' 
            6'b011_010: ascii_lookup = 8'h58; // 'X' 
            6'b011_011: ascii_lookup = 8'h43; // 'C' 
            6'b011_100: ascii_lookup = 8'h56; // 'V' 
            6'b011_101: ascii_lookup = 8'h42; // 'B' 
            6'b011_110: ascii_lookup = 8'h4E; // 'N' 
            6'b011_111: ascii_lookup = 8'h4D; // 'M' 
 
            // Row 4: Bottom Modifiers 
            6'b100_000: ascii_lookup = 8'h11; // LEFT CTRL 
            6'b100_001: ascii_lookup = 8'h91; // WIN KEY 
            6'b100_010: ascii_lookup = 8'h12; // LEFT ALT 
            6'b100_011: ascii_lookup = 8'h20; // SPACE 
            6'b100_100: ascii_lookup = 8'h20; // SPACE (extended) 
            6'b100_101: ascii_lookup = 8'h92; // RIGHT ALT 
            6'b100_110: ascii_lookup = 8'h93; // RIGHT WIN 
            6'b100_111: ascii_lookup = 8'h94; // MENU KEY 
 
            // Row 5: Top Numbers and Symbols 
            6'b101_000: ascii_lookup = 8'h38; // '8' 
            6'b101_001: ascii_lookup = 8'h39; // '9' 
            6'b101_010: ascii_lookup = 8'h30; // '0' 
            6'b101_011: ascii_lookup = 8'h2D; // '-' 
            6'b101_100: ascii_lookup = 8'h3D; // '=' 
            6'b101_101: ascii_lookup = 8'h08; // BACKSPACE 
            6'b101_110: ascii_lookup = 8'h95; // INSERT 
            6'b101_111: ascii_lookup = 8'h96; // HOME 
 
            // Row 6: Punctuation and Navigation 
            6'b110_000: ascii_lookup = 8'h49; // 'I' 
            6'b110_001: ascii_lookup = 8'h4F; // 'O' 
            6'b110_010: ascii_lookup = 8'h50; // 'P' 
            6'b110_011: ascii_lookup = 8'h5B; // '[' 
            6'b110_100: ascii_lookup = 8'h5D; // ']' 
            6'b110_101: ascii_lookup = 8'h5C; // '\' 
            6'b110_110: ascii_lookup = 8'h7F; // DELETE 
            6'b110_111: ascii_lookup = 8'h97; // END 
 
            // Row 7: Punctuation and Navigation 
            6'b111_000: ascii_lookup = 8'h4B; // 'K' 
            6'b111_001: ascii_lookup = 8'h4C; // 'L' 
            6'b111_010: ascii_lookup = 8'h3B; // ';' 
            6'b111_011: ascii_lookup = 8'h27; // ''' 
            6'b111_100: ascii_lookup = 8'h0D; // ENTER 
            6'b111_101: ascii_lookup = 8'h98; // UP ARROW 
            6'b111_110: ascii_lookup = 8'h99; // PAGE UP 
            6'b111_111: ascii_lookup = 8'h9A; // PAGE DOWN 
 
            default: ascii_lookup = 8'h3F; // '?' for any unmapped key 
        endcase 
    end 
endfunction 
 
//===========================================================================
 === 
// Output Assignments 
//===========================================================================
 === 
assign fifo_write_enable_o    = fifo_write_enable_r; 
assign key_press_interrupt_o  = key_press_interrupt_r; 
assign key_position_data_o    = {detected_row_r, detected_col_r}; 
assign key_ascii_data_o       = ascii_lookup({detected_row_r, detected_col_r}); 
assign controller_state_o     = current_state_r; 
assign key_detected_flag_o    = (current_state_r == STATE_SCAN) & any_key_pressed; 
assign debounce_active_flag_o = (current_state_r == STATE_DEBOUNCE); 
 
endmodule