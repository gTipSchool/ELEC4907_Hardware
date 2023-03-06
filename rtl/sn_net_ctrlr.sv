/*
    sn_net_ctrlr:
    Controls the execution of the network, as prompted to start
    by software.
    Commands all neurons to evaluate during evaluation periods,
    and commands the API controller to allow transmission of spike
    statuses during the transmit period.
    After the configured number of execution periods (eval and trans.),
    the network controller then changes a status bit to inform
    software that the execution has completed.
*/
module sn_net_ctrlr
    #(
        parameter P_NUM_NEURONS=100,
        parameter P_NUM_INPUTS=45,
        parameter P_NUM_OUTPUTS=3,
        parameter P_MAX_NUM_PERIODS=100
    )
    (
        // Generic
        input clk,
        input rst,
        // Neurons
        output logic nc_evaluate, // Asserted during the 1 cycle eval period.
        output logic nc_reset, // Asserted at the start of execution.
        // IO Manager
        output logic nc_warmup,
        // API Controller
        output logic nc_transmit, // Held during transmit period.
        input api_nc_done, // API asserts this to tell NC that transmit is done.
        // IO Manager
        //  Configurable number of execution periods:
        input [$clog2(P_MAX_NUM_PERIODS+1)-1:0] io_nc_max_per,
        //  Current period number for status
        output logic [$clog2(P_MAX_NUM_PERIODS+1)-1:0] nc_io_cur_per,
        //  Start signal from software. Asserted to start execution.
        input io_nc_start,
        //  Final evaluation signal to tell when exe is done.
        output logic nc_io_done
    );

    // Declarations:
    //------------------
    // Warmup logic.
    // This evaluates some number of times before the start of a test to "wake up" the network.
    localparam NUM_EVAL_PER_B4_START = 100;
    reg [$clog2(NUM_EVAL_PER_B4_START+1)-1:0] warmup_cntr;
    wire [$clog2(NUM_EVAL_PER_B4_START+1)-1:0] warmup_cntr_nxt;
    wire warmup, start_d;
    // Period registers/counters - current and configured max period.
    logic [$clog2(P_MAX_NUM_PERIODS+1)-1:0] cur_period, cur_period_nxt;
    // Execution FSM signals.
    reg trans1_eval0;
    wire final_per;
    reg done, done_d;
    
    
    // Warmup Logic:
    always_ff @(posedge clk) begin
        if (rst) begin
            warmup_cntr <= '0;
        end else if (warmup || io_nc_start) begin
            warmup_cntr <= warmup_cntr_nxt;
        end
    end
    
    assign warmup = |warmup_cntr;
    assign start_d = warmup_cntr == $bits(warmup_cntr)'('d1);
    assign warmup_cntr_nxt = io_nc_start ? $bits(warmup_cntr_nxt)'(NUM_EVAL_PER_B4_START) : warmup_cntr - 'd1;
    

    // Sequence of Events: io_nc_start -> E -> T -> E -> T -> ... -> E -> T -> E -> nc_io_done
    // E=Evaluate, T=Transmit
    // ---------------------------------------------------------------------------------------
    // Expected signal values:
    //               done:           1    0    0    0    0           0    0    0    1    1
    //               done_d:         1    1    0    0    0           0    0    0    0    1
    //               cur_period:     0    1    1    2    2           99   99   100  100  100
    //               max_period:     100  100  100  100  100         100  100  100  100  100
    //               trans1_eval0:   0    0    1    0    1           0    1    0    1    0
    //               final_per:      X    0    0    0    0           0    0    1    1    1
    //                                                                                 |___|
    //                                                                                   |
    //                                        Extra cycle needed to reset the state <----/

    // The last period is special so we need a flag to identify when it occurs.
    assign final_per = cur_period == io_nc_max_per;
    always_ff @(posedge clk) begin
        if (rst) begin
            done <= 1'b1;
            done_d <= 1'b1;
            trans1_eval0 <= 1'b0;
        end else begin
            done_d <= done;
            // Done bit: set after final evaluation. Unset when software restarts execution.
            if (final_per)
                done <= 1'b1;
            else if (start_d)
                done <= 1'b0;
            // trans1_eval0 bit:
            //  Toggle when 0 (evaluating) and exe is running (done=0). This
            //  will cause the nc_evaluate to be asserted for 1 cycle only.
            //  Also toggle when API controller is done transmitting and
            //  the exe is running. This will cause nc_transmit to be
            //  asserted until api_nc_done is returned.
            //  ...Also toggle a second time in the final period to skip
            //  the last transmit period.
            if (!done && (!trans1_eval0 || api_nc_done) || final_per && !done_d) // This could probable be done better but it should work.
                trans1_eval0 <= ~trans1_eval0;
        end
    end
    assign nc_evaluate = ~done & ~trans1_eval0 | warmup;
    assign nc_transmit = ~done & trans1_eval0 & ~final_per; // Don't transmit in the final period.
    assign nc_reset = io_nc_start & done;
    assign nc_warmup = warmup;
    assign nc_io_done = done && warmup ? 1'b0 : done;

    // Period Registers:
    always_ff @(posedge clk) begin
        if (rst)
            cur_period <= '0;
        else
            if (!done || io_nc_start)
                cur_period <= cur_period_nxt;
    end

    always_comb begin
        cur_period_nxt = cur_period; // Default/else
        // If we get a start and the execution isn't running, then set to 1.
        if (done && io_nc_start) // Can't start while still executing.
            cur_period_nxt = $bits(cur_period_nxt)'(1);
        // Else if the execution is running while in a transmit period and 
        // API is done transmitting, increment.
        else if (!done & trans1_eval0 & api_nc_done)
            cur_period_nxt += $bits(cur_period_nxt)'(1);
    end
    
    assign nc_io_cur_per = cur_period;



endmodule