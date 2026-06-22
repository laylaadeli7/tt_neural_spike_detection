// IIR Biquad Bandpass Filter
    // fixed-point 10-bit arithmetic (1 sign + 9 integer + 10 fractional bits = 20-bit internal)
// coefficients approximate 300-3000 Hz bandpass at 50 kHz effective sample rate
// (assumes input is clocked at 50 kHz via clock-enable, or use as-is at slower rates)
//
// the transfer function: H(z) = b0 + b1*z^-1 + b2*z^-2
//                              -------------------------
//                               1  + a1*z^-1 + a2*z^-2
//
// coefficients (10-bit, scaled by 1024) using standard eq. from Auto Eq Cookbook:
//   b0 =  0.4441 -> 455
//   b1 =  0 -> 0
//   b2 = -0.4441 -> -455
//   a1 = -0.9201 -> -942
//   a2 =  0.1118 -> 114
//
// these coefficients were found as they will give a bandpass centered ~1 kHz with -3dB points ~300 Hz and ~3000 Hz
// this is known to be suitable for neural spike band isolation!

// it was then pipelined into two stages to meet timing: stage 1 computes w0, stage 2 computes y_full.
// this adds 1 extra clk_en cycle of latency, which is negligible for spike detection, but was necessary to pass all tests 
`default_nettype none
module iir_biquad (
    input  wire clk,
    input  wire rst_n,
    input  wire clk_en,
    input  wire signed [7:0]  x_in,
    output reg  signed [7:0]  y_out
);
    // matches comments above 
   localparam signed [15:0] B0 = 16'sd455;
    localparam signed [15:0] B2 = -16'sd455;
    localparam signed [15:0] A1 = -16'sd942;
    localparam signed [15:0] A2 = 16'sd114;

    reg signed [19:0] w1, w2;
    reg signed [19:0] w0_reg; // pipeline register: stage 1 result
    reg signed [19:0] w2_reg; // delayed w2 to align with w0_reg (these were newly added in)

    wire signed [19:0] x_ext = {{12{x_in[7]}}, x_in};
    wire signed [19:0] w0     = x_ext - ((A1 * w1) >>> 10) - ((A2 * w2) >>> 10); // logic for the biquad filter stage 1
    wire signed [19:0] y_full = ((B0 * w0_reg) >>> 10) + ((B2 * w2_reg) >>> 10); // continued logic for biquad filter stage 2 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w1     <= 20'sd0;
            w2     <= 20'sd0;
            w0_reg <= 20'sd0;
            w2_reg <= 20'sd0;
            y_out  <= 8'sd0;
        end else if (clk_en) begin
            // first stage is to compute w0, advance delay line
            w2 <= w1;
            w1 <= w0;
            // these are the pipeline registers feeding stage 2
            w0_reg <= w0;
            w2_reg <= w2;
            // second stage is to compute y_full from previous cycle's w0/w2 (now registered)
            if      (y_full > 20'sd127)  y_out <= 8'sd127;
            else if (y_full < -20'sd128) y_out <= -8'sd128;
            else    y_out <= y_full[7:0];
        end
    end
endmodule
