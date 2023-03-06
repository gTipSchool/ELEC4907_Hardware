/*
    sn_network_top_wrapper:
        This is the module we use as top when synthesizing. It instantiates the top network module
        with a configuration specified by the declared localparams.
*/
module sn_network_top_wrapper
    (
     // Top clock and reset.
     input clk_in1_p,
     input clk_in1_n,
     input rst,
     // UART signals
     input rx_input,
     output tx_output
    );

    // Declarations
    //-------------------
    localparam L_DUT_USE_TOP_CFG = 1;
    localparam L_NEUR_MODEL_CFG = 0; // 0=Izhikevich, 1=Integrate & Fire.
    localparam L_NUM_NEURONS=21; // Includes inputs and outputs.
    localparam L_NUM_INPUTS=9;
    localparam L_NUM_OUTPUTS=3;
    localparam L_TABLE_WEIGHT_BW=9;
    localparam L_TABLE_WEIGHT_PRECISION=2;
    localparam integer L_TABLE_NUM_ROWS_ARRAY [L_NUM_NEURONS-L_NUM_INPUTS:1] = {//2,2,2,1};
                                                                                1,//21
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
    localparam L_TABLE_MAX_NUM_ROWS=4;
    localparam L_TABLE_DFLT_NUM_ROWS=L_DUT_USE_TOP_CFG==1?0:L_TABLE_MAX_NUM_ROWS; // Must be 0 if static weights are used. Else it should be equal to L_TABLE_MAX_ROWS
    // Multiply by 2^L_WEIGHT_PRECISION before adding to the list.
    localparam integer L_NEUR_CONST_CURRENT_ARRAY [L_NUM_NEURONS-L_NUM_INPUTS:1] = {//0,0,0,80};
                                                                                    0,//21
                                                                                    0,//20
                                                                                    0,//19
                                                                                    0,//18
                                                                                    0,//17
                                                                                    0,//16
                                                                                    12 *2**L_TABLE_WEIGHT_PRECISION,//15
                                                                                    0,//14
                                                                                    0,//13
                                                                                    0,//12
                                                                                    0,//11
                                                                                    0//10
                                                                                    };
    localparam integer L_NEUR_CNTR_VAL_ARRAY [L_NUM_NEURONS:1] = {//0,0,0,40,40};
                                                                  0,//21
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
    localparam L_NEUR_CURRENT_BW=L_TABLE_WEIGHT_BW+2; // Must be more than L_TABLE_WEIGHT_BW
    localparam L_NEUR_MODEL_PRECISION=10;
    localparam L_NEUR_IZH_HIGH_PREC_EN=0;
    localparam L_DFLT_CNTR_VAL=40;
    localparam L_NEUR_STEP_CNTR_BW=$clog2(200+1);
    localparam L_MAX_NUM_PERIODS=50000;
    localparam L_TABLE_IDX_BW=$clog2(L_NUM_NEURONS-L_NUM_OUTPUTS+1);
    
    //localparam L_CLK_FREQ = 50000000; // 50 MHz
    //localparam L_UART_BAUD_RATE = 912600;
    localparam L_UART_CLKS_PER_BIT=87;//L_CLK_FREQ / L_UART_BAUD_RATE; // Number of prot_clk clock cycles per bit on the UART interface. Depends on baudrate.
    localparam L_UART_BITS_PER_PKT=10; // Total number of bits per UART packet, including the start and end bits.
    localparam L_PROT_WATCHDOG_TIME=L_UART_CLKS_PER_BIT*L_UART_BITS_PER_PKT*100000; // Number of cycles until the HW watchdog timer expires.
    
    // Network
    //-------------------    
generate
    if (L_DUT_USE_TOP_CFG==1) begin: gen_dut_cfg
        
        logic [L_NUM_NEURONS-L_NUM_INPUTS:1] [L_TABLE_MAX_NUM_ROWS-1:0] [L_TABLE_WEIGHT_BW+L_TABLE_IDX_BW-1:0] cfg_table_contents;
        localparam L_CTC_PER_NEUR_BW = L_TABLE_MAX_NUM_ROWS*(L_TABLE_WEIGHT_BW+L_TABLE_IDX_BW); // bit width of the table contents of each neuron.
        
        assign cfg_table_contents = {L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(18),L_TABLE_WEIGHT_BW'(10 *2**L_TABLE_WEIGHT_PRECISION)}), // N21
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(11),L_TABLE_WEIGHT_BW'(8 *2**L_TABLE_WEIGHT_PRECISION)}), // N20
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(17),L_TABLE_WEIGHT_BW'(10 *2**L_TABLE_WEIGHT_PRECISION)}), // N19
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(16),L_TABLE_WEIGHT_BW'(6 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(14),L_TABLE_WEIGHT_BW'(10 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(15),L_TABLE_WEIGHT_BW'(-6 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(11),L_TABLE_WEIGHT_BW'(-15 *2**L_TABLE_WEIGHT_PRECISION)}), // N18
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(15),L_TABLE_WEIGHT_BW'(6 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(13),L_TABLE_WEIGHT_BW'(10 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(16),L_TABLE_WEIGHT_BW'(-6 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(11),L_TABLE_WEIGHT_BW'(-15 *2**L_TABLE_WEIGHT_PRECISION)}), // N17
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(13),L_TABLE_WEIGHT_BW'(-12 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(14),L_TABLE_WEIGHT_BW'(-12 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(11),L_TABLE_WEIGHT_BW'(-12 *2**L_TABLE_WEIGHT_PRECISION)}), // N16
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(13),L_TABLE_WEIGHT_BW'(-12 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(14),L_TABLE_WEIGHT_BW'(-12 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(11),L_TABLE_WEIGHT_BW'(-12 *2**L_TABLE_WEIGHT_PRECISION)}), // N15
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(10),L_TABLE_WEIGHT_BW'(-5 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(11),L_TABLE_WEIGHT_BW'(-20 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(12),L_TABLE_WEIGHT_BW'(5 *2**L_TABLE_WEIGHT_PRECISION)}), // N14
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(10),L_TABLE_WEIGHT_BW'(5 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(11),L_TABLE_WEIGHT_BW'(-20 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(12),L_TABLE_WEIGHT_BW'(-5 *2**L_TABLE_WEIGHT_PRECISION)}), // N13
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(7),L_TABLE_WEIGHT_BW'(10 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(8),L_TABLE_WEIGHT_BW'(10 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(9),L_TABLE_WEIGHT_BW'(10 *2**L_TABLE_WEIGHT_PRECISION)}), // N12
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(4),L_TABLE_WEIGHT_BW'(10 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(5),L_TABLE_WEIGHT_BW'(10 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(6),L_TABLE_WEIGHT_BW'(10 *2**L_TABLE_WEIGHT_PRECISION)}), // N11
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(1),L_TABLE_WEIGHT_BW'(10 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(2),L_TABLE_WEIGHT_BW'(10 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(3),L_TABLE_WEIGHT_BW'(10 *2**L_TABLE_WEIGHT_PRECISION)}) // N10
                                     };
                                    /*{L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(2),L_TABLE_WEIGHT_BW'(10 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(1),L_TABLE_WEIGHT_BW'(15 *2**L_TABLE_WEIGHT_PRECISION)}),//5
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(2),L_TABLE_WEIGHT_BW'(20 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(1),L_TABLE_WEIGHT_BW'(15 *2**L_TABLE_WEIGHT_PRECISION)}),//4
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(2),L_TABLE_WEIGHT_BW'(30 *2**L_TABLE_WEIGHT_PRECISION),
                                                         L_TABLE_IDX_BW'(1),L_TABLE_WEIGHT_BW'(15 *2**L_TABLE_WEIGHT_PRECISION)}),//3
                                     L_CTC_PER_NEUR_BW'({L_TABLE_IDX_BW'(1),L_TABLE_WEIGHT_BW'(30 *2**L_TABLE_WEIGHT_PRECISION)})};//2*/
        sn_network_top_cfg
            #(
            .P_NUM_NEURONS(L_NUM_NEURONS),
            .P_NUM_INPUTS(L_NUM_INPUTS),
            .P_NUM_OUTPUTS(L_NUM_OUTPUTS),
            .P_TABLE_NUM_ROWS_ARRAY(L_TABLE_NUM_ROWS_ARRAY),
            .P_TABLE_MAX_NUM_ROWS(L_TABLE_MAX_NUM_ROWS),
            .P_NEUR_CONST_CURRENT_ARRAY(L_NEUR_CONST_CURRENT_ARRAY),
            .P_NEUR_CNTR_VAL_ARRAY(L_NEUR_CNTR_VAL_ARRAY),
            .P_TABLE_DFLT_NUM_ROWS(L_TABLE_DFLT_NUM_ROWS),
            .P_TABLE_WEIGHT_BW(L_TABLE_WEIGHT_BW),
            .P_TABLE_WEIGHT_PRECISION(L_TABLE_WEIGHT_PRECISION),
            .P_NEUR_CURRENT_BW(L_NEUR_CURRENT_BW),
            .P_NEUR_MODEL_CFG(L_NEUR_MODEL_CFG),
            .P_NEUR_MODEL_PRECISION(L_NEUR_MODEL_PRECISION),
            .P_NEUR_IZH_HIGH_PREC_EN(L_NEUR_IZH_HIGH_PREC_EN),
            .P_DFLT_CNTR_VAL(L_DFLT_CNTR_VAL),
            .P_NEUR_STEP_CNTR_BW(L_NEUR_STEP_CNTR_BW),
            .P_MAX_NUM_PERIODS(L_MAX_NUM_PERIODS),
            .P_UART_CLKS_PER_BIT(L_UART_CLKS_PER_BIT),
            .P_UART_BITS_PER_PKT(L_UART_BITS_PER_PKT),
            .P_PROT_WATCHDOG_TIME(L_PROT_WATCHDOG_TIME),
            .P_CLK_GEN_EN(1)
            )
        network_DUT (
            .clk_in1_p(clk_in1_p),
            .clk_in1_n(clk_in1_n),
            .rst(rst),
            // UART Interface
            .rx_input(rx_input),
            .tx_output(tx_output),
            // CFG
            .cfg_table_contents(cfg_table_contents)
        );
        
    end else begin: gen_dut_normal
    
        sn_network_top
            #(
            .P_NUM_NEURONS(L_NUM_NEURONS),
            .P_NUM_INPUTS(L_NUM_INPUTS),
            .P_NUM_OUTPUTS(L_NUM_OUTPUTS),
            .P_TABLE_NUM_ROWS(L_TABLE_DFLT_NUM_ROWS),
            .P_TABLE_WEIGHT_BW(L_TABLE_WEIGHT_BW),
            .P_TABLE_WEIGHT_PRECISION(L_TABLE_WEIGHT_PRECISION),
            .P_NEUR_CURRENT_BW(L_NEUR_CURRENT_BW),
            .P_NEUR_IZH_PRECISION(L_NEUR_MODEL_PRECISION),
            .P_NEUR_IZH_HIGH_PREC_EN(L_NEUR_IZH_HIGH_PREC_EN),
            .P_DFLT_CNTR_VAL(L_DFLT_CNTR_VAL),
            .P_NEUR_STEP_CNTR_BW(L_NEUR_STEP_CNTR_BW),
            .P_MAX_NUM_PERIODS(L_MAX_NUM_PERIODS),//P_MAX_NUM_PERIODS),
            .P_UART_CLKS_PER_BIT(L_UART_CLKS_PER_BIT),
            .P_UART_BITS_PER_PKT(L_UART_BITS_PER_PKT),
            .P_PROT_WATCHDOG_TIME(L_PROT_WATCHDOG_TIME),
            .P_CLK_GEN_EN(1)
            )
        network_DUT (
            .clk_in1_p(clk_in1_p),
            .clk_in1_n(clk_in1_n),
            .rst(rst),
            // UART Interface
            .rx_input(rx_input),
            .tx_output(tx_output)
        );
        
    end
 endgenerate

endmodule