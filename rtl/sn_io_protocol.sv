`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01/05/2023 09:44:45 AM
// Design Name: 
// Module Name: sn_io_protocol
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


module sn_io_protocol
    #(
      parameter P_CLKS_PER_BIT=10, // Number of prot_clk clock cycles per bit on the UART interface. Depends on baudrate.
      parameter P_BITS_TO_SEND=10,
      parameter P_BITS_TO_RECEIVE=10,
      parameter P_PROT_WATCHDOG_TIME=100 // Number of cycles until the HW watchdog timer expires.
    )
    (
     // Top clock and reset.
     input clk,
     input rst,
     // UART signals
     output logic uart_tx,
     input uart_rx,
     //input cts_input,
     //output logic rts_output,
     // Protocol interface
     output logic prot_enable, // Enable all <prot_*> signals
     output logic prot_r0w1, // 0=read operation, 1=write operation
     output logic [7-1:0] prot_addr, // Register address for reading or writing
     output logic [8-1:0] prot_wdata, // Data for writing
     input [8-1:0] prot_rdata // Data returned during a read. Valid when prot_enable=1 (i.e. no read latency).
    );
    

    reg [$clog2(P_PROT_WATCHDOG_TIME+1)-1:0] counter;
    logic [$clog2(P_PROT_WATCHDOG_TIME+1)-1:0] counter_next;
    
    // IO for the instantiated modules uart_rx.sv and uart_tx.sv:
    logic [7:0] rx_word; // Output from uart_rx.sv
    logic [7:0] tx_word; // input into uart_tx.sv (output from a MUX whose inputs are prot_rdata and rx_word_r).
    logic rx_enable, tx_enable; // Inputs into uart_rx.sv and uart_tx.sv
    logic rx_done, tx_done; // Outputs from uart_rx.sv and uart_tx.sv telling the state machine when they are done tx/rx.
    
    // Buffer for received_word from uart_rx.sv. This is used as a source for prot_r0w1 and prot_addr.
    logic [7:0] rx_word_r, rx_word_r_next;
    logic rx_word_r_en; // Enable for the register.
    
    // FSM state:
    typedef enum bit [2:0] {IDLE,R1,W1,W2,W3} state_t; 
    state_t sm_state, sm_state_next;
    
    sn_uart_rx
        #(
        .P_CLKS_PER_BIT(P_CLKS_PER_BIT),
        .P_NUM_BITS_TO_RECEIVE(P_BITS_TO_RECEIVE)
    )
    uart_rx_DUT (
        .clk(clk),
        .rst(rst),
        .rx_enable(rx_enable),
        .rx_input(uart_rx),
        .received_word(rx_word),
        .rx_done(rx_done)
     );
     
     sn_uart_tx
        #(
        .P_CLKS_PER_BIT(P_CLKS_PER_BIT),
        .P_NUM_BITS_TO_SEND(P_BITS_TO_SEND)
        )
    uart_tx_DUT (
        .clk(clk),
        .rst(rst),
        .tx_enable(tx_enable),
        .data_to_pc(tx_word),
        .tx_output(uart_tx),
        .tx_done(tx_done)
     );
    
    // All registers:
    always_ff @(posedge clk) begin
        if (rst) begin
            counter <= '0;
            sm_state <= IDLE;
            rx_word_r <= '0;
        end else begin
            counter <= counter_next;
            sm_state <= sm_state_next;
            if (rx_word_r_en)
                rx_word_r <= rx_word_r_next;
        end
    end
    
    // All next values for registers and current values for wires:
    always_comb begin
        // Default/else for all wires. They might be overridden later in the always_comb block.
        counter_next = '0;
        sm_state_next = sm_state; // Stay in the current state by default.
        prot_r0w1 = rx_word_r[7]; // Protocol R/W operation specified by the MSB of the buffered received word.
        prot_addr = rx_word_r[6:0]; // Protocol address specified by the 7 lower bits of the buffered received word by default.
        prot_wdata = rx_word; // Protocol write data sourced from the output from the uart_rx.sv module. 
        prot_enable = 1'b0;
        rx_word_r_next = rx_word;
        rx_word_r_en = 1'b0; // Disable latching of the next value of rx_word by default.
        rx_enable = 1'b0; // Disable uart_rx.sv by default.
        tx_enable = 1'b0; // Disable uart_tx.sv by default.
        //rts_output = 1'b0; // By default rts is off unless the uart interface is reading the rx line
        tx_word = '0;
        
        // Cases for each state of the state machine.
        // In each possible case, the defaults above^ may or may not be overwritten.
        case (sm_state)
            // IDLE state. Waiting for RX from computer.
            IDLE: begin
                // Enable the receiver.
                rx_enable = 1'b1;
                // Tell computer it can transmit
                //rts_output = 1'b1;
                if (rx_done) begin
                    // Data has been received.
                    // Disable RX so that the received data isn't overwritten if software for some reason sends two transmissions. (done by default)
                    // Latch the received word into the recieved word buffer (overwrite default):
                    rx_word_r_en = 1'b1;
                    // Disable uart_rx.sv immediately so that it doesn't start trying to receive again.
                    rx_enable = 1'b0;
                    // Next state:
                    //  By default, next state is the read sequence.
                    sm_state_next = R1;
                    if (rx_word[7])
                        // If the MSb of the received word is 1, go into the write sequence.
                        sm_state_next = W1;
                end
            end

            // First state in the write sequence:
            //  Here we have recieved the operation and register address to target. We just need to data to write.
            //  We want to send the same transmission back to the computer.
            W1: begin
                // Supply uart_tx.sv with the word to send (retransmission of what was just received), and enable it.
                tx_word = rx_word_r;
                tx_enable = 1'b1;
                // When uart_tx.sv is done transmitting, disable it and go to the next state in the write sequence.
                if (tx_done) begin
                    tx_enable = 1'b0;
                    sm_state_next = W2;
                end
            end
            
            // Second state in the write sequence:
            //  Here, software has received an acknowledgement (hopefully), and will now send the data to write.
            //  We want to enable the uart_rx.sv module to receive the write data. Once we get it, we can write on the protocol interface.
            //  Also need to use the watchdog counter here to timeout after some amount of time of waiting.
            W2: begin
                // Enable uart_rx.sv and start incrementing the counter.
                rx_enable = 1'b1;
                // Tell computer it can transmit
                //rts_output = 1'b0;
                counter_next = counter + $bits(counter)'(1'd1);
                if (rx_done) begin
                    rx_word_r_en = 1'b1;
                    // If uart_rx.sv has received a word, enable the protocol interface because we now have all the data to
                    // perform a write operation.
                    // (prot_r0w1, prot_addr, and prot_wdata are assigned correctly by default)
                    prot_enable = 1'b1;
                    // Disable uart_rx.sv immediately so that it doesn't start trying to receive again.
                    rx_enable = 1'b0;
                    // Next clock cycle the write sequence will be complete, so we can go back to the IDLE state.
                    sm_state_next = W3;
                end else if (counter == P_PROT_WATCHDOG_TIME) begin
                    // If the counter expires, go back to the idle state.
                    sm_state_next = IDLE;
                end
            end
            // Third state in the write sequence:
            //  Here we have recieved the operation and register address to target. We just need the data to write.
            //  We want to send the same transmission back to the computer.
            W3: begin
                // Supply uart_tx.sv with the word to send (retransmission of what was just received), and enable it.
                tx_word = rx_word_r;
                tx_enable = 1'b1;
                // When uart_tx.sv is done transmitting, disable it and go to the next state in the write sequence.
                if (tx_done) begin
                    tx_enable = 1'b0;
                    sm_state_next = IDLE;
                end
            end
            
            // First state in the read sequence:
            //  Here we have recieved the operation and register address to target.
            //  We have all the information we need to perform a read on the protocol interface.
            //  So, perform the read and send the read data back to the computer.
            R1: begin
                // Enable uart_tx.sv to tell it to start transmitting.
                tx_word = prot_rdata;
                tx_enable = 1'b1;
                
                // Enable the protocol interface to perform the read. Hold it until uart_tx.sv is done transmitting
                // so that the data is present for uart_tx.sv to serialize.
                prot_enable = 1'b1;
                if (tx_done) begin
                    // When uart_tx.sv is done transmitting, the operation is done. Go back to idle.
                    tx_enable = 1'b0;
                    sm_state_next = IDLE;
                end
            end
        endcase
    end
endmodule

