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


module sn_network_top_tb;

    localparam L_CLK_FREQ_MHZ = 50; // MHz
    localparam L_CLK_PERIOD = (10**3)/L_CLK_FREQ_MHZ; // ns
    
    // DUT Parameters:
    localparam L_DUT_USE_TOP_CFG=1; // 1 to use sn_network_top_cfg.sv, 0 to use sn_network_top.sv 
    localparam P_NUM_NEURONS=21; 
    localparam P_NUM_OUTPUTS=3;
    localparam P_NUM_INPUTS=9;
    localparam P_DFLT_CNTR_VAL=40;
    localparam L_STEP_CNTR_MAX_VAL = 200;
    localparam L_TABLE_IDX_BW=$clog2(P_NUM_NEURONS-P_NUM_OUTPUTS+1);
    localparam P_TABLE_DFLT_NUM_ROWS=0; // Set this to 0 if L_DUT_USE_TOP_CFG==1 (this will decrease the size of the neuron internal addresses).
    localparam P_TABLE_WEIGHT_BW=9;
    localparam P_TABLE_WEIGHT_PRECISION=2;
    localparam P_NEUR_CURRENT_BW=9;
    localparam P_NEUR_MODEL_CFG=0;
    localparam P_NEUR_MODEL_PRECISION=10; // Number of bits below the decimal point in Izh variables.
    localparam P_NEUR_IZH_HIGH_PREC_EN=0; // Set to 1 if P_NEUR_IZH_PRECISION>10
    localparam P_NEUR_STEP_CNTR_BW=$clog2(L_STEP_CNTR_MAX_VAL+1);
    localparam P_MAX_NUM_PERIODS=5000;
    localparam P_UART_CLKS_PER_BIT=L_CLK_FREQ_MHZ; // (1M baud)
    localparam P_UART_BITS_PER_PKT=10;
    localparam P_PROT_WATCHDOG_TIME = P_UART_CLKS_PER_BIT*P_UART_BITS_PER_PKT*2;
    
    localparam integer P_TABLE_NUM_ROWS_ARRAY [P_NUM_NEURONS-P_NUM_INPUTS:1] = {1,//21
                                                                                1,//20
                                                                                1,//19
                                                                                4,//18
                                                                                4,//17
                                                                                3,//16
                                                                                3,//15
                                                                                3,//14
                                                                                3,//13
                                                                                3,//12
                                                                                3,//11
                                                                                3//10
                                                                                };
                                                                                // {2,2,2,1}; // For the 5-neuron network.
    localparam P_TABLE_MAX_NUM_ROWS=4;
    // Multiply by 2^L_WEIGHT_PRECISION before adding to the list.
    localparam integer P_NEUR_CONST_CURRENT_ARRAY [P_NUM_NEURONS-P_NUM_INPUTS:1] = {0,//21
                                                                                    0,//20
                                                                                    0,//19
                                                                                    0,//18
                                                                                    0,//17
                                                                                    0,//16
                                                                                    12 *2**P_TABLE_WEIGHT_PRECISION,//15
                                                                                    0,//14
                                                                                    0,//13
                                                                                    0,//12
                                                                                    0,//11
                                                                                    0//10
                                                                                    };
                                                                                    // {0,0,0,80}; // for the 5 neuron network.
    localparam integer P_NEUR_CNTR_VAL_ARRAY [P_NUM_NEURONS:1] = {0,//21
                                                                  0,//20
                                                                  0,//19
                                                                  40,//18
                                                                  40,//17
                                                                  20,//16
                                                                  20,//15
                                                                  40,//14
                                                                  40,//13
                                                                  20,//12
                                                                  200,//11
                                                                  20,//10
                                                                  40,//9
                                                                  40,//8
                                                                  40,//7
                                                                  40,//6
                                                                  40,//5
                                                                  40,//4
                                                                  40,//3
                                                                  40,//2
                                                                  40//1
                                                                  };
                                                                  //{0,0,0,40,40}; // for the 5-neuron network.
    
    // Parameters for DUT IO widths:
    localparam L_NUM_PARAM_REGS = 2;
    localparam L_NEUR_MEM_ADDR_MSB_BW=$clog2(P_NUM_NEURONS+1);
    localparam L_NEUR_MEM_ADDR_LSB_BW=$clog2(P_TABLE_DFLT_NUM_ROWS*2+L_NUM_PARAM_REGS);
    localparam L_NEUR_MEM_DATA_BW=P_NEUR_CURRENT_BW;
    
    // Verification Parameters:
    localparam L_NUM_CYCLES_PROT_RW = 2*2;// Number of cycles between each protocol transmission. 87*2 cycles per 8b of transmitted/received data is default.
    localparam L_OUTPUT_IZH_VAR_EN = 0; // Set to enable displaying the Izh variables for select neurons each network evaluation period.
    localparam L_OUTPUT_IZH_VAR_START_NEUR = 1; // The first neuron to output if enabled.
    localparam L_OUTPUT_IZH_VAR_END_NEUR = 5; // The last neuron to output if enabled.
    localparam L_TRACK_PERCENT_EXEC = !L_OUTPUT_IZH_VAR_EN; // Set to 1 to calculate % completion during a running network execution.
    localparam L_PROT_WATCHDOG_TIME = P_PROT_WATCHDOG_TIME*1.5; // in clock cycles.
    localparam L_PROT_CFG = 0; // =1 for complex acknowledgement protocol, =0 for simpler protocol.
    localparam L_PROT_NUM_RETRIES = 2; // Including the first attempt.
    localparam L_UART_PARITY_EN = 0;
    localparam L_UART_DELAY = P_UART_CLKS_PER_BIT;
    localparam L_PROT_DELAY = 10; // Delay in cycles after each protocol communication sequence (read or write).
    localparam L_UART_FLIP_TX_DATA = 1;
    localparam L_UART_FLIP_RX_DATA = 1;

    // State variables (just for visibility in the waves.
    enum {UART_IDLE, UART_TRANSMITTING, UART_WAIT_4_RESP, UART_RECEIVING} uart_state;
    enum {PROT_IDLE,PROT_SEND_CMD,PROT_WAIT_4_ACK,PROT_ACK_RX,PROT_RETRY_DELAY,
          PROT_W_DATA_TX,PROT_W_WAIT_4_ACK,PROT_W_ACK_RX,PROT_W_DONE,
          PROT_R_RDY_TX,PROT_R_WAIT_4_DATA,PROT_R_DATA_RX,PROT_R_DONE} prot_if_state;
    enum {VERIF_IDLE, VERIF_LOAD_WEIGHTS, VERIF_CHANGE_NUM_PERIODS, VERIF_WAIT_4_TEST_END, VERIF_READ_OUTPUTS, VERIF_READ_DBG_MONITOR} verif_state;
    // Output counter values
    logic [P_NUM_OUTPUTS-1:0] [7:0] received_spike_counters;
    // Storage for all the values read from the debug monitor memory.
    logic [P_MAX_NUM_PERIODS-1:0] [P_NUM_NEURONS-P_NUM_OUTPUTS:1] dbg_mon_storage;
    // The maximum configured execution period.
    logic [15:0] max_period, cur_period;
    // The number of retries protocol read and writes.
    int prot_num_retried_writes, prot_num_retried_reads;
    logic [7:0] uart_tx_word, uart_rx_word;
    logic [$clog2(P_UART_BITS_PER_PKT+1)-1:0] rx_bit, tx_bit;
    
    // DUT pins:
    reg clk, rst;
    reg uart_tx;
    wire uart_rx;
    
    wire [P_NUM_NEURONS:1] [P_NEUR_MODEL_PRECISION+(P_NEUR_MODEL_CFG==0||P_NEUR_MODEL_CFG==0?8:9)-1:0] v_out;
    wire [P_NUM_NEURONS:1] [P_NEUR_MODEL_PRECISION+8-1:0] u_out;
    wire nc_evaluate;
    
