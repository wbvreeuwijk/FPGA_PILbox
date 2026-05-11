module hpil_link_layer (
    input  wire clk_16mhz,     // Systeemklok (62.5ns per tik)
    input  wire reset,

    // --- Fysieke Laag: Window Comparator (RX) ---
    input  wire rx_p,          // Hoog bij +1.5V op de loop
    input  wire rx_n,          // Hoog bij -1.5V op de loop

    // --- Fysieke Laag: Direct Drive (TX) ---
    output reg  tx_p,          // Maakt +1.5V op de loop
    output reg  tx_n,          // Maakt -1.5V op de loop

    // --- Interne Bus naar/van de Command Decoder ---
    // Ontvangen
    output reg        frame_rx_valid,
    output reg  [2:0] frame_rx_ctrl, // De 3 control bits (C2, C1, C0)
    output reg  [7:0] frame_rx_data, // De 8 data bits
    
    // Zenden
    input  wire       frame_tx_start,
    input  wire [2:0] frame_tx_ctrl,
    input  wire [7:0] frame_tx_data,
    output reg        frame_tx_busy
);

    // =========================================================
    // RX ONTVANGER LOGICA
    // =========================================================
    
    // 1. Synchronizers voor asynchrone comparatorsignalen
    reg rx_p_s1, rx_p_sync;
    reg rx_n_s1, rx_n_sync;

    always @(posedge clk_16mhz) begin
        rx_p_s1 <= rx_p; rx_p_sync <= rx_p_s1;
        rx_n_s1 <= rx_n; rx_n_sync <= rx_n_s1;
    end

    // Typische HP-IL pulslengtes: ~1us per polariteit (16 kloktikken @ 16MHz)
    // Een Sync bit is ~2us per polariteit (32 kloktikken @ 16MHz).
    // Drempelwaarde voor Sync bit: 1.4us = ~22 kloktikken.
    localparam THRESHOLD_SYNC = 8'd22;

    reg [7:0]  rx_timer;
    reg [3:0]  rx_bit_count;
    reg [10:0] rx_shift_reg;
    reg [2:0]  rx_state;

    localparam RX_IDLE      = 3'd0;
    localparam RX_MEASURE_1 = 3'd1; // Meet de lengte van de 1e helft van de bit
    localparam RX_WAIT_2    = 3'd2; // Wacht op de 2e (omgekeerde) helft
    localparam RX_EVALUATE  = 3'd3;

    reg first_half_is_p; // Onthoud of we begonnen met een positieve of negatieve puls

    always @(posedge clk_16mhz) begin
        if (reset) begin
            rx_state       <= RX_IDLE;
            frame_rx_valid <= 1'b0;
            rx_bit_count   <= 0;
            rx_timer       <= 0;
        end else begin
            frame_rx_valid <= 1'b0; // Default

            case (rx_state)
                default: rx_state <= RX_IDLE;
                RX_IDLE: begin
                    rx_timer <= 0;
                    if (rx_p_sync || rx_n_sync) begin
                        first_half_is_p <= rx_p_sync; // Als rx_p_sync hoog is, is het een '1' (of '1' sync)
                        rx_state        <= RX_MEASURE_1;
                    end
                end

                RX_MEASURE_1: begin
                    if (rx_p_sync || rx_n_sync) begin
                        // Zolang de puls aanhoudt, timer verhogen
                        if (rx_timer < 255) rx_timer <= rx_timer + 1;
                    end else begin
                        // Puls viel weg. Dit was de 1e helft van de bit.
                        rx_state <= RX_WAIT_2;
                    end
                end

                RX_WAIT_2: begin
                    // Zodra de *andere* polariteit start, evalueren we de bit
                    if ( (first_half_is_p && rx_n_sync) || (!first_half_is_p && rx_p_sync) ) begin
                        rx_state <= RX_EVALUATE;
                    end else if (rx_timer == 255) begin
                        // Timeout: Er kwam geen 2e helft, dit is storing.
                        rx_state <= RX_IDLE;
                    end else begin
                        rx_timer <= rx_timer + 1; // Timer loopt door als timeout-bewaker
                    end
                end

                RX_EVALUATE: begin
                    // Bepaal bitwaarde (P-N is een 1, N-P is een 0)
                    rx_shift_reg <= {rx_shift_reg[9:0], first_half_is_p};

                    // Check of de timer langer liep dan de drempelwaarde voor een Sync bit
                    if (rx_timer > THRESHOLD_SYNC) begin
                        // SYNC bit gedetecteerd! Reset de counter, dit is de eerste bit (C2).
                        rx_bit_count <= 1; 
                    end else begin
                        if (rx_bit_count == 10) begin
                            // Laatste bit (D0) binnengekomen!
                            frame_rx_ctrl  <= {rx_shift_reg[9:8], rx_shift_reg[7]}; // Framebits C2, C1, C0
                            frame_rx_data  <= {rx_shift_reg[6:0], first_half_is_p}; // Framebits D7..D0
                            
                            frame_rx_valid <= 1'b1;
                            rx_bit_count   <= 0;
                        end else begin
                            rx_bit_count <= rx_bit_count + 1;
                        end
                    end
                    
                    // Wacht tot de bus weer rustig is (beide comparators laag)
                    if (!rx_p_sync && !rx_n_sync) rx_state <= RX_IDLE;
                end
            endcase
        end
    end

    // =========================================================
    // TX ZENDER LOGICA (Voor direct drive)
    // =========================================================

    localparam T_NORMAL_HALF = 8'd16; // 1us (bij 16MHz)
    localparam T_SYNC_HALF   = 8'd32; // 2us (bij 16MHz)

    reg [7:0]  tx_timer;
    reg [3:0]  tx_bit_idx;
    reg [10:0] tx_shift_reg;
    reg [2:0]  tx_state;

    localparam TX_IDLE   = 3'd0;
    localparam TX_PULSE1 = 3'd1;
    localparam TX_PULSE2 = 3'd2;
    localparam TX_GAP    = 3'd3;

    wire tx_current_bit = tx_shift_reg[10]; // Verzenden MSB first
    wire is_sync_bit    = (tx_bit_idx == 0);
    wire [7:0] tx_target_time = is_sync_bit ? T_SYNC_HALF : T_NORMAL_HALF;

    always @(posedge clk_16mhz) begin
        if (reset) begin
            tx_p <= 0; tx_n <= 0;
            tx_state <= TX_IDLE;
            frame_tx_busy <= 0;
        end else begin
            case (tx_state)
                default: tx_state <= TX_IDLE;
                TX_IDLE: begin
                    tx_p <= 0; tx_n <= 0;
                    if (frame_tx_start) begin
                        // Laad het 11-bit frame in het schuifregister
                        tx_shift_reg  <= {frame_tx_ctrl, frame_tx_data};
                        tx_bit_idx    <= 0;
                        frame_tx_busy <= 1'b1;
                        tx_timer      <= 0;
                        tx_state      <= TX_PULSE1;
                    end else begin
                        frame_tx_busy <= 1'b0;
                    end
                end

                TX_PULSE1: begin
                    // Eerste helft van de bit
                    tx_p <=  tx_current_bit; // Als 1, +1.5V
                    tx_n <= ~tx_current_bit; // Als 0, -1.5V
                    
                    if (tx_timer == tx_target_time) begin
                        tx_timer <= 0;
                        tx_state <= TX_PULSE2;
                    end else begin
                        tx_timer <= tx_timer + 1;
                    end
                end

                TX_PULSE2: begin
                    // Tweede helft van de bit (omgekeerde polariteit)
                    tx_p <= ~tx_current_bit;
                    tx_n <=  tx_current_bit;
                    
                    if (tx_timer == tx_target_time) begin
                        tx_timer <= 0;
                        tx_state <= TX_GAP;
                    end else begin
                        tx_timer <= tx_timer + 1;
                    end
                end

                TX_GAP: begin
                    // Idle gap tussen bits (rust op de lijn)
                    tx_p <= 0;
                    tx_n <= 0;
                    
                    if (tx_timer == T_NORMAL_HALF) begin
                        if (tx_bit_idx == 10) begin
                            tx_state <= TX_IDLE; // Frame is compleet
                        end else begin
                            tx_shift_reg <= {tx_shift_reg[9:0], 1'b0}; // Schuif
                            tx_bit_idx   <= tx_bit_idx + 1;
                            tx_timer     <= 0;
                            tx_state     <= TX_PULSE1;
                        end
                    end else begin
                        tx_timer <= tx_timer + 1;
                    end
                end
            endcase
        end
    end

endmodule
