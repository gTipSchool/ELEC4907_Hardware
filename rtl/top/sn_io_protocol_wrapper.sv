`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/26/2023 07:42:21 PM
// Design Name: 
// Module Name: sn_io_protocol_wrapper
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


module sn_io_protocol_wrapper
    (
    input clk_in1_p,
    input clk_in1_n,
    input rst,
        
    input rx_input,
    output tx_output
    );
    
    localparam P_CLKS_PER_BIT=87;
    localparam P_BITS_TO_SEND=10;
    localparam P_BITS_TO_RECEIVE=10;
    localparam P_PROT_WATCHDOG_TIME=100000000;
    
    // Declarations:
    
    // For modules:
    logic clk;
    
    logic prot_enable;
    logic prot_r0w1;
    logic [7-1:0] prot_addr; // Register address for reading or writing
    logic [8-1:0] prot_wdata; // Data for writing
    logic [8-1:0] prot_rdata;
    
    // 
    logic [1:0] read_call_counter;
    logic [1:0] read_call_counter_next;
    
    
    
    // Clock divider:
    clk_wiz_0 clk_div_i (
        .clk_in1_p(clk_in1_p),
        .clk_in1_n(clk_in1_n),
        .reset(rst),
        .clk(clk)
    );
    
    sn_io_protocol
        #(
        .P_CLKS_PER_BIT(P_CLKS_PER_BIT),
        .P_BITS_TO_SEND(P_BITS_TO_SEND),
        .P_BITS_TO_RECEIVE(P_BITS_TO_RECEIVE),
        .P_PROT_WATCHDOG_TIME(P_PROT_WATCHDOG_TIME)
        )
    sn_io_protocol_DUT
        (   
        .clk(clk),
        .rst(rst),
        
        .uart_tx(tx_output),
        .uart_rx(rx_input),
        
        .prot_enable(prot_enable),
        .prot_r0w1(prot_r0w1),
        .prot_addr(prot_addr),
        .prot_wdata(prot_wdata),
        .prot_rdata(prot_rdata)
        );
        
   always_ff @(posedge clk) begin
     if (rst) begin
        read_call_counter <= 0;
        read_call_counter_next <= 0;
     end else begin
        read_call_counter <= read_call_counter_next;   
     end 
   end
   
   always_comb begin
    if (prot_r0w1)
        read_call_counter_next = read_call_counter_next + 1'b1;
    else 
        read_call_counter_next = read_call_counter_next;
    end
    
  always_comb begin
  
    //prot_rdata = 8'b10101010;
    prot_rdata = 8'b11110000;
    
    case (read_call_counter)
        0: prot_rdata = 8'b11110001;
        1: prot_rdata = 8'b11110010;
        2: prot_rdata = 8'b11110011;
        3: prot_rdata = 8'b11110100;
    endcase        
    
  end 
   
    
endmodule
