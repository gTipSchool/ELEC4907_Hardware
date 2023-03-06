`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/26/2023 06:47:07 PM
// Design Name: 
// Module Name: sn_io_protocol_tb
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


module sn_io_protocol_tb
    #(
      localparam P_CLKS_PER_BIT=10, // Number of prot_clk clock cycles per bit on the UART interface. Depends on baudrate.
      localparam P_BITS_TO_SEND=11,
      localparam P_BITS_TO_RECEIVE=11,
      localparam P_PROT_WATCHDOG_TIME=100 
    )
    (
    // Clk and Rst
     input clk,
     input rst,
    
    // FPGA protocol interconnection
     input uart_tx,
     output uart_rx,
     output cts_input,
     input rts_output,
     
     // Protocol Interface
     input prot_enable, // Enable all <prot_*> signals
     input prot_r0w1, // 0=read operation, 1=write operation
     input [7-1:0] prot_addr, // Register address for reading or writing
     input [8-1:0] prot_wdata, // Data for writing
     output logic [8-1:0] prot_rdata // Data returned during a read. Valid when prot_enable=1 (i.e. no read latency).
    );
    
    
endmodule
