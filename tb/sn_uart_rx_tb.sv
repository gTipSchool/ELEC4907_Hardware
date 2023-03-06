`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/08/2022 03:32:23 PM
// Design Name: 
// Module Name: sn_neuron_tb
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


module sn_uart_rx_tb;
    
    localparam  P_CLKS_PER_BIT = 10;
    localparam P_NUM_BITS_TO_RECEIVE = 10;
    
    reg [9:0] data_to_receive;
    
    reg clk, rst, rx_enable;
    logic rx_input;
    //inputs
    
    wire [7:0] received_word;
    wire rx_done;
    wire rx_active;
    //outputs
    
    assign rx_input = data_to_receive[9];
    
    sn_uart_rx
        #(
        .P_CLKS_PER_BIT(P_CLKS_PER_BIT),
        .P_NUM_BITS_TO_RECEIVE(P_NUM_BITS_TO_RECEIVE)
    )
    uart_rx_DUT (
        .clk(clk),
        .rst(rst),
        .rx_enable(rx_enable),
        .rx_input(rx_input),
        .received_word(received_word),
        .rx_done(rx_done),
        .rx_active(rx_active)
     );
     
     
     

    initial clk = 1'b0;
    always #5 clk = ~clk;
    
    initial begin
        {rst, rx_enable, rx_input} = '0;
        rst = 1'b1;
        
        data_to_receive = 10'b0100110011; //make sure first bit is 0, and last buit is 1 for UART to work
        
        @(posedge clk) #0 
        rst = 1'b0;

        for (int i = 0;i < 10;i++) begin
            if (i == 0)
                rx_enable = 1;            
            repeat(10) @(posedge clk) #0;
            data_to_receive = data_to_receive << 1; 
        end
                
        @(posedge rx_done)
        rx_enable = 0;
        repeat(150) @(posedge clk);
        $stop;
    end
        
endmodule