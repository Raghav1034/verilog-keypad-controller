module fifo #(
    parameter DATA_WIDTH = 8,
    parameter FIFO_DEPTH = 16,
    parameter ADDR_WIDTH = 4
)(
    input  wire clk_i,
    input  wire rst_n_i,

    // Write Interface
    input  wire wr_en_i,
    input  wire [DATA_WIDTH-1:0] wr_data_i,

    // Read Interface
    input  wire rd_en_i,
    output reg  [DATA_WIDTH-1:0] rd_data_o,

    // Status Outputs
    output wire full_o,
    output wire empty_o,
    output wire [ADDR_WIDTH:0] count_o
);

    // Registers for memory and pointers
    reg [DATA_WIDTH-1:0] memory_r [0:FIFO_DEPTH-1];
    reg [ADDR_WIDTH-1:0] wr_ptr_r;
    reg [ADDR_WIDTH-1:0] rd_ptr_r;
    reg [ADDR_WIDTH:0]   count_r; 

    // Internal valid signals
    wire wr_valid_w = wr_en_i & ~full_o;
    wire rd_valid_w = rd_en_i & ~empty_o;

    // Status flag assignments
    assign full_o  = (count_r == FIFO_DEPTH);
    assign empty_o = (count_r == 0);
    assign count_o = count_r;

    // Write logic: update memory and write pointer
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            wr_ptr_r <= {ADDR_WIDTH{1'b0}};
        end else if (wr_valid_w) begin
            memory_r[wr_ptr_r] <= wr_data_i;
            wr_ptr_r           <= wr_ptr_r + 1'b1;
        end
    end

    // Read logic: update output data and read pointer
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rd_ptr_r  <= {ADDR_WIDTH{1'b0}};
            rd_data_o <= {DATA_WIDTH{1'b0}};
        end else if (rd_valid_w) {
            rd_data_o <= memory_r[rd_ptr_r];
            rd_ptr_r  <= rd_ptr_r + 1'b1;
        end
    end

    // FIFO fill count logic
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            count_r <= 0;
        end else begin
            case ({wr_valid_w, rd_valid_w})
                2'b00:   count_r <= count_r;         // No operation
                2'b01:   count_r <= count_r - 1'b1;  // Read only
                2'b10:   count_r <= count_r + 1'b1;  // Write only
                2'b11:   count_r <= count_r;         // Read and Write, count is stable
                default: count_r <= count_r;
            endcase
        end
    end

endmodule
