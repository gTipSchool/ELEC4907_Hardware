module sn_uart_rx
    #(
    parameter P_CLKS_PER_BIT =  54, // NEED TO CALCULATE USING CLOCK RATE/BAUD RATE (EX. 10MHz CLK/ 115200 baud = 87)
    parameter P_NUM_BITS_TO_RECEIVE = 10
    )(
    input clk,
    input rst, 

    input rx_enable, // set high by io_controller when the transmit transmit cycle is done and we wait for data to be received 

    input rx_input, // current bit being received, connected to UART interface. Sampled halfway through receiving period (if clks_per_bit = 80 --> sampled at 40)

    output reg [7:0] received_word, // 1 byte register to store the received byte

    output reg rx_done,
    output reg rx_active
    );

    localparam S_IDLE = 2'b00;
    localparam S_WAIT_FOR_FIRST = 2'b01;
    localparam S_FIRST_BIT = 2'b10;
    localparam S_RECEIVE = 2'b11;

    // THESE PARAMETRES ARE BASED ON THE CLKS_PER_BIT AND DETERMINE WHEN THE DATA SAMPLES ARE TAKEN DURING THE TIME THE BIT IS BEING RECEIVED
    localparam SAMPLE_ONE_CLK = int'(P_CLKS_PER_BIT/4);
    localparam SAMPLE_TWO_CLK = 2 * int'(P_CLKS_PER_BIT/4);
    localparam SAMPLE_THREE_CLK = 3 * int'(P_CLKS_PER_BIT/4);

    reg SAMPLE_ONE;
    reg SAMPLE_TWO;
    reg SAMPLE_THREE;
    wire SAMPLE_OR;


    reg [1:0] SM_STATE; // State machine state
    reg [$clog2(P_CLKS_PER_BIT)-1:0] clk_count; // counts the clock cycles that occur during the transmission of 1 bit
    reg [3:0] bit_count; // counts the index of the current bit being sent (starts at 0)

    assign SAMPLE_OR = SAMPLE_ONE | SAMPLE_THREE | SAMPLE_TWO;

    always_ff @(posedge clk) begin

        if (rst) begin
            clk_count <= 0;
            bit_count <= 0;
            received_word <= 0;
            rx_done <= 0;
            rx_active <= 0;
            SM_STATE <= S_IDLE;
        end else begin

            case (SM_STATE)
                S_IDLE: begin

                    rx_done <= 1'b0;
    
                    //Set counts to 0
                    clk_count <= 0;
                    bit_count <= 0;

                    if (rx_enable) begin
                        rx_active <= 1'b1;
                        SM_STATE <= S_WAIT_FOR_FIRST;
                    end else begin
                        SM_STATE <= S_IDLE;
                        rx_active <=1'b0;
                    end
                end

                S_WAIT_FOR_FIRST: begin
                    rx_active <= 1'b1;
                    if (rx_input == 0) begin
                        SM_STATE <= S_FIRST_BIT;
                    end else begin
                        SM_STATE <= S_WAIT_FOR_FIRST;
                        clk_count <= 0;
                    end
                end

                S_FIRST_BIT: begin
                    rx_active <= 1'b1;
                    if (clk_count == SAMPLE_ONE_CLK) begin
                        SAMPLE_ONE <= rx_input;
                        clk_count <= clk_count + 1;
                    end else if (clk_count == SAMPLE_TWO_CLK) begin
                        SAMPLE_TWO <= rx_input;
                        clk_count <= clk_count + 1;
                    end else if (clk_count == SAMPLE_THREE_CLK) begin
                        SAMPLE_THREE <= rx_input;
                        clk_count <= clk_count + 1;
                    end else if (clk_count == P_CLKS_PER_BIT - 1) begin
                        if (SAMPLE_OR == 0) begin
                            SM_STATE <= S_RECEIVE;
                            clk_count <= 0;
                            bit_count <= bit_count +1;
                        end else begin
                            SM_STATE <= S_IDLE;
                            rx_active <= 0; //THIS CONDITION CAN BE USED TO DETECT FAULTS (rx_switches to active but not done)
                            rx_done <= 0;
                            clk_count <= clk_count + 1;
                            
                        end
                    end else
                        clk_count <= clk_count +1;
                end

                S_RECEIVE: begin
                    rx_active <= 1'b1;

                    if (clk_count == SAMPLE_TWO_CLK && bit_count != P_NUM_BITS_TO_RECEIVE - 1) begin
                        received_word[7] <= rx_input;
                        
                    end else if (clk_count == P_CLKS_PER_BIT - 1) begin
                        bit_count <= bit_count + 1;
                        clk_count <= 0;
                        if (bit_count == P_NUM_BITS_TO_RECEIVE - 1) begin
                            SM_STATE <= S_IDLE;
                            rx_active <= 1'b0;
                            rx_done <= 1'b1;
                        end else if (bit_count < P_NUM_BITS_TO_RECEIVE - 2)
                            received_word <= received_word >> 1;
                    end
                    if (clk_count < (P_CLKS_PER_BIT -1))
                        clk_count <= clk_count + 1;
                    else 
                        clk_count <= 0;
                end
                default:
                    SM_STATE <= S_IDLE;
            endcase
        end
    end

endmodule
