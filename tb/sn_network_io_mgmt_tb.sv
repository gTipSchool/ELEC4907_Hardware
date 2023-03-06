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


module sn_network_io_mgmt_tb;
    
    // DUT Parameters:
    localparam P_NUM_NEURONS=21; 
    localparam P_NUM_OUTPUTS=3;
    localparam P_NUM_INPUTS=9;
    localparam P_DFLT_CNTR_VAL=40;
    localparam L_STEP_CNTR_MAX_VAL = 120;
    localparam P_TABLE_NUM_ROWS=4;
    localparam P_TABLE_WEIGHT_BW=9;
    localparam P_NEUR_CURRENT_BW=9;
    localparam P_NEUR_IZH_PRECISION=10; // Number of bits below the decimal point in Izh variables.
    localparam P_NEUR_IZH_HIGH_PREC_EN=0; // Set to 1 if P_NEUR_IZH_PRECISION>10
    localparam P_NEUR_STEP_CNTR_BW=$clog2(L_STEP_CNTR_MAX_VAL+1);
    localparam P_MAX_NUM_PERIODS=50000;
    
    // Parameters for DUT IO widths:
    localparam L_NUM_PARAM_REGS = 2;
    localparam L_NEUR_MEM_ADDR_MSB_BW=$clog2(P_NUM_NEURONS+1);
    localparam L_NEUR_MEM_ADDR_LSB_BW=$clog2(P_TABLE_NUM_ROWS*2+L_NUM_PARAM_REGS);
    localparam L_NEUR_MEM_DATA_BW=P_NEUR_CURRENT_BW;
    
    // Verification Parameters:
    localparam L_NUM_CYCLES_PROT_RW = 2*2;// Number of cycles between each protocol transmission. 87*2 cycles per 8b of transmitted/received data is default.
    localparam L_OUTPUT_IZH_VAR_EN = 1; // Set to enable displaying the Izh variables for select neurons each network evaluation period.
    localparam L_OUTPUT_IZH_VAR_START_NEUR = 1; // The first neuron to output if enabled
    localparam L_OUTPUT_IZH_VAR_END_NEUR = 5; // The last neuron to output if enabled.
    localparam L_TRACK_PERCENT_EXEC = !L_OUTPUT_IZH_VAR_EN; // Set to 1 to calculate % completion during a running network execution.
    
    // State variables (just for visibility in the waves.
    enum {PROT_IDLE,PROT_READ,PROT_WRITE} prot_if_state;
    enum {VERIF_IDLE, VERIF_LOAD_WEIGHTS, VERIF_CHANGE_NUM_PERIODS, VERIF_WAIT_4_TEST_END, VERIF_READ_OUTPUTS, VERIF_READ_DBG_MONITOR} verif_state;
    // Output counter values
    logic [P_NUM_OUTPUTS-1:0] [7:0] received_spike_counters;
    // Storage for all the values read from the debug monitor memory.
    logic [P_MAX_NUM_PERIODS-1:0] [P_NUM_NEURONS-P_NUM_OUTPUTS:1] dbg_mon_storage;
    // The maximum configured execution period.
    logic [15:0] max_period, cur_period;
    
    reg clk, rst;
    
    reg prot_enable, prot_r0w1;
    reg [7-1:0] prot_addr;
    reg [8-1:0] prot_wdata;
    wire [8-1:0] prot_rdata;
    
    wire [P_NUM_NEURONS:1] [P_NEUR_IZH_PRECISION+8-1:0] v_out;
    wire [P_NUM_NEURONS:1] [P_NEUR_IZH_PRECISION+8-1:0] u_out;
    wire nc_evaluate;
    
    sn_network
        #(
        .P_NUM_NEURONS(P_NUM_NEURONS), 
        .P_NUM_OUTPUTS(P_NUM_OUTPUTS),
        .P_NUM_INPUTS(P_NUM_INPUTS),
        .P_DFLT_CNTR_VAL(P_DFLT_CNTR_VAL),
        .P_TABLE_NUM_ROWS(P_TABLE_NUM_ROWS),
        .P_TABLE_WEIGHT_BW(P_TABLE_WEIGHT_BW),
        .P_NEUR_CURRENT_BW(P_NEUR_CURRENT_BW),
        .P_NEUR_IZH_PRECISION(P_NEUR_IZH_PRECISION),
        .P_NEUR_IZH_HIGH_PREC_EN(P_NEUR_IZH_HIGH_PREC_EN),
        .P_MAX_NUM_PERIODS(P_MAX_NUM_PERIODS),
        .P_NEUR_STEP_CNTR_BW(P_NEUR_STEP_CNTR_BW)
        )
    network_DUT (
        .clk(clk),
        .rst(rst),
        .prot_enable(prot_enable),
        .prot_r0w1(prot_r0w1),
        .prot_addr(prot_addr),
        .prot_wdata(prot_wdata),
        .prot_rdata(prot_rdata),
        .nc_evaluate_out(nc_evaluate),
        .v_out(v_out),
        .u_out(u_out)
    );
    
    always #5 clk = ~clk;
    
    initial begin
        // Reset verif variables:
        verif_state = VERIF_IDLE;
        prot_if_state = PROT_IDLE;
        received_spike_counters = '0;
        dbg_mon_storage = '0;
        max_period = P_MAX_NUM_PERIODS;
        cur_period = '0;
        // Reset input regs:
        {clk,rst,prot_enable,prot_r0w1,prot_addr,prot_wdata} = '0;
        rst = 1'b1;
        @(posedge clk) #0 rst = 1'b0;
        @(posedge clk) #0;
        
        if (P_NUM_NEURONS==3) begin: test_neur_prec
        
        end else if (P_NUM_NEURONS==4) begin: test_backprop
            // 21 neurons in our "small" creature model. This has 9 inputs (R1/2/3, C1/2/3, L1/2/3) and 3 outputs (LEFT, FORWARD, RIGHT).
            verif_state = VERIF_LOAD_WEIGHTS;
            load_const_current(1,4);
            
            // Set the weights:
            load_weight(2,0,1,4);
            load_weight(2,1,2,10);
            load_weight(2,2,3,-5);
            load_step_len(10,60);
            
            load_weight(3,0,2,5);
            load_weight(3,1,3,5);
            
            load_weight(4,0,1,5);
            
            // Set the number of evaluation periods:
            verif_state = VERIF_CHANGE_NUM_PERIODS;
            set_num_periods(3000);
            
            // Command the network to start executing and then wait for it to stop:
            verif_state = VERIF_WAIT_4_TEST_END;
            run_execution(100000); // Watchdog timer set to 10000 cycles.
            
            // Evaluate the outputs (read all spike counters and compare them):
            verif_state = VERIF_READ_OUTPUTS;
            evaluate_outputs;
            
            // Read the debug monitor memory:
            verif_state = VERIF_READ_DBG_MONITOR;
            create_dbg_mon_log(1,500);
            
            verif_state = VERIF_IDLE;
        
        end else if (P_NUM_NEURONS==21) begin: test_smplfd_creature
            // 21 neurons in our "small" creature model. This has 9 inputs (R1/2/3, C1/2/3, L1/2/3) and 3 outputs (LEFT, FORWARD, RIGHT).
            verif_state = VERIF_LOAD_WEIGHTS;
            // Setup inputs (overriding initialization to zero):
            // Format is "load_const_current(target_neuron, current)"
           //  Right neurons:
            load_const_current(1,15);
            load_const_current(2,15);
            //load_const_current(3,15);
           // Center neurons:
            //load_const_current(4,4);
            //load_const_current(5,15);
            load_const_current(6,15);
           // Left neurons:
            //load_const_current(7,15);
            //load_const_current(8,15);
            //load_const_current(9,15);
            
            // Set the weights:
            // Format for weights is "load_weight(target_neuron, row_of_weight_table, associated_neuron, weight_value)"
            // Format for changing output step lengths is "load_step_len(target_neuron, new_step_length)"
            //  Neuron 10 (HR): Right first hidden layer. Reacts to all right inputs (1,2,3)
            load_weight(10,0,1,10);
            load_weight(10,1,2,10);
            load_weight(10,2,3,10);
            load_step_len(10,20);
            //  Neuron 11 (HC): Center first hidden layer. Reacts to all center inputs (4,5,6). Also change the output step counter to 120 from 40.
            load_weight(11,0,4,8);
            load_weight(11,1,5,8);
            load_weight(11,2,6,8);
            //load_weight(11,3,11,10);// Make the center neuron reach to itself
            load_step_len(11,L_STEP_CNTR_MAX_VAL);
            //  Neuron 12 (HL): Left first hidden layer. Reacts to all left inputs (7,8,9)
            load_weight(12,0,7,10);
            load_weight(12,1,8,10);
            load_weight(12,2,9,10);
            load_step_len(12,20);
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
            load_step_len(15,20);
            load_const_current(15,3);
            //  Neuron 16 (RANDL). Reacts to LGR(-12), HC(-12), RGL(-12). Also has constant current 4.
            load_weight(16,0,13,-12);
            load_weight(16,1,14,-12);
            load_weight(16,2,11,-12);
            load_step_len(16,20);
            //load_const_current(16,4);
            //  Neuron 17 (RGL2). Reacts to RANDR(5), RGL(10), RANDL(-6), HC(-15)
            load_weight(17,0,15,6);
            load_weight(17,1,13,10);
            load_weight(17,2,16,-6);
            load_weight(17,3,11,-15);
            //  Neuron 18 (LGR2). Reacts to RANDL(5), LGR(10), RANDR(-6), HC(-15)
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
            verif_state = VERIF_CHANGE_NUM_PERIODS;
            set_num_periods(500);
            
            // Command the network to start executing and then wait for it to stop:
            verif_state = VERIF_WAIT_4_TEST_END;
            run_execution(100000); // Watchdog timer set to 10000 cycles.
            
            // Evaluate the outputs (read all spike counters and compare them):
            verif_state = VERIF_READ_OUTPUTS;
            evaluate_outputs;
            
            // Read the debug monitor memory:
            verif_state = VERIF_READ_DBG_MONITOR;
            create_dbg_mon_log(1,1500);
            
            verif_state = VERIF_IDLE;
        end
        
        repeat(10) @(posedge clk) #0;
        $stop;
    end

