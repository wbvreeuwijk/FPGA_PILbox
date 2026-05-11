module uart_rx #(
    parameter CLKS_PER_BIT = 69 // 16MHz / 230400 = ~69.44
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       rx,
    output reg  [7:0] data_out,
    output reg        valid_out
);

    localparam IDLE  = 3'd0;
    localparam START = 3'd1;
    localparam DATA  = 3'd2;
    localparam STOP  = 3'd3;
    
    reg [2:0] state;
    reg [7:0] clk_count;
    reg [2:0] bit_idx;

    // Synchronize RX
    reg rx_s1, rx_sync;
    always @(posedge clk) begin
        rx_s1 <= rx;
        rx_sync <= rx_s1;
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            data_out <= 0;
            valid_out <= 0;
            clk_count <= 0;
            bit_idx <= 0;
        end else begin
            valid_out <= 1'b0; // Default

            case (state)
                default: state <= IDLE;
                IDLE: begin
                    clk_count <= 0;
                    bit_idx <= 0;
                    if (rx_sync == 1'b0) begin
                        state <= START;
                    end
                end

                START: begin
                    if (clk_count == (CLKS_PER_BIT / 2)) begin
                        if (rx_sync == 1'b0) begin
                            clk_count <= 0;
                            state <= DATA;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        data_out[bit_idx] <= rx_sync;
                        if (bit_idx == 7) begin
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                STOP: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        valid_out <= 1'b1;
                        state <= IDLE;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
            endcase
        end
    end
endmodule


module uart_tx #(
    parameter CLKS_PER_BIT = 69 // 16MHz / 230400 = ~69.44
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       start,
    input  wire [7:0] data_in,
    output reg        tx,
    output reg        busy
);

    localparam IDLE  = 3'd0;
    localparam START = 3'd1;
    localparam DATA  = 3'd2;
    localparam STOP  = 3'd3;

    reg [2:0] state;
    reg [7:0] clk_count;
    reg [2:0] bit_idx;
    reg [7:0] tx_data;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            tx <= 1'b1;
            busy <= 1'b0;
            clk_count <= 0;
            bit_idx <= 0;
            tx_data <= 0;
        end else begin
            case (state)
                default: state <= IDLE;
                IDLE: begin
                    tx <= 1'b1;
                    clk_count <= 0;
                    bit_idx <= 0;
                    if (start) begin
                        tx_data <= data_in;
                        busy <= 1'b1;
                        state <= START;
                        tx <= 1'b0;
                    end else begin
                        busy <= 1'b0;
                    end
                end

                START: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        state <= DATA;
                        tx <= tx_data[0];
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        if (bit_idx == 7) begin
                            state <= STOP;
                            tx <= 1'b1;
                        end else begin
                            bit_idx <= bit_idx + 1;
                            tx <= tx_data[bit_idx + 1];
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end

                STOP: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        state <= IDLE;
                        busy <= 1'b0;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
            endcase
        end
    end
endmodule
