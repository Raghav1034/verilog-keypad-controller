`timescale 1ns / 1ps


module APB_Slave(
    //APB Interface (pclk domain)
    input               pclk,
    input               presetn,
    input               psel,
    input               penable,
    input      [7:0]    paddr,
    input               pwrite,
    input      [31:0]   pwdata,
    output reg [31:0]   prdata,
    output              pready,
    
    //System Interface (system_clk domain)
    input               system_clk,
    input               sys_resetn,
    
    //Configuration outputs (from SoC)
    output reg [19:0]   clk_divider_limit_o,
    output reg [7:0]    debounce_limit_o,
    output reg [3:0]    scan_timeout_limit_o,
    
    //Position FIFO Interface (from FIFO)
    input               position_fifo_empty_i,      
    input               position_fifo_full_i,      
    input      [5:0]    position_fifo_data_i,       
    
    // ASCII FIFO Interface (from FIFO)
    input               ascii_fifo_empty_i,         
    input               ascii_fifo_full_i,          
    input      [7:0]    ascii_fifo_data_i,       
    
    //Controller Status (from keypad_controller in system_clk domain)
    input               key_press_interrupt_i,
    
    //FIFO Control (to FIFO in system_clk domain)
    output              fifo_read_enable_o,
    
    // Interrupt (to Processor in pclk domain)
    output              key_press_interrupt_o   
);
    
    //APB Register Address Map
    parameter REG_CLK_DIV       = 8'h00;
    parameter REG_DEBOUNCE      = 8'h04;
    parameter REG_TIMEOUT       = 8'h08;
    parameter REG_FIFO_STATUS   = 8'h0C;
    parameter REG_INTR_STATUS   = 8'h10;
    parameter REG_POS_DATA      = 8'h14; // Read-only access to FIFO data output
    parameter REG_ASCII_DATA    = 8'h18; // Read-only access to FIFO data output
    parameter REG_CONTROL       = 8'h1C; // Write-only control register


    //Configuration Register Handling (pclk -> system_clk)


    // Shadow registers (pclk domain)
    reg [19:0] clk_div_shadow;
    reg [7:0]  debounce_shadow;
    reg [3:0]  timeout_shadow;
    
    //Handshake logic for safe configuration transfer
    reg        config_valid_pclk;
    wire       config_ack_system_clk;
    reg        config_ack_sync1, config_ack_pclk;

    // APB Write to shadow registers
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            clk_div_shadow  <= 20'd0;
            debounce_shadow <= 8'd0;
            timeout_shadow  <= 4'd0;
            config_valid_pclk <= 1'b0;
        end else begin
            // Set valid flag when a configuration register is written
            if (psel && penable && pwrite) begin
                case(paddr)
                    REG_CLK_DIV:    clk_div_shadow <= pwdata[19:0];
                    REG_DEBOUNCE:   debounce_shadow <= pwdata[7:0];
                    REG_TIMEOUT:    timeout_shadow <= pwdata[3:0];
                endcase
                if (paddr == REG_CLK_DIV || paddr == REG_DEBOUNCE || paddr == REG_TIMEOUT) begin
                    config_valid_pclk <= 1'b1;
                end
            end 
            // Clear valid flag once the system_clk domain acknowledges the transfer
            else if (config_ack_pclk) begin
                config_valid_pclk <= 1'b0;
            end
        end
    end

    // Synchronize valid pulse to system_clk domain
    reg config_valid_sync1, config_valid_system_clk;
    always @(posedge system_clk or negedge sys_resetn) begin
        if (!sys_resetn) begin
            config_valid_sync1      <= 1'b0;
            config_valid_system_clk <= 1'b0;
        end else begin
            config_valid_sync1      <= config_valid_pclk;
            config_valid_system_clk <= config_valid_sync1;
        end
    end

    // Latch configuration in system_clk domain and generate acknowledge
    always @(posedge system_clk or negedge sys_resetn) begin
        if (!sys_resetn) begin
            clk_divider_limit_o  <= 20'd0;
            debounce_limit_o     <= 8'd0;
            scan_timeout_limit_o <= 4'd0;
        end else if (config_valid_system_clk) begin
            // Latch the shadow register values from the pclk domain
            clk_divider_limit_o  <= clk_div_shadow;
            debounce_limit_o     <= debounce_shadow;
            scan_timeout_limit_o <= timeout_shadow;
        end
    end
    assign config_ack_system_clk = config_valid_system_clk;

    // Synchronize acknowledge pulse back to pclk domain
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            config_ack_sync1 <= 1'b0;
            config_ack_pclk  <= 1'b0;
        end else begin
            config_ack_sync1 <= config_ack_system_clk;
            config_ack_pclk  <= config_ack_sync1;
        end
    end


    // Interrupt Handling (system_clk -> pclk)

    reg  intr_flag_system_clk;
    wire intr_clear_pclk = (psel && penable && pwrite && (paddr == REG_CONTROL) && pwdata[0]);
    
    // Synchronize clear signal to system_clk domain
    reg intr_clear_sync1, intr_clear_system_clk;
    always @(posedge system_clk or negedge sys_resetn) begin
        if (!sys_resetn) begin
            intr_clear_sync1      <= 1'b0;
            intr_clear_system_clk <= 1'b0;
        end else begin
            intr_clear_sync1      <= intr_clear_pclk;
            intr_clear_system_clk <= intr_clear_sync1;
        end
    end

    // Latch interrupt flag in system_clk domain
    always @(posedge system_clk or negedge sys_resetn) begin
        if (!sys_resetn) begin
            intr_flag_system_clk <= 1'b0;
        end else if (key_press_interrupt_i) begin
            intr_flag_system_clk <= 1'b1; // Set flag on interrupt pulse
        end else if (intr_clear_system_clk) begin
            intr_flag_system_clk <= 1'b0; // Clear flag on synchronized clear signal
        end
    end

    // Synchronize interrupt flag to pclk domain for CPU to read
    reg intr_flag_sync1, intr_flag_pclk;
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            intr_flag_sync1 <= 1'b0;
            intr_flag_pclk  <= 1'b0;
        end else begin
            intr_flag_sync1 <= intr_flag_system_clk;
            intr_flag_pclk  <= intr_flag_sync1;
        end
    end
    assign key_press_interrupt_o = intr_flag_pclk;


    // FIFO Status Synchronization (system_clk -> pclk)
    //empty flag - pclk domain (no sync needed), full flag - system_clk domain (sync needed).
    reg pos_fifo_full_sync1, pos_fifo_full_pclk;
    reg ascii_fifo_full_sync1, ascii_fifo_full_pclk;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            pos_fifo_full_sync1  <= 1'b0;
            pos_fifo_full_pclk   <= 1'b0;
            ascii_fifo_full_sync1<= 1'b0;
            ascii_fifo_full_pclk <= 1'b0;
        end else begin
            pos_fifo_full_sync1  <= position_fifo_full_i;
            pos_fifo_full_pclk   <= pos_fifo_full_sync1;
            ascii_fifo_full_sync1<= ascii_fifo_full_i;
            ascii_fifo_full_pclk <= ascii_fifo_full_sync1;
        end
    end

  
    // FIFO Read Enable (pclk -> system_clk)

    wire fifo_read_req_pclk = (psel && penable && pwrite && (paddr == REG_CONTROL) && pwdata[1]);

    // Synchronize read request to system_clk domain
    reg fifo_read_req_sync1, fifo_read_req_system_clk;
    always @(posedge system_clk or negedge sys_resetn) begin
        if (!sys_resetn) begin
            fifo_read_req_sync1     <= 1'b0;
            fifo_read_req_system_clk<= 1'b0;
        end else begin
            fifo_read_req_sync1     <= fifo_read_req_pclk;
            fifo_read_req_system_clk<= fifo_read_req_sync1;
        end
    end
    assign fifo_read_enable_o = fifo_read_req_system_clk;


    // APB Read Logic (pclk domain)

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            prdata <= 32'h0;
        end else if (psel && penable && !pwrite) begin
            case(paddr)
                REG_CLK_DIV:     prdata <= {12'h0, clk_div_shadow};
                REG_DEBOUNCE:    prdata <= {24'h0, debounce_shadow};
                REG_TIMEOUT:     prdata <= {28'h0, timeout_shadow};
                REG_FIFO_STATUS: prdata <= {28'h0,
                                            ascii_fifo_full_pclk,
                                            ascii_fifo_empty_i,
                                            pos_fifo_full_pclk,
                                            position_fifo_empty_i};
                REG_INTR_STATUS: prdata <= {31'h0, intr_flag_pclk};
                REG_POS_DATA:    prdata <= {26'h0, position_fifo_data_i};
                REG_ASCII_DATA:  prdata <= {24'h0, ascii_fifo_data_i};
                default:         prdata <= 32'h0;
            endcase
        end else begin
            prdata <= 32'h0;
        end
    end

    // APB ready
    assign pready = 1'b1;
    
endmodule
