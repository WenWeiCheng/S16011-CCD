`timescale 1ns / 1ps

module test_ccd_driver;

    parameter real CLK_PERIOD = 40.0;  // 25 MHz

    reg ADCCLK;
    reg P1V;
    reg P2V;    // TG
    reg P1H;
    reg P2H;
    reg P3H;
    reg P4H;    // SG
    reg RG;

    localparam real T = CLK_PERIOD;

    // ADCCLK: 同相, 50%, 复位电平=0
    initial ADCCLK = 1'b0;
    always #(T/2.0) ADCCLK = ~ADCCLK;

    // P1V: 超前90°, 50%, 复位电平=0
    initial P1V = 1'b0;
    always begin
        #(T/4.0) P1V = ~P1V;
        forever #(T/2.0) P1V = ~P1V;
    end

    // P2V(TG): 落后90°, 50%, 复位电平=0
    initial P2V = 1'b0;
    always begin
        #(3.0*T/4.0) P2V = ~P2V;
        forever #(T/2.0) P2V = ~P2V;
    end

    // P1H: 相差180°, 50%, 复位电平=1
    initial P1H = 1'b1;
    always begin
        forever #(T/2.0) P1H = ~P1H;
    end

    // P2H: 超前90°, 50%, 复位电平=0
    initial P2H = 1'b0;
    always begin
        #(T/4.0) P2H = ~P2H;
        forever #(T/2.0) P2H = ~P2H;
    end

    // P3H: 同相, 50%, 复位电平=0
    initial P3H = 1'b0;
    always #(T/2.0) P3H = ~P3H;

    // P4H(SG): 落后90°, 50%, 复位电平=0
    initial P4H = 1'b0;
    always begin
        #(3.0*T/4.0) P4H = ~P4H;
        forever #(T/2.0) P4H = ~P4H;
    end

    // RG: 落后90°, 25%, 复位电平=1
    initial RG = 1'b1;
    always begin
        forever begin
            #(3.0*T/4.0) RG = 1'b1;
            #(T/4.0) RG = 1'b0;
        end
    end

    initial begin
        $dumpfile("test_ccd_driver.vcd");
        $dumpvars(0, test_ccd_driver);
        #(20 * T);
        $finish;
    end

endmodule
