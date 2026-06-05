// Noise Estimator
// Tracks noise level sigma using Exponential Weighted Moving Average (EWMA)
// of the absolute value of the filtered signal.
//
// sigma[n] = (1 - alpha) * sigma[n-1] + alpha * |x[n]|
//
// Using alpha = 1/16 (right shift by 4) for hardware efficiency:
// sigma[n] = sigma[n-1] + (|x[n]| - sigma[n-1]) >> 4
//
// Threshold = k * sigma, where k is configurable (default 5).
// This gives an adaptive threshold that tracks baseline drift,
// which is critical for long-duration neural recordings.
//
// sigma is kept in Q4 fixed point internally (shifted left 4 bits)
// for precision, then the threshold is output in the same domain
// as the NEO output for direct comparison.

`default_nettype none

module noise_estimator (
    input  wire clk,
    input  wire rst_n,
    input  wire clk_en,
    input  wire signed [7:0]  x_in, // filtered signal (for noise tracking)
    input  wire [3:0]  k_thresh,   // threshold multiplier (default 5)
    output reg  [15:0] threshold   // adaptive threshold for NEO comparison
);

    // sigma_acc: Q4 fixed point (sigma * 16), 12 bits
    reg [11:0] sigma_acc;

    wire [7:0] abs_x = x_in[7] ? (~x_in + 8'h1) : x_in; // |x|
    wire [7:0] sigma_est = sigma_acc[11:4]; // Q0 sigma

    // EWMA update: alpha = 1/16
    wire signed [12:0] sigma_acc_s = {1'b0, sigma_acc};
    wire signed [12:0] abs_x_ext   = {5'b0, abs_x};
    wire signed [12:0] error       = (abs_x_ext <<< 4) - sigma_acc_s;
    wire signed [12:0] update      = error >>> 4;
    wire signed [12:0] sigma_next  = sigma_acc_s + update;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sigma_acc <= 12'h80; // start at 8
            threshold <= 16'h0;
        end else if (clk_en) begin
            sigma_acc <= sigma_next[11:0];
            // Threshold = k * sigma^2 / 4 (scaled to NEO energy domain)
            threshold <= (k_thresh * sigma_est * sigma_est) >> 9; // tested the threshold 
        end
    end

endmodule
