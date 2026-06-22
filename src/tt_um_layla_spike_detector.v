// tt_um_layla_spike_detector 
// Top-level Tiny Tapeout wrapper
// Neural Spike Detector for TTGF26b
//
// the signal path is path: ADC input -> IIR bandpass -> NEO -> adaptive threshold -> spike FSM
//
// pin mapping:
//   ui_in[7:0]  - 8-bit signed ADC sample (2's complement, Q7)
//   uo_out[7]   - spike detected (1-cycle pulse, synchronous to clk_en)
//   uo_out[6:0] - 7-bit rolling timestamp (increments each clk_en)
//   uio[0]      - SPI SCLK        (input)
//   uio[1]      - SPI MOSI        (input)
//   uio[2]      - SPI CS_n        (input)
//   uio[3]      - debug: filtered signal bit 7 (output)
//   uio[7:4]    - unused (input)
//
// Clock divider: system clk (10 MHz) -> clk_en every 500 cycles = 20 kHz sample rate
// this is below typical neural recording ADC rates (20-50 kHz), but was running into GDS errors with faster clocks 
`default_nettype none
module tt_um_layla_spike_detector (
    input  wire [7:0] ui_in,    // dedicated inputs
    output wire [7:0] uo_out,   // dedicated outputs
    input  wire [7:0] uio_in,   // bidir IOs: input path
    output wire [7:0] uio_out,  // bidir IOs: output path
    output wire [7:0] uio_oe,   // bidir IOs: output enable (1=output)
    input  wire       ena,      // always 1 when design selected
    input  wire       clk,      // system clock
    input  wire       rst_n     // active-low reset
);
    // this is the IIR bandpass filter 
    wire signed [7:0] filtered;
    // ── uio direction: only uio[3] is output (debug) ──
    assign uio_oe  = 8'b00001000;
    assign uio_out = {4'b0, filtered[7], 3'b0}; // debug on uio[3]
    // Clock divider: 50 MHz -> 50 kHz sample clock enable 
    reg [9:0] clk_div;
    wire clk_en = (clk_div == 10'h0);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) clk_div <= 10'h0;
        else        clk_div <= (clk_div == 10'd999) ? 10'h0 : clk_div + 10'h1;
    end
    // SPI config 
    wire [3:0] k_thresh;
    wire [7:0] refractory_len;
    spi_config u_spi (
        .clk (clk),
        .rst_n (rst_n),
        .sclk  (uio_in[0]),
        .mosi  (uio_in[1]),
        .cs_n  (uio_in[2]),
        .k_thresh (k_thresh),
        .refractory_len (refractory_len)
    );
  
    iir_biquad u_filter (
        .clk    (clk),
        .rst_n  (rst_n),
        .clk_en (clk_en),
        .x_in   (ui_in),
        .y_out  (filtered)
    );
    // the NEO energy operator 
    wire [15:0] neo_val;
    neo u_neo (
        .clk (clk),
        .rst_n (rst_n),
        .clk_en (clk_en),
        .x_in (filtered),
        .neo_out (neo_val)
    );
    // Noise estimator + adaptive threshold
    wire [15:0] threshold;
    noise_estimator u_noise (
        .clk (clk),
        .rst_n (rst_n),
        .clk_en (clk_en),
        .x_in (filtered),
        .k_thresh (k_thresh),
        .threshold (threshold)
    );
    // Spike detection FSM
    spike_fsm u_fsm (
        .clk  (clk),
        .rst_n (rst_n),
        .clk_en (clk_en),
        .neo_val (neo_val),
        .threshold(threshold),
        .refractory_len (refractory_len),
        .uo_out (uo_out)
    );
endmodule