generate
    if (L_DUT_USE_TOP_CFG==1) begin: gen_dut_cfg
    
        logic [P_NUM_NEURONS-P_NUM_INPUTS:1] [P_TABLE_MAX_NUM_ROWS-1:0] [P_TABLE_WEIGHT_BW+L_TABLE_IDX_BW-1:0] cfg_table_contents;
        localparam L_CTC_PER_NEUR_BW = P_TABLE_MAX_NUM_ROWS*(P_TABLE_WEIGHT_BW+L_TABLE_IDX_BW); // bit width of the table contents of each neuron.
        
        assign cfg_table_contents = {L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(18),P_TABLE_WEIGHT_BW'(10 *2**P_TABLE_WEIGHT_PRECISION)}), // N21
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(11),P_TABLE_WEIGHT_BW'(8 *2**P_TABLE_WEIGHT_PRECISION)}), // N20
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(17),P_TABLE_WEIGHT_BW'(10 *2**P_TABLE_WEIGHT_PRECISION)}), // N19
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(16),P_TABLE_WEIGHT_BW'(6 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(14),P_TABLE_WEIGHT_BW'(10 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(15),P_TABLE_WEIGHT_BW'(-6 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(11),P_TABLE_WEIGHT_BW'(-15 *2**P_TABLE_WEIGHT_PRECISION)}), // N18
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(15),P_TABLE_WEIGHT_BW'(6 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(13),P_TABLE_WEIGHT_BW'(10 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(16),P_TABLE_WEIGHT_BW'(-6 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(11),P_TABLE_WEIGHT_BW'(-15 *2**P_TABLE_WEIGHT_PRECISION)}), // N17
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(13),P_TABLE_WEIGHT_BW'(-12 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(14),P_TABLE_WEIGHT_BW'(-12 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(11),P_TABLE_WEIGHT_BW'(-12 *2**P_TABLE_WEIGHT_PRECISION)}), // N16
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(13),P_TABLE_WEIGHT_BW'(-12 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(14),P_TABLE_WEIGHT_BW'(-12 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(11),P_TABLE_WEIGHT_BW'(-12 *2**P_TABLE_WEIGHT_PRECISION)}), // N15
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(10),P_TABLE_WEIGHT_BW'(-5 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(11),P_TABLE_WEIGHT_BW'(-20 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(12),P_TABLE_WEIGHT_BW'(5 *2**P_TABLE_WEIGHT_PRECISION)}), // N14
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(10),P_TABLE_WEIGHT_BW'(5 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(11),P_TABLE_WEIGHT_BW'(-20 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(12),P_TABLE_WEIGHT_BW'(-5 *2**P_TABLE_WEIGHT_PRECISION)}), // N13
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(7),P_TABLE_WEIGHT_BW'(10 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(8),P_TABLE_WEIGHT_BW'(10 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(9),P_TABLE_WEIGHT_BW'(10 *2**P_TABLE_WEIGHT_PRECISION)}), // N12
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(4),P_TABLE_WEIGHT_BW'(10 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(5),P_TABLE_WEIGHT_BW'(10 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(6),P_TABLE_WEIGHT_BW'(10 *2**P_TABLE_WEIGHT_PRECISION)}), // N11
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(1),P_TABLE_WEIGHT_BW'(10 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(2),P_TABLE_WEIGHT_BW'(10 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(3),P_TABLE_WEIGHT_BW'(10 *2**P_TABLE_WEIGHT_PRECISION)}) // N10
                                     };
                                     // Below is for the 5-neuron network.
                                     /*{L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(2),P_TABLE_WEIGHT_BW'(10 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(1),P_TABLE_WEIGHT_BW'(15 *2**P_TABLE_WEIGHT_PRECISION)}),//5
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(2),P_TABLE_WEIGHT_BW'(20 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(1),P_TABLE_WEIGHT_BW'(15 *2**P_TABLE_WEIGHT_PRECISION)}),//4
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(2),P_TABLE_WEIGHT_BW'(30 *2**P_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(1),P_TABLE_WEIGHT_BW'(15 *2**P_TABLE_WEIGHT_PRECISION)}),//3
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(1),P_TABLE_WEIGHT_BW'(30 *2**P_TABLE_WEIGHT_PRECISION)})};//2*/
        sn_network_top_cfg
            #(
            .P_NUM_NEURONS(P_NUM_NEURONS),
            .P_NUM_INPUTS(P_NUM_INPUTS),
            .P_NUM_OUTPUTS(P_NUM_OUTPUTS),
            .P_TABLE_NUM_ROWS_ARRAY(P_TABLE_NUM_ROWS_ARRAY),
            .P_TABLE_MAX_NUM_ROWS(P_TABLE_MAX_NUM_ROWS),
            .P_NEUR_CONST_CURRENT_ARRAY(P_NEUR_CONST_CURRENT_ARRAY),
            .P_NEUR_CNTR_VAL_ARRAY(P_NEUR_CNTR_VAL_ARRAY),
            .P_TABLE_DFLT_NUM_ROWS(P_TABLE_DFLT_NUM_ROWS),
            .P_TABLE_WEIGHT_BW(P_TABLE_WEIGHT_BW),
            .P_TABLE_WEIGHT_PRECISION(P_TABLE_WEIGHT_PRECISION),
            .P_NEUR_CURRENT_BW(P_NEUR_CURRENT_BW),
            .P_NEUR_MODEL_CFG(P_NEUR_MODEL_CFG),
            .P_NEUR_MODEL_PRECISION(P_NEUR_MODEL_PRECISION),
            .P_NEUR_IZH_HIGH_PREC_EN(P_NEUR_IZH_HIGH_PREC_EN),
            .P_DFLT_CNTR_VAL(P_DFLT_CNTR_VAL),
            .P_NEUR_STEP_CNTR_BW(P_NEUR_STEP_CNTR_BW),
            .P_MAX_NUM_PERIODS(P_MAX_NUM_PERIODS),
            .P_UART_CLKS_PER_BIT(P_UART_CLKS_PER_BIT),
            .P_UART_BITS_PER_PKT(P_UART_BITS_PER_PKT),
            .P_PROT_WATCHDOG_TIME(P_PROT_WATCHDOG_TIME),
            .P_CLK_GEN_EN(0)
            )
        network_DUT (
            .v_clk(clk),
            .rst(rst),
            .rx_input(uart_tx),
            .tx_output(uart_rx),
            .nc_evaluate_out(nc_evaluate),
            .v_out(v_out),
            .u_out(u_out),
            // Set the FPGA clock to zero. Use the verification clock v_clk instead.
            .clk_in1_p(1'b0),
            .clk_in1_n(1'b0),
            // CFG
            .cfg_table_contents(cfg_table_contents)
        );
        
    end else begin: gen_dut_normal
    
        sn_network_top
            #(
            .P_NUM_NEURONS(P_NUM_NEURONS),
            .P_NUM_INPUTS(P_NUM_INPUTS),
            .P_NUM_OUTPUTS(P_NUM_OUTPUTS),
            .P_TABLE_NUM_ROWS(P_TABLE_DFLT_NUM_ROWS),
            .P_TABLE_WEIGHT_BW(P_TABLE_WEIGHT_BW),
            .P_TABLE_WEIGHT_PRECISION(P_TABLE_WEIGHT_PRECISION),
            .P_NEUR_CURRENT_BW(P_NEUR_CURRENT_BW),
            .P_NEUR_IZH_PRECISION(P_NEUR_MODEL_PRECISION),
            .P_NEUR_IZH_HIGH_PREC_EN(P_NEUR_IZH_HIGH_PREC_EN),
            .P_DFLT_CNTR_VAL(P_DFLT_CNTR_VAL),
            .P_NEUR_STEP_CNTR_BW(P_NEUR_STEP_CNTR_BW),
            .P_MAX_NUM_PERIODS(P_MAX_NUM_PERIODS),
            .P_UART_CLKS_PER_BIT(P_UART_CLKS_PER_BIT),
            .P_UART_BITS_PER_PKT(P_UART_BITS_PER_PKT),
            .P_PROT_WATCHDOG_TIME(P_PROT_WATCHDOG_TIME),
            .P_CLK_GEN_EN(0)
            )
        network_DUT (
            .v_clk(clk),
            .rst(rst),
            .rx_input(uart_tx),
            .tx_output(uart_rx),
            .nc_evaluate_out(nc_evaluate),
            .v_out(v_out),
            .u_out(u_out),
            // Set the FPGA clock to zero. Use the verification clock v_clk instead.
            .clk_in1_p(1'b0),
            .clk_in1_n(1'b0)
        );
        
    end
endgenerate
    
    always #(L_CLK_PERIOD/2) clk = ~clk;
    
    initial begin
        // Reset verif variables:
        uart_state = UART_IDLE;
        verif_state = VERIF_IDLE;
        prot_if_state = PROT_IDLE;
        received_spike_counters = '0;
        dbg_mon_storage = '0;
        max_period = P_MAX_NUM_PERIODS;
        cur_period = '0;
        prot_num_retried_writes = 0;
        prot_num_retried_reads = 0;
        uart_tx_word = '0;
        uart_rx_word = '0;
        rx_bit = '0;
        tx_bit = '0;
        // Reset input regs:
        clk = 1'b0;
        uart_tx = 1'b1;
        rst = 1'b1;
        @(posedge clk) #0 rst = 1'b0;
        repeat(10) @(posedge clk) #0;
        
        if (P_NUM_NEURONS==6) begin: test_neur_4_syn
            
            // Load the weights:
            verif_state = VERIF_LOAD_WEIGHTS;
            
            // Input Neurons:
            //  N1:
            load_const_current(1,15);
            //  N2:
            //load_const_current(2,15);
            
            // Hidden Neurons:
            //  N3: reacts to N1 with step length 100
            load_weight(3,0,1,20);
            load_step_len(3,100);
            //  N4: reacts to N2 with step length 200
            load_weight(4,0,2,15);
            load_step_len(4,200);
            
            // Output Neurons:
            //  N5: reacts to N3 and N4
            load_weight(5,0,3,25);
            load_weight(5,1,4,15);
            //  N6: reacts to N4
            load_weight(6,0,4,14);
            
            // Set the number of evaluation periods:
            verif_state = VERIF_CHANGE_NUM_PERIODS;
            set_num_periods(1025);
            
            // Command the network to start executing and then wait for it to stop:
            verif_state = VERIF_WAIT_4_TEST_END;
            run_execution(100000); // Watchdog timer set to 100000 cycles.
            
            // Evaluate the outputs (read all spike counters and compare them):
            verif_state = VERIF_READ_OUTPUTS;
            evaluate_outputs;
            
            // Read the debug monitor memory:
            //verif_state = VERIF_READ_DBG_MONITOR;
            //create_dbg_mon_log(1,1000);
            
            verif_state = VERIF_IDLE;
        
        end else if (P_NUM_NEURONS==4) begin: test_backprop
            // 21 neurons in our "small" creature model. This has 9 inputs (R1/2/3, C1/2/3, L1/2/3) and 3 outputs (LEFT, FORWARD, RIGHT).
            verif_state = VERIF_LOAD_WEIGHTS;
            load_const_current(1,15);
            
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
            if (L_DUT_USE_TOP_CFG==0) begin // No need to load weights if the _cfg network is used.
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
            end
            
            // Set the number of evaluation periods:
            verif_state = VERIF_CHANGE_NUM_PERIODS;
            set_num_periods(5000);
            
            // Command the network to start executing and then wait for it to stop:
            verif_state = VERIF_WAIT_4_TEST_END;
            run_execution(100000); // Watchdog timer set to 10000 cycles.
            
            // Evaluate the outputs (read all spike counters and compare them):
            verif_state = VERIF_READ_OUTPUTS;
            evaluate_outputs;
            
            verif_state = VERIF_LOAD_WEIGHTS;
            load_const_current(1,0);
            load_const_current(2,0);
            load_const_current(3,15);
           // Center neurons:
            load_const_current(4,0);
            load_const_current(5,0);
            load_const_current(6,0);
           // Left neurons:
            load_const_current(7,0);
            load_const_current(8,15);
            load_const_current(9,15);
            
            // Command the network to start executing and then wait for it to stop:
            verif_state = VERIF_WAIT_4_TEST_END;
            run_execution(100000); // Watchdog timer set to 10000 cycles.
            
            // Evaluate the outputs (read all spike counters and compare them):
            verif_state = VERIF_READ_OUTPUTS;
            evaluate_outputs;
            
            verif_state = VERIF_LOAD_WEIGHTS;
            load_const_current(1,15);
            load_const_current(2,0);
            load_const_current(3,15);
           // Center neurons:
            load_const_current(4,0);
            load_const_current(5,15);
            load_const_current(6,0);
           // Left neurons:
            load_const_current(7,0);
            load_const_current(8,15);
            load_const_current(9,15);
            
            // Command the network to start executing and then wait for it to stop:
            verif_state = VERIF_WAIT_4_TEST_END;
            run_execution(100000); // Watchdog timer set to 10000 cycles.
            
            // Evaluate the outputs (read all spike counters and compare them):
            verif_state = VERIF_READ_OUTPUTS;
            evaluate_outputs;
            
            // Read the debug monitor memory:
            //verif_state = VERIF_READ_DBG_MONITOR;
            //create_dbg_mon_log(1,1000);
            
            verif_state = VERIF_IDLE;
        end else begin
            
            // This was a test for the 5-neuron network.
            // It was used to compare the results between FPGA implementation and simulation.
            //----------------------------------------------------------------
            load_const_current(1,0);
            
            verif_state = VERIF_CHANGE_NUM_PERIODS;
            set_num_periods(5000);
            
            for (int i=0; i<6; i++) begin
                if (i%3==0)
                    load_const_current(1,0);
                else if (i%3==1)
                    load_const_current(1,10);
                else
                    load_const_current(1,20);
                if (i==3)
                    set_num_periods(500);
                    
                // Command the network to start executing and then wait for it to stop:
                verif_state = VERIF_WAIT_4_TEST_END;
                run_execution(100000); // Watchdog timer set to 10000 cycles.
                
                // Evaluate the outputs (read all spike counters and compare them):
                verif_state = VERIF_READ_OUTPUTS;
                evaluate_outputs;
                
                
            end
            //verif_state = VERIF_READ_DBG_MONITOR;
            //create_dbg_mon_log(1,500);
            
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
    
    // This task will send P_UART_BITS_PER_PKT-3 (3 because start bit, parity bit, and stop bit) bits 
    // of data to the network using the UART bus.
    task uart_transmit(input bit [P_UART_BITS_PER_PKT-3-L_UART_PARITY_EN:0] pkt_data);
        begin
            uart_state = UART_TRANSMITTING;
            uart_tx_word = pkt_data;
            if (L_UART_PARITY_EN==1) begin
                for (int i=P_UART_BITS_PER_PKT-1; i>=0; i--) begin
                    case(i)
                        (P_UART_BITS_PER_PKT-1): // Start bit
                            uart_tx = 1'b0;
                        1: // Parity bit
                            uart_tx = ^pkt_data;
                        0: // Stop bit
                            uart_tx = 1'b1;
                        default: // Data
                            uart_tx = pkt_data[i-2];
                    endcase
                    tx_bit = i+1;
                    repeat(P_UART_CLKS_PER_BIT) @(posedge clk) #0;
                end
            end else begin
                if (L_UART_FLIP_TX_DATA==1) begin // Flip the data
                    for (int i=0; i<P_UART_BITS_PER_PKT; i++) begin
                        case(i)
                            0: // Start bit
                                uart_tx = 1'b0;
                            (P_UART_BITS_PER_PKT-1): // Stop bit
                                uart_tx = 1'b1;
                            default: // Data
                                uart_tx = pkt_data[i-1];
                        endcase
                        tx_bit = i+1;
                        repeat(P_UART_CLKS_PER_BIT) @(posedge clk) #0;
                    end
                end else begin
                    for (int i=P_UART_BITS_PER_PKT-1; i>=0; i--) begin
                        case(i)
                            (P_UART_BITS_PER_PKT-1): // Start bit
                                uart_tx = 1'b0;
                            0: // Stop bit
                                uart_tx = 1'b1;
                            default: // Data
                                uart_tx = pkt_data[i-1];
                        endcase
                        tx_bit = i+1;
                        repeat(P_UART_CLKS_PER_BIT) @(posedge clk) #0;
                    end
                end
            end
            uart_state = UART_IDLE;
            uart_tx_word = '0;
            tx_bit = '0;
        end
        //repeat(L_UART_DELAY) @(posedge clk) #0;
    endtask
    
    // This task will wait to receive P_UART_BITS_PER_PKT-3 bits of data from the network
    // over the UART bus.
    task uart_receive(input integer watchdog_time, output bit [P_UART_BITS_PER_PKT-3-L_UART_PARITY_EN:0] pkt_data, output bit err);
        begin
            automatic bit flag = 0;
            err = 1'b1; // Default. Overriden if no error.
            
            uart_state = UART_WAIT_4_RESP;
            
            if (L_UART_PARITY_EN==1) begin
                for (int i = 0; i<watchdog_time; i++) begin
                    if (uart_rx == 1'b0) begin
                        flag = 1'b1;
                        break;
                    end
                    @(posedge clk) #0;
                end
                if (flag == 1'b0) begin
                    uart_state = UART_IDLE;
                    $display("t=%0t - ERROR: Watchdog timer expired while waiting for RX.",$time);
                    return;
                end
                rx_bit = P_UART_BITS_PER_PKT;
                uart_state = UART_RECEIVING;
                
                // Delay until halfway through the first data bit of the packet.
                repeat(P_UART_CLKS_PER_BIT*3/2) @(posedge clk) #0;
                
                // Start deserializing data
                for (int i=P_UART_BITS_PER_PKT-2; i>=0; i--) begin
                    case(i)
                        1: // Parity bit
                            if (uart_rx != ^pkt_data) begin// Error out if there is a parity mismatch.
                                uart_state = UART_IDLE;
                                $display("t=%0t - ERROR: Parity mismatch after RX.",$time);
                                return;
                            end
                        0: // Stop bit
                            if (uart_rx != 1'b1) begin // Error out if there is no stop bit where it is expected.
                                uart_state = UART_IDLE;
                                $display("t=%0t - ERROR: No stop bit observed after RX.",$time);
                                return;
                            end
                        default: // Data
                            begin
                                pkt_data[i-2] = uart_rx;
                                uart_rx_word = pkt_data;
                            end
                    endcase
                    rx_bit = i+1;
                    repeat(P_UART_CLKS_PER_BIT) @(posedge clk) #0;
                end
            end else begin
                for (int i = 0; i<watchdog_time; i++) begin
                    if (uart_rx == 1'b0) begin
                        flag = 1'b1;
                        break;
                    end
                    @(posedge clk) #0;
                end
                if (flag == 1'b0) begin
                    uart_state = UART_IDLE;
                    $display("t=%0t - ERROR: Watchdog timer expired while waiting for RX.",$time);
                    return;
                end
                rx_bit = L_UART_FLIP_TX_DATA==1 ? 1 : P_UART_BITS_PER_PKT;
                uart_state = UART_RECEIVING;
                // Delay until halfway through the first data bit of the packet.
                repeat(P_UART_CLKS_PER_BIT*3/2) @(posedge clk) #0;
                
                // Start deserializing data
                if (L_UART_FLIP_TX_DATA==1) begin // Flip the data
                    for (int i=1; i<P_UART_BITS_PER_PKT-1; i++) begin
                        case(i)
                            P_UART_BITS_PER_PKT-1: // Stop bit
                                if (uart_rx != 1'b1) begin // Error out if there is no stop bit where it is expected.
                                    uart_state = UART_IDLE;
                                    $display("t=%0t - ERROR: No stop bit observed after RX.",$time);
                                    return;
                                end
                            default: // Data
                                begin
                                    pkt_data[i-1] = uart_rx;
                                    uart_rx_word = pkt_data;
                                end
                        endcase
                        rx_bit = i;
                        repeat(P_UART_CLKS_PER_BIT) @(posedge clk) #0;
                    end
                end else begin
                    for (int i=P_UART_BITS_PER_PKT-2; i>=0; i--) begin
                        case(i)
                            0: // Stop bit
                                if (uart_rx != 1'b1) begin // Error out if there is no stop bit where it is expected.
                                    uart_state = UART_IDLE;
                                    $display("t=%0t - ERROR: No stop bit observed after RX.",$time);
                                    return;
                                end
                            default: // Data
                                begin
                                    pkt_data[i-1] = uart_rx;
                                    uart_rx_word = pkt_data;
                                end
                        endcase
                        rx_bit = i+1;
                        repeat(P_UART_CLKS_PER_BIT) @(posedge clk) #0;
                    end
                end
            end
            err = 1'b0;
            uart_state = UART_IDLE;
            uart_rx_word = '0;
            rx_bit = '0;
        end
        repeat(L_UART_DELAY) @(posedge clk) #0;
    endtask
    
    // This task will write to the address of a register on the protocol interface with some data.
    // It goes through the protocol specified in Communication Protocol.drawio from POV of PC.
    task prot_write(input integer addr, input bit [7:0] data);
        begin
            automatic bit uart_err, prot_err;
            automatic bit [7:0] last_tx, last_rx;
            prot_err = 1'b1; // Default. Overriden if no error.
            
            //  During a write, just send 8bits to start, with the 7th bit set, and bits 6-0 containing the register address.
            //  Then wait for a response from the hardware. When we get one, check that the data rx is the same the data tx.
            //  Then transmit the write data.
            //  Then recieve the data back as an acknowledgement.
            for (int i=0; i<L_PROT_NUM_RETRIES; i++) begin
                prot_if_state = PROT_SEND_CMD;
                last_tx = {1'b1, 7'(addr)};
                uart_transmit(last_tx); // first transmission: operation and reg addr (r0w1)

                prot_if_state = PROT_WAIT_4_ACK;
                uart_receive(L_PROT_WATCHDOG_TIME, last_rx, uart_err);
                if (uart_err) begin
                    prot_num_retried_writes++;
                    $display("\tProtocol write attempt %0d failed (CMD).",i);
                    // DELAY so that the HW watchdog timer expires.
                    prot_if_state = PROT_RETRY_DELAY;
                    repeat(L_PROT_WATCHDOG_TIME) @(posedge clk) #0;
                    continue;
                end else if (last_rx != last_tx) begin
                    prot_num_retried_writes++;
                    $display("t=%0t - ERROR: Mismatch between CMD TX and ack CMD RX during write\n\tTX cmd=%b, RX cmd=%b\n\tProtocol write attempt %0d failed.",$time,last_tx,last_rx,i);
                    prot_if_state = PROT_RETRY_DELAY;
                    repeat(L_PROT_WATCHDOG_TIME) @(posedge clk) #0;
                    continue;
                end
                
                prot_if_state = PROT_W_DATA_TX;
                last_tx = data;
                uart_transmit(last_tx); // Second transmission: data
                
                prot_if_state = PROT_WAIT_4_ACK;
                uart_receive(L_PROT_WATCHDOG_TIME, last_rx, uart_err);
                if (uart_err) begin
                    prot_num_retried_writes++;
                    $display("\tProtocol write attempt %0d failed (CMD).",i);
                    // DELAY so that the HW watchdog timer expires.
                    prot_if_state = PROT_RETRY_DELAY;
                    repeat(L_PROT_WATCHDOG_TIME) @(posedge clk) #0;
                    continue;
                end else if (last_rx != last_tx) begin
                    prot_num_retried_writes++;
                    $display("t=%0t - ERROR: Mismatch between DATA TX and ack DATA RX during write\n\tTX data=%b, RX data=%b\n\tProtocol write attempt %0d failed.",$time,last_tx,last_rx,i);
                    prot_if_state = PROT_RETRY_DELAY;
                    repeat(L_PROT_WATCHDOG_TIME) @(posedge clk) #0;
                    continue;
                end
                // Successful write.
                prot_err = 1'b0;
                break;
            end
            
            // No recovery if all retries fail. Stop the simulation.
            if (prot_err) begin
                $display("t=%0t - CRITICAL ERROR: Maximum number of protocol write retries reached.",$time);
                repeat(10) @(posedge clk) #0;
                $stop;
            end
            prot_if_state = PROT_IDLE;
            repeat(L_PROT_DELAY) @(posedge clk) #0;
        end
    endtask

    // This will read from the address of a register on the protocol interface, returning some data.
    // It goes through the protocol specified in Communication Protocol.drawio from POV of PC.
    task prot_read(input integer addr, output bit [7:0] data);
        begin
            automatic bit uart_err, prot_err;
            automatic bit [7:0] last_tx, last_rx;

            prot_err = 1'b1; // Default. Overridden if no error.
            
            if (L_PROT_CFG==1) begin
                // Complex protocol configured.
                for (int i=0; i<L_PROT_NUM_RETRIES; i++) begin
                    prot_if_state = PROT_SEND_CMD;
                    last_tx = {1'b0, 7'(addr)};
                    uart_transmit(last_tx); // first transmission: operation and reg addr (r0w1)
    
                    prot_if_state = PROT_WAIT_4_ACK;
                    uart_receive(L_PROT_WATCHDOG_TIME, last_rx, uart_err);
                    if (uart_err) begin
                        prot_num_retried_reads++;
                        $display("\tProtocol read attempt %0d failed (CMD).",i);
                        // DELAY so that the HW watchdog timer expires.
                        prot_if_state = PROT_RETRY_DELAY;
                        repeat(L_PROT_WATCHDOG_TIME) @(posedge clk) #0;
                        continue;
                    end else if (last_rx != last_tx) begin
                        prot_num_retried_reads++;
                        $display("t=%0t - ERROR: Mismatch between CMD TX and ack CMD RX during read\n\tTX cmd=%b, RX=%b\n\tProtocol read attempt %0d failed.",$time,last_tx,last_rx,i);
                        continue;
                    end
    
                    prot_if_state = PROT_R_RDY_TX;
                    last_tx = 8'b11000011;
                    uart_transmit(last_tx); // Second transmission: ready message
                    
                    prot_if_state = PROT_R_WAIT_4_DATA;
                    uart_receive(L_PROT_WATCHDOG_TIME, last_rx, uart_err);
                    if (uart_err) begin
                        prot_num_retried_reads++;
                        $display("\tProtocol write attempt %0d failed (DATA).",i);
                        continue;
                    end
    
                    // Successful read.
                    prot_err = 1'b0;
                    break;
                end
            
            end else begin
                // Simple protocol configured.
                for (int i=0; i<L_PROT_NUM_RETRIES; i++) begin
                    prot_if_state = PROT_SEND_CMD;
                    last_tx = {1'b0, 7'(addr)};
                    uart_transmit(last_tx); // first transmission: operation and reg addr (r0w1)
                    
                    prot_if_state = PROT_R_WAIT_4_DATA;
                    uart_receive(L_PROT_WATCHDOG_TIME, last_rx, uart_err);
                    if (uart_err) begin
                        prot_num_retried_reads++;
                        $display("\tProtocol write attempt %0d failed.",i);
                        continue;
                    end
    
                    // Successful read.
                    prot_err = 1'b0;
                    break;
                end
                
            end
            
            // No recovery if all retries fail. Stop the simulation.
            if (prot_err) begin
                $display("t=%0t - CRITICAL ERROR: Maximum number of protocol read retries reached.",$time);
                repeat(10) @(posedge clk) #0;
                $stop;
            end else
                data = last_rx;
            prot_if_state = PROT_IDLE;
            repeat(L_PROT_DELAY) @(posedge clk) #0;
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
            addr = {/*(L_NEUR_MEM_ADDR_MSB_BW)'*/(addr_neuron_idx), (/*L_NEUR_MEM_ADDR_LSB_BW*/8)'(addr_internal)};
            data = value;
            
            // Write the address:
            prot_write(6,addr[23:16]); // Upper bits of address are at protocol address 6.
            prot_write(7,addr[15:8]); // Middle bits of address are at protocol address 7.
            prot_write(8,addr[7:0]); // Lower bits of address are at protocol address 8.
            
            // Write the data:
            prot_write(9,data[23:16]); // Upper bits of data are at protocol address 9.
            prot_write(10,data[15:8]); // Middle bits of data are at protocol address 10.
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
            mmu_write(target_neuron, row*2+3, weight*(2**P_TABLE_WEIGHT_PRECISION));
        end
    endtask

    // This writes a constant current to a target neuron.
    // This is done through the MMU registers.
    task load_const_current(input integer target_neuron, current);
        begin
            mmu_write(target_neuron, 0, current*(2**P_TABLE_WEIGHT_PRECISION));
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
                    if (i == (P_NUM_NEURONS-P_NUM_OUTPUTS)/8-1 && 
                        ((P_NUM_NEURONS-P_NUM_OUTPUTS)%8)>0)
                        prot_read(17,dbg_mon_storage[i][P_NUM_NEURONS-P_NUM_OUTPUTS : P_NUM_NEURONS-P_NUM_OUTPUTS-((P_NUM_NEURONS-P_NUM_OUTPUTS)%8)+1]);
                    else
                        prot_read(17,dbg_mon_storage[i][j +: 8]);
                end
            end
        end
    endtask
endmodule
