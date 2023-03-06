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

module comms  
    #(
    parameter P_CLKS_PER_BIT =  87, // NEED TO CALCULATE USING CLOCK RATE/BAUD RATE (EX. 100MHz CLK/ 115200 baud = 87)
    parameter P_NUM_BITS_TO_SEND = 10,
    parameter P_NUM_BITS_TO_RECEIVE = 10
    )(
    input clk_in1_p,
    input clk_in1_n,
    input rst,
    input rx_input,
   
    // output logic rts_output,
    output tx_output
    );
    
    wire clk;
    
    reg rx_done_hold;
    reg rx_enable;
    
    wire tx_enable;
    wire [7:0] received_word;
    
    
    // Clock divider:
    clk_wiz_0 clk_div_i (
        .clk_in1_p(clk_in1_p),
        .clk_in1_n(clk_in1_n),
        .reset(rst),
        .clk(clk)
    );
   
    assign tx_enable = rx_done_hold & ~tx_done;
    
    
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
        .rx_done(rx_done)
     );
     
     sn_uart_tx
        #(
        .P_CLKS_PER_BIT(P_CLKS_PER_BIT),
        .P_NUM_BITS_TO_SEND(P_NUM_BITS_TO_SEND)
        )
    uart_tx_DUT (
        .clk(clk),
        .rst(rst),
        .tx_enable(tx_enable),
        .data_to_pc(~received_word),
        .tx_output(tx_output),
        .tx_done(tx_done)
     );
    
    always_ff @(posedge clk)
        if (rst)
            rx_enable <= 1;
            
            
    always_ff @(posedge clk) begin
        if (rst)
            rx_done_hold <= 0;
        else begin
            if (rx_done)
                rx_done_hold <= 1;
            else if (tx_done)
                rx_done_hold  <= 0;
                //tx_enable <= 0
            
        end
    end
endmodule
