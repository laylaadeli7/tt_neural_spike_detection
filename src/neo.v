// Nonlinear Energy Operator (NEO)
// Computes: psi[n] = x[n]^2 - x[n+1]*x[n-1]
//     comes after the IIR because it will amplify everything (got rid of noise first)
// The NEO amplifies spike energy relative to noise, giving much better
// SNR than simple threshold on raw signal. it was used in Mukhopadhyay & Ray 1998
// and widely adopted in implantable neural recording ASICs.
//
// Since we are causal (real-time), we implement the 1-sample delayed version:
//   psi[n-1] = x[n-1]^2 - x[n]*x[n-2]
// the output is always non-negative (energy measure).

`default_nettype none

module neo (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clk_en,
    input  wire signed [7:0]  x_in,   // filtered input
    output reg         [15:0] neo_out // unsigned energy output (8x8 = 16-bit max)
);

    reg signed [7:0] x_d1, x_d2; // x[n-1], x[n-2]

    // equations: all together it is this psi[n] = x[n]^2 - x[n+1]*x[n-1]
    // previously mentioned, delay by 1 so it is psi[n-1] = x[n-1]^2 - x[n]*x[n-2]
    wire signed [15:0] x_sq   = x_d1 * x_d1; // x[n-1]^2  always >= 0
    wire signed [15:0] x_prod = x_in  * x_d2; // x[n]*x[n-2]
    wire signed [15:0] neo_raw = x_sq - x_prod;

    // the clocked update block that shifts delay line and updates registers
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_d1    <= 8'sd0;
            x_d2    <= 8'sd0;
            neo_out <= 16'h0;
        end else if (clk_en) begin
            x_d2    <= x_d1;
            x_d1    <= x_in;
            // NEO output should be non-negative; 
            // so must clamp if somehow negative (startup)
            neo_out <= (neo_raw[15]) ? 16'h0 : neo_raw[15:0];
        end
    end

endmodule
