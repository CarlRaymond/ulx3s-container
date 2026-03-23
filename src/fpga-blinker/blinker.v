// Simple LED blinker for ULX3S ECP5-12K
// 25 MHz clock; counter bits [26:23] give ~0.75 – 6 Hz blink rates across 8 LEDs

module blinker (
    input  clk_25mhz,
    output [7:0] led
);
    reg [27:0] counter = 0;

    always @(posedge clk_25mhz)
        counter <= counter + 1;

    // Each LED gets the next counter bit, so rates are 6, 3, 1.5, 0.75 Hz, etc.
    assign led = counter[27:20];

endmodule
