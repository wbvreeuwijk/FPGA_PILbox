module pilbox_top (
    input  wire clk_16mhz, // 16MHz clock from TinyFPGA BX

    // UART connected to external USB-to-Serial adapter
    input  wire uart_rx,
    output wire uart_tx,

    // HP-IL Physical Interface
    input  wire hpil_rx_p,
    input  wire hpil_rx_n,
    output wire hpil_tx_p,
    output wire hpil_tx_n,
    
    // Status LED
    output wire led
);

    // Reset generator (simple power-on reset)
    reg [7:0] reset_cnt = 0;
    wire reset = (reset_cnt != 8'hFF);
    always @(posedge clk_16mhz) begin
        if (!reset)
            reset_cnt <= reset_cnt;
        else
            reset_cnt <= reset_cnt + 1;
    end

    // --- UART Modules ---
    wire [7:0] rx_data;
    wire       rx_valid;
    
    wire [7:0] tx_data;
    wire       tx_start;
    wire       tx_busy;

    uart_rx #(
        .CLKS_PER_BIT(69) // 230400 baud at 16MHz
    ) u_uart_rx (
        .clk(clk_16mhz),
        .reset(reset),
        .rx(uart_rx),
        .data_out(rx_data),
        .valid_out(rx_valid)
    );

    uart_tx #(
        .CLKS_PER_BIT(69) // 230400 baud at 16MHz
    ) u_uart_tx (
        .clk(clk_16mhz),
        .reset(reset),
        .start(tx_start),
        .data_in(tx_data),
        .tx(uart_tx),
        .busy(tx_busy)
    );

    // --- HP-IL Link Layer ---
    wire       hpil_rx_valid_sig;
    wire [2:0] hpil_rx_ctrl_sig;
    wire [7:0] hpil_rx_data_sig;

    wire       hpil_tx_start_sig;
    wire [2:0] hpil_tx_ctrl_sig;
    wire [7:0] hpil_tx_data_sig;
    wire       hpil_tx_busy_sig;

    hpil_link_layer u_hpil_link (
        .clk_16mhz(clk_16mhz),
        .reset(reset),

        .rx_p(hpil_rx_p),
        .rx_n(hpil_rx_n),
        .tx_p(hpil_tx_p),
        .tx_n(hpil_tx_n),

        .frame_rx_valid(hpil_rx_valid_sig),
        .frame_rx_ctrl(hpil_rx_ctrl_sig),
        .frame_rx_data(hpil_rx_data_sig),

        .frame_tx_start(hpil_tx_start_sig),
        .frame_tx_ctrl(hpil_tx_ctrl_sig),
        .frame_tx_data(hpil_tx_data_sig),
        .frame_tx_busy(hpil_tx_busy_sig)
    );

    // --- PILbox Protocol State Machine ---
    pilbox_protocol u_protocol (
        .clk(clk_16mhz),
        .reset(reset),

        .uart_rx_data(rx_data),
        .uart_rx_valid(rx_valid),

        .uart_tx_data(tx_data),
        .uart_tx_start(tx_start),
        .uart_tx_busy(tx_busy),

        .hpil_rx_valid(hpil_rx_valid_sig),
        .hpil_rx_ctrl(hpil_rx_ctrl_sig),
        .hpil_rx_data(hpil_rx_data_sig),

        .hpil_tx_start(hpil_tx_start_sig),
        .hpil_tx_ctrl(hpil_tx_ctrl_sig),
        .hpil_tx_data(hpil_tx_data_sig),
        .hpil_tx_busy(hpil_tx_busy_sig)
    );

    // Pulse LED on UART RX for debug
    reg [19:0] led_timer;
    always @(posedge clk_16mhz) begin
        if (reset) begin
            led_timer <= 0;
        end else if (rx_valid) begin
            led_timer <= 20'd1000000; // ~62ms
        end else if (led_timer > 0) begin
            led_timer <= led_timer - 1;
        end
    end
    assign led = (led_timer > 0);

endmodule
