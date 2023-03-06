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


module sn_uart_tx_tb;
    
    localparam  P_CLKS_PER_BIT = 87;
    localparam P_NUM_BITS_TO_SEND = 10;
    
    reg clk, rst, tx_enable;
    reg [7:0] data_to_pc;
     //inputs
    
    wire tx_output, tx_done, tx_active; //outputs
    // Input Controller
   
    
    sn_uart_tx
        #(
        .P_CLKS_PER_BIT(P_CLKS_PER_BIT),
        .P_NUM_BITS_TO_SEND(P_NUM_BITS_TO_SEND)
        )
    uart_tx_DUT (
        .clk(clk),
        .rst(rst),
        .tx_enable(tx_enable),
        .data_to_pc(data_to_pc),
        .tx_output(tx_output),
        .tx_done(tx_done),
        .tx_active(tx_active)
         );
    
    initial clk = 1'b0;
    always #5 clk = ~clk; // ! && || 
    // ~ & | ^
    // a=1010
    // b=0011
    // c = a && b = 1
    // c = a & b = 0010
    
    
    initial begin
        {rst, tx_enable, data_to_pc} = '0;
        rst = 1'b1;
        
    @(posedge clk) #0 rst = 1'b0;
//        data_to_pc = 10'b0101001101;
        data_to_pc = 8'b11110000;
        #10
        tx_enable = 1;
        
    @(posedge tx_done)
        tx_enable = 0;
        
        
        repeat(150) @(posedge clk);
        $stop;
    end
        
  
endmodule
