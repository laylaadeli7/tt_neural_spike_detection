// Spike Detection FSM
// States: IDLE -> DETECT -> REFRACTORY -> IDLE
//
// IDLE:        Watching for NEO > threshold crossing
// DETECT:      Threshold exceeded, so it emit spike pulse for 1 cycle,
//              latch timestamp
// REFRACTORY:  Dead time counter, blocks re-triggering on same spike
//              Refractory period configurable via refractory_len
//              Default ~1ms at 50kHz sample rate = 50 samples
//
// Output on uo_out:
//   [7] = spike detected (1-cycle pulse)
//   [6:0] = 7-bit timestamp counter (wraps every 128 samples)

`default_nettype none

module spike_fsm (
    input  wire clk,
    input  wire rst_n,
    input  wire clk_en,
    input  wire [15:0] neo_val,  // NEO energy
    input  wire [15:0] threshold, // adaptive threshold
    input  wire [7:0]  refractory_len, // refractory period in samples
    output reg  [7:0]  uo_out  // TT output port
);

    // the FSM states
    localparam IDLE = 2'b00;
    localparam DETECT = 2'b01;
    localparam REFRACTORY = 2'b10;

    reg [1:0]  state;
    reg [7:0]  refrac_cnt; // the refractory counter
    reg [6:0]  timestamp;  // the 7-bit rolling timestamp

    wire above_threshold = (neo_val > threshold) && (threshold > 16'h0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= IDLE;
            refrac_cnt  <= 8'h0;
            timestamp <= 7'h0;
            uo_out <= 8'h0;
        end else if (clk_en) begin
            timestamp <= timestamp + 7'h1;
            // conditional state 
            // checks condition in the background, if true moves onto DETECT 
            case (state)
                IDLE: begin
                    uo_out <= {1'b0, timestamp};
                    if (above_threshold) begin
                        state  <= DETECT;
                    end
                end
                // not conditional, this is just right after IDLE 
                // sets up the refractory count and spike pulsing etc 
                // moves onto refractory state after 
                DETECT: begin
                    // here, want to emit spike pulse in this cycle with timestamp
                    uo_out <= {1'b1, timestamp};
                    state  <= REFRACTORY;
                    refrac_cnt <= (refractory_len == 8'h0) ? 8'd50 : refractory_len;
                end
                // this is the "cooldown" effectively, keep counting down until it is 0 
                // at 0 for countdown, it then moves back to IDLE 
                REFRACTORY: begin
                    uo_out <= {1'b0, timestamp};
                    if (refrac_cnt == 8'h0) begin
                        state <= IDLE;
                    end else begin
                        refrac_cnt <= refrac_cnt - 8'h1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
