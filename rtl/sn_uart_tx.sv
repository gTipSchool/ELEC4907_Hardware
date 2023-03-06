module sn_uart_tx
    #(
    parameter P_CLKS_PER_BIT =  54, // NEED TO CALCULATE USING CLOCK RATE/BAUD RATE (EX. 10MHz CLK/ 115200 baud = 87)
    parameter P_NUM_BITS_TO_SEND = 10
    )(
    input clk,
    input rst, 
    
    input tx_enable, // signifies that there is data available and ready to transmit
    input [7:0] data_to_pc, // the data that is ready to be transmitted

    output reg tx_output, //output bit seen by UART interfae
    output reg tx_done, //flag to mark that 10 bit word transmission is complete
    output reg tx_active //flag that module is actively sending a word
    );
    
    // 2 state SM
    // IDLE: keep output at 1, set flags and counts to 0, no transmission
    //       When tx_enable is on, set active flag on, package the data (1'b1, data_on_pc, 1"b0) ASK GRANT IF THE DATA_ON_PC SHOULD BE LSB OR MSB FIRST
    //       and change state to transmit
    //Transmit


    localparam S_IDLE = 1'b0; 
    localparam S_TRANSMIT = 1'b1;


    reg [1:0] SM_STATE; // State machine state
    reg [$clog2(P_CLKS_PER_BIT)-1:0] clk_count; // counts the clock cycles that occur during the transmission of 1 bit
    reg [3:0] bit_count; // counts the index of the current bit being sent (starts at 0)
    reg [P_NUM_BITS_TO_SEND-1:0] tx_data; //shift right register for all data bits 

    always_ff @(posedge clk) begin
    
        if (rst) begin
            clk_count <= 0;
            bit_count <= 0;
            tx_data <= 0;
            tx_done <= 0;
            tx_active <= 0;
            tx_output <= 1;
            SM_STATE <= S_IDLE;
        end else begin
            
            case (SM_STATE)
                S_IDLE : begin
                    //keep output high to signify no transmission
                    tx_output <= 1'b1;
    
                    // keep flags at 0
                    
                    tx_done <= 1'b0;
    
                    //Set counts to 0
                    clk_count <= 0;
                    bit_count <= 0;
    
                    if (tx_enable) begin // if data is available
                        tx_active <= 1'b1;
                        tx_data <= {1'b1, data_to_pc, 1'b0};// 0101010101
                        //tx_data <= 10'b0101001101;
//                        tx_data <= data_to_pc;
                        SM_STATE <= S_TRANSMIT;
    
                    end else begin
                        SM_STATE <= S_IDLE;
                        tx_active <=1'b0;
                    end
                end
    
                S_TRANSMIT : begin 
                    tx_active <= 1'b1;
                    tx_output <= tx_data[0];
    
                    if (bit_count < P_NUM_BITS_TO_SEND-1) begin
                        if (clk_count < P_CLKS_PER_BIT - 1) begin
                            clk_count <= clk_count + 1;
                            SM_STATE <= S_TRANSMIT;
    
                        end else begin
                            clk_count <= 0;
                            bit_count <= bit_count + 1;
                            tx_data <= tx_data>>1;
                            SM_STATE <= S_TRANSMIT;
                        end
                    end else begin
                        if (clk_count < P_CLKS_PER_BIT - 1) begin
                            clk_count <= clk_count + 1;    
                            SM_STATE <= S_TRANSMIT;
                        
                        end else begin
                            clk_count <= 0;
                            bit_count <= 0;
                            tx_data <= 0;
                            tx_done <= 1;
                            SM_STATE <= S_IDLE;
    
                        end
                    end 
                end
                default: 
                    SM_STATE <= S_IDLE;
            endcase 
        end
    end
endmodule






