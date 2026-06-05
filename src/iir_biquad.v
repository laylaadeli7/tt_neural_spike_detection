// IIR Biquad Bandpass Filter
// Fixed-point Q10 arithmetic (1 sign + 9 integer + 10 fractional bits = 20-bit internal)
// coefficients approximate 300-3000 Hz bandpass at 50 kHz effective sample rate
// (assumes input is clocked at 50 kHz via clock-enable, or use as-is at slower rates)
//
// the transfer function: H(z) = b0 + b1*z^-1 + b2*z^-2
//                           -------------------------
//                               1  + a1*z^-1 + a2*z^-2
//
// coefficients (Q10, scaled by 1024):
//   b0 =  0.0923 -> 94
//   b1 =  0 -> 0
//   b2 = -0.0923 -> -94
//   a1 = -1.7022 -> -1743
//   a2 =  0.8154 -> 835
//
// these will give a bandpass centered ~1 kHz with -3dB points ~300 Hz and ~3000 Hz
// suitable for neural spike band isolation.

`default_nettype none

module iir_biquad (
    input  wire clk,
    input  wire rst_n,
    input  wire clk_en,  // sample clock enable (decimation)
    input  wire signed [7:0]  x_in,  // 8-bit signed input sample
    output reg  signed [7:0]  y_out  // 8-bit signed filtered output
);

    // the Q10 coefficients
    localparam signed [15:0] B0 = 16'sd94;
    localparam signed [15:0] B2 = -16'sd94;
    localparam signed [15:0] A1 = -16'sd1743;
    localparam signed [15:0] A2 = 16'sd835;
    localparam signed [15:0] Q  = 16'sd1024; // 2^10

    // delay registers (Q10 scaled)
    reg signed [19:0] w1, w2; // w[n-1], w[n-2]

    // internal wires
    wire signed [19:0] x_ext = {{12{x_in[7]}}, x_in}; // sign-extend to 20 bits
    wire signed [19:0] w0;
    wire signed [19:0] y_full;

    // direct form II: w[n] = x[n] - a1*w[n-1] - a2*w[n-2]
    //                 y[n] = b0*w[n] + b2*w[n-2]
    // divide by Q (arithmetic right shift 10) to keep in range
    assign w0     = x_ext - ((A1 * w1) >>> 10) - ((A2 * w2) >>> 10);
    assign y_full = ((B0 * w0) >>> 10) + ((B2 * w2) >>> 10);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w1    <= 20'sd0;
            w2    <= 20'sd0;
            y_out <= 8'sd0;
        end else if (clk_en) begin
            w2    <= w1;
            w1    <= w0;
            // Saturate to 8-bit output
            if      (y_full > 20'sd127)  y_out <= 8'sd127;
            else if (y_full < -20'sd128) y_out <= -8'sd128;
            else                         y_out <= y_full[7:0];
        end
    end

endmodule