// This prints the izhikevich variables for specified neurons every execution period if enabled.
// Helpful because the output values can be copied and exported to Excel/MATLAB to be analyzed.
generate
    if (L_OUTPUT_IZH_VAR_EN==1) begin
    
        always @(posedge clk) if (L_OUTPUT_IZH_VAR_EN==1) begin
            if (nc_evaluate) @(posedge clk) #0 begin
                automatic string s="";
                for (int i=L_OUTPUT_IZH_VAR_START_NEUR; i<=L_OUTPUT_IZH_VAR_END_NEUR; i++) begin
                    automatic string s2 = s;
                    $sformat(s, "%s %0d %0d",s2, $signed(v_out[i]),$signed(u_out[i]));
                end
                $display("%s", s);
            end
        end
        
    end
endgenerate
    
    // Call all of these tasks after "@(posedge clk) #0"
    
    // This will write to the address of a register on the protocol interface with some data.
    // Make sure that the addressed register can be written to.
    task prot_write(input integer addr, input bit [7:0] data);
        begin
            prot_if_state = PROT_WRITE;
            prot_enable = 1'b1;
            prot_r0w1 = 1'b1;
            prot_addr = addr;
            prot_wdata = data;
            @(posedge clk) #0;
            {prot_enable,prot_r0w1,prot_addr,prot_wdata} = '0;
            repeat(L_NUM_CYCLES_PROT_RW-1) @(posedge clk) #0;
            prot_if_state = PROT_IDLE;
        end
    endtask
    // This will read from the address of a register on the protocol interface, returning some data.
    // Make sure that the addressed register can be read from.
    task prot_read(input integer addr, output bit [7:0] data);
        begin
            prot_if_state = PROT_READ;
            prot_enable = 1'b1;
            prot_r0w1 = 1'b0;
            prot_addr = addr;
            @(negedge clk) #0 data = prot_rdata;
            @(posedge clk) #0;
            {prot_enable,prot_r0w1,prot_addr} = '0;
            repeat(L_NUM_CYCLES_PROT_RW-1) @(posedge clk) #0;
            prot_if_state = PROT_IDLE;
        end
    endtask
    // This writes to a specified neuron at a specified internal neuron address with a value.
    // It uses the MMU registers at addresses 5-11. First it writes to the address register (prot addresses 6-8),
    // then it writes to the data register (prot addresses 9-11),
    // then it commands the MMU logic to write by writing to the MMU write-enable register (prot address 5).
    task mmu_write(input integer addr_neuron_idx, addr_internal, value);
        begin
            // Format the data and address as 24b because the waddr and wdata registers are 24 bits wide.
            bit [23:0] addr, data;
            // MMU address is simply just a concatenation of the index of the addressed neuron, followed by the 
            // internal address of the addressed register inside the neuron.
            addr = {(L_NEUR_MEM_ADDR_MSB_BW)'(addr_neuron_idx), (L_NEUR_MEM_ADDR_LSB_BW)'(addr_internal)};
            data = value;
            
            // Write the address:
            // Set mmu write address bits.
            if (L_NEUR_MEM_ADDR_MSB_BW+L_NEUR_MEM_ADDR_LSB_BW>16) begin
                // Need to write all 24 bits of the address register.
                prot_write(6,addr[23:16]); // Upper bits of address are at protocol address 6.
            end
            if (L_NEUR_MEM_ADDR_MSB_BW+L_NEUR_MEM_ADDR_LSB_BW>8) begin
                // Need to write the middle bits of the address register.
                prot_write(7,addr[15:8]); // Middle bits of address are at protocol address 7.
            end
            // Always need to write the lower bits of the address register.
            prot_write(8,addr[7:0]); // Lower bits of address are at protocol address 8.
            
            // Write the data:
            if ($clog2(value)>16) begin
                // Need to write all 24 bits of the data register.
                prot_write(9,data[23:16]); // Upper bits of data are at protocol address 9.
            end
            if ($clog2(value)>8) begin
                // Need to write the middle bits of the data register.
                prot_write(10,data[15:8]); // Middle bits of data are at protocol address 10.
            end
            // Always need to write the lower bits of the data register.
            prot_write(11,data[7:0]); // Lower bits of data are at protocol address 11.
            
            // Command the MMU to write it by setting the "we" register to 1'b1:
            prot_write(5,1);
        end
    endtask
    // This starts the test by programming the "start" register with a value of 1.
    // The task then continues to read the "start" register until it reads back a value of 0.
    // Each time it reads "start", if it reads a value of 1 back, it then reads the "current period" register
    // at protocol addresses 1 (MSB) and 2 (LSB) and prints the % execution before reading the "start" register again.
    // There's a watchdog timer that only reads the "start" register for a maximum of watchdog_time 
    // times before returning erroneously.
    task run_execution(input integer watchdog_time);
        begin
            $display("t=%0t - Starting Execution!\n--------------------------------",$time);
            // Write 8'b1 to the "start" register at protocol address 0.
            prot_write(0,1);
            for (int i=0; i<watchdog_time; i++) begin
                bit [7:0] out_val;
                prot_read(0,out_val);
                if (out_val==0) begin
                    $display("t=%0t - Finished Execution!",$time);
                    break;
                end else if (L_TRACK_PERCENT_EXEC==1) begin
                    // There's an issue here where the cur_period changes between reading the LSB and MSB. This causes % to decrease sometimes but is generally okay.
                    // This could be fixed by only reading the MSBs to approximate the %.
                    prot_read(1,cur_period[15:8]);
                    prot_read(2,cur_period[7:0]);
                    $display("t=%0t - %01d%%",$time,cur_period*100/max_period);
                end
            end
            cur_period = '0;
        end
    endtask
    // This writes one weight associated with a neuron to a specific row of the target neurons weight table.
    // This is done through the MMU registers.
    task load_weight(input integer target_neuron, row, assoc_neuron_idx, weight);
        begin
            mmu_write(target_neuron, row*2+2, assoc_neuron_idx);
            mmu_write(target_neuron, row*2+3, weight);
        end
    endtask
    // This writes a constant current to a target neuron.
    // This is done through the MMU registers.
    task load_const_current(input integer target_neuron, current);
        begin
            mmu_write(target_neuron, 0, current);
        end
    endtask
    // This writes a new output step length to a target neuron, changing how long the neuron holds its output for.
    // The default step length is P_DFLT_CNTR_VAL (40 at the time of writing this), so this task overrides the default.
    task load_step_len(input integer target_neuron, count);
        begin
            mmu_write(target_neuron, 1, count);
        end
    endtask
    // This sets the number of execution periods for the network.
    // This is done through the max period register, which is writable through protocol addresses 3 (msb) and 4 (lsb).
    task set_num_periods(input integer value);
        begin
            bit [15:0] data;
            max_period = value;
            data = value;
            // Write upper bits
            prot_write(3,data[15:8]);
            // Write lower bits
            prot_write(4,data[7:0]);
        end
    endtask
    // This reads all the output spike counters for the output neurons and then compares them to determine the dominant output.
    task evaluate_outputs;
        begin
            automatic bit flag = 0;
            automatic int max_idx, max_cnt;
            max_cnt = 0;
            max_idx = -1;
            // Read all the counter values and store them locally:
            for (int i=0; i<P_NUM_OUTPUTS; i++) begin
                // Write to the output select register, selecting the spike counter to read.
                prot_write(12, i);
                // Read from the output counter register, which holds the selected spike counter value.
                prot_read(13,received_spike_counters[i]);
                $display("t=%0t - spike_counter[%0d]=%0d",$time,i,received_spike_counters[i]);
                
                // Compare against current maximum spike count:
                if (received_spike_counters[i] > max_cnt) begin
                    max_idx = i;
                    max_cnt = received_spike_counters[i];
                end
            end
            if (max_idx == -1) begin
                $display("t=%0t - Network Error: No output spikes.\n",$time);
                flag = 1;
            end else for (int i=0; i<P_NUM_OUTPUTS; i++)
                if (received_spike_counters[i] == max_cnt && i!=max_idx) begin 
                    $display("t=%0t - Network Error: No clear output.\n",$time);
                    flag = 1;
                end    
            // Output max value:
            if (!flag) $display("t=%0t - Output Neuron %0d spiked the most with %0d spikes", $time, max_idx, max_cnt);
        end
    endtask
    localparam L_MAX_DBG_MON_PARTIAL_TS_IDX = (P_NUM_NEURONS-P_NUM_OUTPUTS+1)%8==0 ? (P_NUM_NEURONS-P_NUM_OUTPUTS+1)/8 : (P_NUM_NEURONS-P_NUM_OUTPUTS+1)/8 + 1;
    // Read the debug monitor memory withing the specified range, store it locally, and then output it.
    task create_dbg_mon_log(input integer num_periods_start, num_periods_len);
        begin
            automatic bit flag = 0;
            automatic bit [15:0] timestep_2_write = '0;
            
            // Read all the counter values and store them locally:
            for (int i=num_periods_start; i<num_periods_start+num_periods_len; i++) begin
                timestep_2_write = i;
                // Write the timestep:
                prot_write(14,timestep_2_write[15:8]);
                prot_write(15,timestep_2_write[7:0]);
                // Read all of the bits at the timestep and store them:
                for (int j=1; j<=L_MAX_DBG_MON_PARTIAL_TS_IDX; j++) begin
                    // Write to the partial timestep register.
                    prot_write(16,j);
                    // Read the partial timestep and store it.
                    if (i == L_MAX_DBG_MON_PARTIAL_TS_IDX)
                        prot_read(17,dbg_mon_storage[i][P_NUM_NEURONS-P_NUM_OUTPUTS:($clog2((P_NUM_NEURONS-P_NUM_OUTPUTS)/8)-1)*8]);
                    else
                        prot_read(17,dbg_mon_storage[i][j +: 8]);
                end
            end
        end
    endtask
endmodule
