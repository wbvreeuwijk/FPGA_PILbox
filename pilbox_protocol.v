module pilbox_protocol (
    input  wire clk,
    input  wire reset,

    // UART RX
    input  wire [7:0] uart_rx_data,
    input  wire       uart_rx_valid,

    // UART TX
    output reg  [7:0] uart_tx_data,
    output reg        uart_tx_start,
    input  wire       uart_tx_busy,

    // HPIL Link Layer RX
    input  wire       hpil_rx_valid,
    input  wire [2:0] hpil_rx_ctrl,
    input  wire [7:0] hpil_rx_data,

    // HPIL Link Layer TX
    output reg        hpil_tx_start,
    output reg  [2:0] hpil_tx_ctrl,
    output reg  [7:0] hpil_tx_data,
    input  wire       hpil_tx_busy
);

    reg [7:0] rx_lasth;
    reg [7:0] tx_lasth;
    
    // UART TX Queue (16 bytes, implemented in registers)
    reg [7:0] tx_queue [0:15];
    reg [3:0] tx_queue_head;
    reg [3:0] tx_queue_tail;
    
    reg cofi_enabled;
    
    localparam CMD_COFF = 11'h497;
    localparam CMD_COFI = 11'h495;
    localparam CMD_TDIS = 11'h494;

    wire [10:0] hpil_rx_frame = {hpil_rx_ctrl, hpil_rx_data};
    wire [7:0] hpil_rx_hbyt = ((hpil_rx_frame >> 6) & 8'h1E) | 8'h20;
    wire [7:0] hpil_rx_lbyt = (hpil_rx_frame & 8'h7F) | 8'h80;

    wire [10:0] decoded_frame_8bit = ((rx_lasth & 11'h1E) << 6) | (uart_rx_data & 11'h7F);
    wire [10:0] decoded_frame_7bit = ((rx_lasth & 11'h1F) << 6) | (uart_rx_data & 11'h3F);
    wire [10:0] decoded_frame = uart_rx_data[7] ? decoded_frame_8bit : decoded_frame_7bit;

    reg [10:0] pending_hpil_tx;
    reg hpil_tx_pending;

    always @(posedge clk) begin
        if (reset) begin
            rx_lasth <= 0;
            tx_lasth <= 0;
            tx_queue_head <= 0;
            tx_queue_tail <= 0;
            uart_tx_start <= 0;
            hpil_tx_start <= 0;
            hpil_tx_pending <= 0;
            cofi_enabled <= 0;
        end else begin
            uart_tx_start <= 0;
            hpil_tx_start <= 0;
            
            // Handle UART TX dispatch
            if (tx_queue_head != tx_queue_tail && !uart_tx_busy && !uart_tx_start) begin
                uart_tx_data <= tx_queue[tx_queue_tail];
                uart_tx_start <= 1;
                tx_queue_tail <= tx_queue_tail + 4'd1;
            end
            
            // To handle multiple queue pushes in one cycle safely, we use a blocking variable
            begin : queue_logic
                reg [3:0] next_head;
                next_head = tx_queue_head;

                if (hpil_rx_valid) begin
                    // IDY is 3'b111. Auto-forward if COFI is disabled.
                    if (hpil_rx_ctrl == 3'b111 && !cofi_enabled) begin
                        if (!hpil_tx_pending) begin
                            hpil_tx_pending <= 1;
                            pending_hpil_tx <= hpil_rx_frame;
                        end
                    end else begin
                        if (hpil_rx_hbyt != tx_lasth) begin
                            tx_lasth <= hpil_rx_hbyt;
                            tx_queue[next_head] <= hpil_rx_hbyt;
                            tx_queue[next_head + 4'd1] <= hpil_rx_lbyt;
                            next_head = next_head + 4'd2;
                        end else begin
                            tx_queue[next_head] <= hpil_rx_lbyt;
                            next_head = next_head + 4'd1;
                        end
                    end
                end

                if (uart_rx_valid) begin
                    if ((uart_rx_data & 8'hE0) == 8'h20) begin
                        rx_lasth <= uart_rx_data;
                    end else if ((uart_rx_data & 8'hC0) != 0) begin
                        if (decoded_frame == CMD_COFF) begin
                            cofi_enabled <= 0;
                            tx_queue[next_head] <= uart_rx_data;
                            next_head = next_head + 4'd1;
                        end else if (decoded_frame == CMD_COFI) begin
                            cofi_enabled <= 1;
                            tx_queue[next_head] <= uart_rx_data;
                            next_head = next_head + 4'd1;
                        end else if (decoded_frame == CMD_TDIS) begin
                            tx_queue[next_head] <= uart_rx_data;
                            next_head = next_head + 4'd1;
                        end else begin
                            hpil_tx_pending <= 1;
                            pending_hpil_tx <= decoded_frame;
                        end
                    end
                end
                
                tx_queue_head <= next_head;
            end

            // Dispatch to HPIL
            if (hpil_tx_pending && !hpil_tx_busy && !hpil_tx_start) begin
                hpil_tx_ctrl <= pending_hpil_tx[10:8];
                hpil_tx_data <= pending_hpil_tx[7:0];
                hpil_tx_start <= 1;
                hpil_tx_pending <= 0;
            end
        end
    end
endmodule
