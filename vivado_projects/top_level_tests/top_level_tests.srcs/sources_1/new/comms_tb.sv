`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/20/2022 02:37:50 PM
// Design Name: 
// Module Name: comms_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module comms_tb;   
    
    localparam P_CLKS_PER_BIT = 109;
    localparam P_NUM_BITS_TO_SEND = 10;
    localparam P_NUM_BITS_TO_RECEIVE = 10;
    
    reg clk, rst;
    reg rx_input;
    wire tx_output;
    
    comms
        #(
        .P_CLKS_PER_BIT(P_CLKS_PER_BIT),
        .P_NUM_BITS_TO_SEND(P_NUM_BITS_TO_SEND),
        .P_NUM_BITS_TO_RECEIVE(P_NUM_BITS_TO_RECEIVE)
        )
    comms_DUT (
        .clk(clk),
        .rst(rst),
        .rx_input(rx_input),
        .tx_output(tx_output)
         );
         
    initial clk = 1'b0;
        always #5 clk = ~clk;
    
    initial begin
        rst = 1;
        #10 
        rst = 0;
        rx_input = 1;
        repeat(100) @(posedge clk) #0;
        rx_input = 0;
        repeat(P_CLKS_PER_BIT) @(posedge clk) #0;
        rx_input = 1;
        repeat(P_CLKS_PER_BIT) @(posedge clk) #0;
        rx_input = 1;
        repeat(P_CLKS_PER_BIT) @(posedge clk) #0;
        rx_input = 0;
        repeat(P_CLKS_PER_BIT) @(posedge clk) #0;
        rx_input = 0;
        repeat(P_CLKS_PER_BIT) @(posedge clk) #0;
        rx_input = 0;
        repeat(P_CLKS_PER_BIT) @(posedge clk) #0;
        rx_input = 0;
        repeat(P_CLKS_PER_BIT) @(posedge clk) #0;
        rx_input = 0;
        repeat(P_CLKS_PER_BIT) @(posedge clk) #0;
        rx_input = 1;
        repeat(P_CLKS_PER_BIT) @(posedge clk) #0;
        rx_input = 1;

        repeat(P_CLKS_PER_BIT) @(posedge clk) #0;
        repeat(200) @(posedge clk);
        $stop;
    end
    
    
    
endmodule
