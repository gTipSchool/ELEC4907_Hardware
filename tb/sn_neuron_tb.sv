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


module sn_neuron_tb;
    
    localparam P_NEUR_CFG = 1; // The configuration of the neuron - 0:input,1:hidden,2:output
    localparam P_NUM_NEURONS=100; 
    localparam P_NUM_OUTPUTS=3;
    localparam P_DFLT_CNTR_VAL=10;
    localparam P_TABLE_NUM_ROWS=32;
    localparam P_TABLE_WEIGHT_BW=7;
    localparam P_NEUR_CURRENT_BW=9;
    localparam P_NEUR_MEM_ADDR_BW=$clog2(P_TABLE_NUM_ROWS)>P_NEUR_CURRENT_BW ? $clog2(P_TABLE_NUM_ROWS) : P_NEUR_CURRENT_BW;
    localparam P_NEUR_MEM_DATA_BW=18;
    localparam P_NEUR_STEP_CNTR_BW=$clog2(100);
    localparam P_NEUR_INDEX=1;
    
    reg clk, rst, nc_evaluate, nc_reset;
    // Input Controller
    reg [P_NEUR_CURRENT_BW-1:0] io_input; // FIXME load inputs via const currents?
    // Output Evaluation
    wire neur_output;
    // Axon Protocol Interface
    reg api_vld;
    reg api_granted;
    wire api_pending;
    wire [$clog2(P_NUM_NEURONS-P_NUM_OUTPUTS+1)-1:0] api_bus;
    reg [$clog2(P_NUM_NEURONS-P_NUM_OUTPUTS+1)-1:0] api_bus_value;
    // Memory Interface
    reg m_we;
    reg [P_NEUR_MEM_ADDR_BW-1:0] m_waddr;
    reg [P_NEUR_MEM_DATA_BW-1:0] m_wdata;
    // TB Regs 
    reg [P_TABLE_NUM_ROWS-1:0] firing;
    
    sn_neuron
        #(.P_NEUR_CFG(P_NEUR_CFG),
        .P_NUM_NEURONS(P_NUM_NEURONS), 
        .P_NUM_OUTPUTS(P_NUM_OUTPUTS),
        .P_DFLT_CNTR_VAL(P_DFLT_CNTR_VAL),
        .P_TABLE_NUM_ROWS(P_TABLE_NUM_ROWS),
        .P_TABLE_WEIGHT_BW(P_TABLE_WEIGHT_BW),
        .P_NEUR_CURRENT_BW(P_NEUR_CURRENT_BW),
        .P_NEUR_MEM_ADDR_BW(P_NEUR_MEM_ADDR_BW),
        .P_NEUR_MEM_DATA_BW(P_NEUR_MEM_DATA_BW),
        .P_NEUR_STEP_CNTR_BW(P_NEUR_STEP_CNTR_BW),
        .P_NEUR_INDEX(P_NEUR_INDEX)
        )
    neuron_DUT (
        .clk(clk),
        .rst(rst),
        .nc_evaluate(nc_evaluate),
        .nc_reset(nc_reset),
        .io_input(io_input),
        .neur_output(neur_output),
        .api_vld(api_vld),
        .api_granted(api_granted),
        .api_pending(api_pending),
        .api_bus(api_bus),
        .m_we(m_we),
        .m_waddr(m_waddr),
        .m_wdata(m_wdata)
    );
    
    initial clk = 1'b0;
    always #5 clk = ~clk;
    
    
    initial begin
        {rst, nc_evaluate, nc_reset, m_we, m_waddr, m_wdata, api_vld, api_granted, io_input, api_bus_value, firing} = '0;
        rst = 1'b1;
        nc_reset = 1'b1;
        @(posedge clk) #0 rst = 1'b0; nc_reset = 1'b0;
        if (P_NEUR_CFG == 0) begin
            // Input layer neuron: 
            
            //  Test the izhikevich model with different currents:
            @(posedge clk) #0 nc_evaluate = 1'b1;
            change_current(10,500);
            change_current(20,500);
            change_current(50,500);
            change_current(100,500);
            change_current(0,300);
            // Change the counter value to 50:
            mem_if_write(1,50);
            // Modify the current again to see if the counter works:
            change_current(10,500);
            change_current(0,300);
            // Change counter value back to 10.
            mem_if_write(1,10);
            
        end else if (P_NEUR_CFG == 1) begin
            // Hidden layer neuron: 
            
            //  Load in weights:
            for (int i=0; i<P_TABLE_NUM_ROWS; i++) begin
                // Write the index:
                mem_if_write(2*i+2,i+1);
                // Write the weight: Each weight will be the same value as the neuron index multiplied by 2.
                mem_if_write(2*i+3,4);//(i+1));
            end
            /*mem_if_write(2,10);
            mem_if_write(3,5);
            mem_if_write(4,100);
            mem_if_write(5,7);*/
            // Evaluate for 2000 cycles just to "wake up" the neuron ODE:
            nc_evaluate = 1'b1;
            repeat(200) @(posedge clk) #0;
            nc_evaluate = 1'b0;
            
            //  T-E periods: simulate many neurons firing and stopping for various spans all at the same time on the API bus.
            firing[0] = 1'b1;
            fork 
                begin
                    for(int i=0; i<P_TABLE_NUM_ROWS; i++) begin
                        fork
                            automatic int j = i;
                            begin
                            
                                repeat(j*200) @(posedge clk) #0;
                                firing[j] = 1'b1;
                                repeat((P_TABLE_NUM_ROWS-j)*100+200) @(posedge clk) #0;
                                firing[j] = 1'b0;
                                
                            end
                        join_none
                    end
                    wait fork;
                end
                begin
                    while (|firing) begin
                        // Transmit
                        for (int i=0; i<P_TABLE_NUM_ROWS; i++)
                            if (firing[i])
                                api_bus_input(i+1);
                        // Evaluate
                        evaluate;
                    end
                end
            join
            repeat(1000) @(posedge clk);
            
        end else begin
            // Output layer neuron:
            
            
        end
        $stop;
    end
    assign api_bus = api_vld ? api_bus_value : 'Z;
    
    task change_current(input integer new_current, num_clks);
        begin
            #0 io_input = new_current;
            repeat(num_clks) @(posedge clk) #0;
        end
    endtask
    
    // Call this after "@(posedge clk) #0"
    task mem_if_write(input integer addr, value);
        begin
            m_we = 1'b1;
            m_waddr = addr; // Address for weight in second row of weight table.
            m_wdata = value; // Set weight for "neuron" 100 to 20.
            @(posedge clk) #0;
            {m_we,m_waddr,m_wdata} = '0;
        end
    endtask
    
    task api_bus_input(input integer neuron_idx);
        begin
            api_vld = 1'b1;
            api_bus_value = neuron_idx;
            @(posedge clk) #0;
            {api_vld,api_bus_value} = '0;
        end
    endtask
    
    task evaluate;
        begin
            nc_evaluate = 1'b1;
            @(posedge clk) #0;
            nc_evaluate = 1'b0;
        end
    endtask
endmodule
