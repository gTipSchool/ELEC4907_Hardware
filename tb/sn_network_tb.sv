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


module sn_network_tb;
    
    localparam P_NUM_NEURONS=21; 
    localparam P_NUM_OUTPUTS=3;
    localparam P_NUM_INPUTS=9;
    localparam P_DFLT_CNTR_VAL=40;
    localparam L_STEP_CNTR_MAX_VAL = 120;
    localparam P_TABLE_NUM_ROWS=4;
    localparam P_TABLE_WEIGHT_BW=9;
    localparam P_NEUR_CURRENT_BW=9;
    localparam P_NEUR_STEP_CNTR_BW=$clog2(L_STEP_CNTR_MAX_VAL+1);
    localparam P_MAX_NUM_PERIODS=2000;
    
    localparam L_NUM_PARAM_REGS = 2;
    localparam L_NEUR_MEM_ADDR_MSB_BW=$clog2(P_NUM_NEURONS+1);
    localparam L_NEUR_MEM_ADDR_LSB_BW=$clog2(P_TABLE_NUM_ROWS*2+L_NUM_PARAM_REGS);
    localparam L_NEUR_MEM_DATA_BW=P_NEUR_CURRENT_BW;
    
    reg clk, rst, io_nc_start;
    // Input Controller
    reg [P_NUM_INPUTS:1][P_NEUR_CURRENT_BW-1:0] io_net_inputs;
    reg io_nc_num_per_wen;
    reg [$clog2(P_MAX_NUM_PERIODS+1)-1:0] io_nc_num_per_d;
    // Memory Interface
    reg io_we;
    reg [L_NEUR_MEM_ADDR_MSB_BW+L_NEUR_MEM_ADDR_LSB_BW-1:0] io_waddr;
    reg [L_NEUR_MEM_DATA_BW-1:0] io_wdata;
    
    wire nc_io_done;
    
    sn_network_dut
        #(
        .P_NUM_NEURONS(P_NUM_NEURONS), 
        .P_NUM_OUTPUTS(P_NUM_OUTPUTS),
        .P_NUM_INPUTS(P_NUM_INPUTS),
        .P_DFLT_CNTR_VAL(P_DFLT_CNTR_VAL),
        .P_TABLE_NUM_ROWS(P_TABLE_NUM_ROWS),
        .P_TABLE_WEIGHT_BW(P_TABLE_WEIGHT_BW),
        .P_NEUR_CURRENT_BW(P_NEUR_CURRENT_BW),
        .P_MAX_NUM_PERIODS(P_MAX_NUM_PERIODS),
        .P_NEUR_STEP_CNTR_BW(P_NEUR_STEP_CNTR_BW)
        )
    network_DUT (
        .clk(clk),
        .rst(rst),
        .io_nc_num_per_wen(io_nc_num_per_wen),
        .io_nc_num_per_d(io_nc_num_per_d),
        .io_net_inputs(io_net_inputs), 
        .io_nc_start(io_nc_start), 
        .io_we(io_we),
        .io_waddr(io_waddr),
        .io_wdata(io_wdata),
        .nc_io_done(nc_io_done)
    );
    
    always #5 clk = ~clk;
    
    initial begin
        {clk,rst,io_nc_start,io_nc_num_per_wen,io_net_inputs,io_nc_num_per_d,io_we,io_waddr,io_wdata} = '0;
        rst = 1'b1;
        @(posedge clk) #0 rst = 1'b0;
        @(posedge clk) #0;
        
        if (P_NUM_NEURONS==5) begin
        
            // Set the input current(s):
            io_net_inputs = 'd30;
            
            // Set the weights for the hidden neurons:
            // neuron 2 (hidden): reacts only to input neuron
            mem_if_write(2,2,1); // Set index to 1
            mem_if_write(2,3,10); // Set weight to 10
            // neuron 3 (hidden): reacts only to input neuron
            mem_if_write(3,2,1); // Set index to 1
            mem_if_write(3,3,20); // Set weight to 20
            // neuron 4 (hidden): reacts to neuron 2 and 3
            mem_if_write(4,2,2); // Set index to 2
            mem_if_write(4,3,30); // Set weight to 10
            mem_if_write(4,4,3); // Set index to 4
            mem_if_write(4,5,30); // Set weight to 10
            // neuron 5 (output): reacts only to neuron 4
            mem_if_write(5,2,4); // Set index to 4
            mem_if_write(5,3,10); // Set weight to 10
            
            // Set the number of evaluation periods:
            set_num_periods(1000);
            
            // Command the network to start executing and then wait for it to stop:
            run_network(10000); // Watchdog timer set to 10000 cycles.
            
            // Set the number of evaluation periods:
            set_num_periods(1000);
            
            // Command the network to start executing and then wait for it to stop:
            run_network(10000); // Watchdog timer set to 10000 cycles.
            
        end else if (P_NUM_NEURONS==21) begin
            // 21 neurons in our "small" creature model. This has 9 inputs (R1/2/3, C1/2/3, L1/2/3) and 3 outputs (LEFT, FORWARD, RIGHT).
        
            // Setup inputs (overriding the zero):
            //  Right neurons:
            io_net_inputs[1] = 'd15;
            io_net_inputs[2] = 'd15;
            io_net_inputs[3] = 'd15;
            //  Center neurons:
            io_net_inputs[4] = 'd15;
            //io_net_inputs[5] = 'd15;
            //io_net_inputs[6] = 'd15;
            //  Left neurons:
            //io_net_inputs[7] = 'd15;
            //io_net_inputs[8] = 'd15;
            io_net_inputs[9] = 'd15;
            
            // Set the weights:
            //  Neuron 10 (HR): Right first hidden layer. Reacts to all right inputs (1,2,3)
            load_weight(10,0,1,10);
            load_weight(10,1,2,10);
            load_weight(10,2,3,10);
            //  Neuron 11 (HC): Center first hidden layer. Reacts to all center inputs (4,5,6). Also change the output step counter to 120 from 40.
            load_weight(11,0,4,10);
            load_weight(11,1,5,10);
            load_weight(11,2,6,10);
            load_step_len(11,L_STEP_CNTR_MAX_VAL);
            //  Neuron 12 (HL): Left first hidden layer. Reacts to all left inputs (7,8,9)
            load_weight(12,0,7,10);
            load_weight(12,1,8,10);
            load_weight(12,2,9,10);
            //  Neuron 13 (RGL). Reacts to HR(5), HC(-20), HL(-5)
            load_weight(13,0,10,5);
            load_weight(13,1,11,-20);
            load_weight(13,2,12,-5);
            //  Neuron 14 (LGR). Reacts to HR(-5), HC(-20), HL(5)
            load_weight(14,0,10,-5);
            load_weight(14,1,11,-20);
            load_weight(14,2,12,5);
            //  Neuron 15 (RANDR). Reacts to LGR(-12), HC(-12), RGL(-12). Also has constant current 4.
            load_weight(15,0,13,-12);
            load_weight(15,1,14,-12);
            load_weight(15,2,11,-12);
            load_const_current(15,20);
            //  Neuron 16 (RANDL). Reacts to LGR(-12), HC(-12), RGL(-12). Also has constant current 4.
            load_weight(16,0,13,-12);
            load_weight(16,1,14,-12);
            load_weight(16,2,11,-12);
            //load_const_current(16,4);
            //  Neuron 17 (RGL2). Reacts to RANDR(6), RGL(10), RANDL(-6), HC(-15)
            load_weight(17,0,15,6);
            load_weight(17,1,13,10);
            load_weight(17,2,16,-6);
            load_weight(17,3,11,-15);
            //  Neuron 18 (LGR2). Reacts to RANDL(6), LGR(10), RANDR(-6), HC(-15)
            load_weight(18,0,16,6);
            load_weight(18,1,14,10);
            load_weight(18,2,15,-6);
            load_weight(18,3,11,-15);
            //  Neuron 19 (Right output). Reacts to RGL2(8)
            load_weight(19,0,17,10);
            //  Neuron 20 (Center output). Reacts to HC(8)
            load_weight(20,0,11,8);
            //  Neuron 21 (Left output). Reacts to LGR2(8)
            load_weight(21,0,18,10);
            
            // Set the number of evaluation periods:
            set_num_periods(1500);
            
            // Command the network to start executing and then wait for it to stop:
            run_network(10000); // Watchdog timer set to 10000 cycles.
            
        end
        
        repeat(10) @(posedge clk) #0;
        $stop;
    end
    
    
    // Call this after "@(posedge clk) #0"
    // This will write to some internal address of some neuron in the network with some value.
    task mem_if_write(input integer addr_neuron_idx, addr_internal, value);
        begin
            io_we = 1'b1;
            io_waddr = {(L_NEUR_MEM_ADDR_MSB_BW)'(addr_neuron_idx),(L_NEUR_MEM_ADDR_LSB_BW)'(addr_internal)};
            io_wdata = value;
            @(posedge clk) #0;
            {io_we,io_waddr,io_wdata} = '0;
        end
    endtask
    // This writes a constant current to a neuron.
    task load_weight(input integer target_neuron, row, assoc_neuron_idx, weight);
        begin
            mem_if_write(target_neuron, row*2+2, assoc_neuron_idx);
            mem_if_write(target_neuron, row*2+3, weight);
        end
    endtask
    // This writes one weight associated with a neuron to a neurons weight table.
    task load_const_current(input integer target_neuron, current);
        begin
            mem_if_write(target_neuron, 0, current);
        end
    endtask
    // This writes the step length to a neuron, changing how long the neuron holds its output for.
    task load_step_len(input integer target_neuron, count);
        begin
            mem_if_write(target_neuron, 1, count);
        end
    endtask
    // This sets the number of execution periods for the network.
    task set_num_periods(input integer value);
        begin
            io_nc_num_per_wen = 1'b1;
            io_nc_num_per_d = value;
            @(posedge clk) #0;
            {io_nc_num_per_d,io_nc_num_per_wen} = '0;
        end
    endtask
    // This starts the network execution and waits for it to end before returning.
    // It also has a watchdog timer that returns after some number of cycles if the network doesn't finishes executing in that time.
    task run_network(input integer timer_val);
        begin
            io_nc_start = 1'b1;
            @(posedge clk) #0 io_nc_start = '0;
            for (int i=0; i<timer_val; i++) @(posedge clk) #0 begin
                if (nc_io_done) break;
            end
        end
    endtask
endmodule
