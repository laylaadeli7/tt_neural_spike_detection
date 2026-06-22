// SPI Configuration Receiver (Mode 0, MSB first)
// Receives 16-bit config word:
//   [15:12] = k_thresh (threshold multiplier, default 5)
//   [11:8]  = reserved
//   [7:0] = refractory_len (samples, default 50 = ~1ms at 50kHz)
//
// Pinout on uio[]:
//   uio[0] = SCLK
//   uio[1] = MOSI
//   uio[2] = CS_n (active low)
//   uio[3] = debug out (filtered signal MSB) - output
//
// All uio pins are inputs except uio[3].
// uio_oe = 8'b00001000 (only uio[3] is output)

`default_nettype none

module spi_config (
    input  wire       clk,
    input  wire       rst_n,
    // these are the SPI pins
    input  wire       sclk,
    input  wire       mosi,
    input  wire       cs_n,
    // these config outputs (registered, hold until next write)
    output reg [3:0]  k_thresh,
    output reg [7:0]  refractory_len
);

    reg [2:0]  sclk_sync;   // 3-stage synchronizer for SCLK
    reg [1:0]  mosi_sync;
    reg [1:0]  cs_sync;

    wire sclk_rise = (sclk_sync[2:1] == 2'b01); // rising edge detect

    reg [4:0]  bit_cnt;
    reg [15:0] shift_reg;

    // this synchronizes async SPI inputs to system clock domain
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_sync <= 3'b0;
            mosi_sync <= 2'b0;
            cs_sync   <= 2'b11;
        end else begin
            sclk_sync <= {sclk_sync[1:0], sclk};
            mosi_sync <= {mosi_sync[0], mosi};
            cs_sync  <= {cs_sync[0], cs_n};
        end
    end
    // inverts it so it is naturally TRUE when active (even though it is active low)
    wire cs_active = ~cs_sync[1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt       <= 5'h0;
            shift_reg     <= 16'h0;
            k_thresh      <= 4'd5;  // default k=5
            refractory_len <= 8'd50; // default ~1ms
        end else begin
            // receives the bits (shift register)
            if (!cs_active) begin
                bit_cnt   <= 5'h0;
                shift_reg <= 16'h0;
            end else if (sclk_rise) begin
                shift_reg <= {shift_reg[14:0], mosi_sync[1]};
                bit_cnt   <= bit_cnt + 5'h1;
                // latches the final result 
                if (bit_cnt == 5'd15) begin
                    // the full 16-bit word received
                    // once the 16 bits have been shifted in (bit_cnt reaches 15, the 16th bit since it started at 0), 
                    //       the full word is complete and gets split per the format at the top 
                    //          top 4 bits become the threshold multiplier, bottom 8 bits become the refractory length.
                    k_thresh       <= shift_reg[15:12];
                    refractory_len <= shift_reg[7:0];
                end
            end
        end
    end

endmodule
