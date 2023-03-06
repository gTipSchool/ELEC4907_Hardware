/*
    sn_neuron:
        RTL implementing a configurable neuron. Includes:
        - Izhikevich Neuron Model with configurable precision
        - Memory interface
        - API interface
        - CAM weight table
        - Network controller interface
        - Spike lengthening logic
    Written by Grant Tippett, SN 101077488
*/
module sn_neuron
    #(
        parameter P_NEUR_CFG=1, // The configuration of the neuron - 0:input,1:hidden,2:output
        parameter P_NUM_NEURONS=100, 
        parameter P_NUM_OUTPUTS=3,
        parameter P_DFLT_CNTR_VAL=10,
        parameter P_TABLE_NUM_ROWS=20,
        parameter P_TABLE_WEIGHT_BW=7,
        parameter P_TABLE_WEIGHT_PRECISION=2,
        parameter P_NEUR_CURRENT_BW=9,
        parameter P_NEUR_MEM_ADDR_BW=5,
        parameter P_NEUR_MEM_DATA_BW=18,
        parameter P_NEUR_STEP_CNTR_BW=$clog2(P_DFLT_CNTR_VAL),
        parameter P_NEUR_INDEX=1,
        parameter P_NEUR_IZH_PRECISION=10,
        parameter P_NEUR_IZH_HIGH_PREC_EN=0
    )
    (
        // Generic
        input clk,
        input rst,
        // Network Controller
        input nc_evaluate,
        input nc_reset, // Resets outputs ff and Izhikevich regs.
        input nc_warmup,
        // Output Evaluation
        output logic neur_output,
        // Axon Protocol Interface
        input api_vld,
        input api_granted,
        output logic api_pending,
        inout [$clog2(P_NUM_NEURONS-P_NUM_OUTPUTS+1)-1:0] api_bus,
        // Memory Interface
        input m_we,
        input [P_NEUR_MEM_ADDR_BW-1:0] m_waddr,
        input [P_NEUR_MEM_DATA_BW-1:0] m_wdata,
        // For simulation only.
        output logic [P_NEUR_IZH_PRECISION+8-1:0] v_out,
        output logic [P_NEUR_IZH_PRECISION+8-1:0] u_out
    );

    // Declarations:
    //------------------
    // Number of parameter regs:
    //  1 for counter value (mem address 0)
    //  1 for constant current (mem address 1)
    localparam L_NUM_PARAM_REGS = 2;
    // Currents:
    logic signed [P_NEUR_CURRENT_BW-1:0] current, const_current;
    // Output value and step counter to hold the output_val high:
    logic [P_NEUR_STEP_CNTR_BW-1:0] step_cntr, step_cntr_nxt,
                                    step_len;
    reg output_val;
    wire output_val_nxt;
    // Izhikevich:
    // each increment of v and u represents 1/2^L_PRECISION_MODIFIER. Default is 1/1024 ~= 0.001
    // Valid values are 10, 8, 6, and 4.
    localparam L_PRECISION_MODIFIER = P_NEUR_IZH_PRECISION; // FIXME this doesn't work, but probably not because the precision is limited past below 10. 
    localparam L_IZH_V_RST_VAL = -70;
    localparam L_IZH_U_RST_VAL = -20;
    localparam L_IZH_V_SPIKE_VAL = 30;
    localparam L_IZH_C = -65;
    localparam L_IZH_D = 6;
    wire spiking;
    reg signed [L_PRECISION_MODIFIER+8-1:0] v, u;
    wire signed [L_PRECISION_MODIFIER+8-1:0] v_nxt, u_nxt;
    wire signed [L_PRECISION_MODIFIER/2+8-1:0] v_pre_sq;
    wire signed [(L_PRECISION_MODIFIER+16-1>25&&P_NEUR_IZH_HIGH_PREC_EN==0?25:L_PRECISION_MODIFIER+16)-1:0] v_sq;
    wire signed [L_PRECISION_MODIFIER+8+3-1:0] v_x_const;
    wire signed [L_PRECISION_MODIFIER+11-1:0] v_sq_x_const;
    wire signed [P_NEUR_CURRENT_BW-1:0] input_current;
    wire signed [P_NEUR_CURRENT_BW+1+L_PRECISION_MODIFIER-1:0] shifted_input_current;
    wire signed [L_PRECISION_MODIFIER+12-1:0] vu_contrib;
    wire signed [L_PRECISION_MODIFIER+13-1:0] v_dv;
    wire signed [L_PRECISION_MODIFIER+11-1:0] v_nxt_nomux;
    wire signed [L_PRECISION_MODIFIER+9-1:0] v_xcmu; // xc="*const", mu="-u"
    wire signed [L_PRECISION_MODIFIER+2-1:0] v_xcmu_x_const; // (v * const - u) * const
    wire signed [L_PRECISION_MODIFIER+8-1:0] u_nxt_nomux;
    
    assign v_out = v;
    assign u_out = u;
    
    // Constant current:
    always_ff @(posedge clk) begin
        if (rst) begin
            const_current <= '0;
        end else if (m_we && m_waddr==$bits(m_waddr)'(0)) begin
            const_current <= $bits(const_current)'(m_wdata);; 
        end
    end 
                
// Generating the input current:
//  Either from the weight table prompted by the API bus,
//  or from the input current into this module (if this is an input neuron).
generate
    if (P_NEUR_CFG != 0) begin: gen_w_table

        // Weight Table & Currents:
        //-------------------------
        // The weight table has P_TABLE_NUM_ROWS rows in it, similar to a cache.
        // Each row has an index for lookup and an associated weight value.
        // When the API bus is valid, an index for a firing neuron will 
        // be placed on the bus. This address can be compared to each index
        // in the weight table. If there is a match, then the associated
        // weight will be added to the next input current in the current cycle.
        // After all firing neurons have placed their indices on the bus,
        // the input current will be completed resolved, and on the following
        // evaluate period, it will be used to calculate the new Izhikevich
        // neuron model values v and u.
        // The input current always has a constant current plus the added
        // weights.
        
        // Flopped API bus (to minimize fan-out into all weight tables).
        logic [$clog2(P_NUM_NEURONS-P_NUM_OUTPUTS+1)-1:0] api_bus_d;
        logic api_vld_d;
        // Next current (declared here because otherwise it is a wire).
        logic signed [P_NEUR_CURRENT_BW-1:0] current_nxt;
        // Weight table:
        logic [P_TABLE_NUM_ROWS-1:0] table_s;
        logic [P_TABLE_NUM_ROWS-1:0][$clog2(P_NUM_NEURONS-P_NUM_OUTPUTS+1)-1:0] table_i, table_i_nxt;
        logic signed [P_TABLE_NUM_ROWS-1:0][P_TABLE_WEIGHT_BW-1:0] table_w, table_w_nxt;
        // Output from weight table. Output 1 for each row if there is a match with the API bus contents.
        logic [P_TABLE_NUM_ROWS-1:0] row_idx_match;
        
        // This is the output from an equality check for every row of the weight table, comparing stored indices with the API index.
        for (genvar row=0; row<P_TABLE_NUM_ROWS; row++) begin: gen_t_match_sig
            assign row_idx_match[row] = api_vld_d & api_bus_d == table_i[row];
        end
        
        always_ff @(posedge clk) begin
            if (rst) begin
                api_bus_d <= '0;
                api_vld_d <= 1'b0;
                current <= '0;
                table_s <= '0;
                table_i <= '0;
                table_w <= '0;
            end else begin
                // Simply just flop the API bus and use the flop as the input into the weight table. This is because the API bus is a critical path otherwise (for large networks).
                api_vld_d <= api_vld;
                if (api_vld) api_bus_d <= api_bus;
                
                if (nc_evaluate || api_vld_d) // We only need to change the value of the current register if a signal is asserted that should trigger a value change (most of the time). This is "clock gating" and is common practice to save dynamic power.
                    current <= current_nxt;
                if (api_vld_d) 
                    for (int i=0; i<P_TABLE_NUM_ROWS; i++)
                        if (row_idx_match[i])
                            table_s[i] <= ~table_s[i];
                if (m_we) begin
                    table_i <= table_i_nxt;
                    table_w <= table_w_nxt;     
                end
            end
        end 

        always_comb begin
            // Default/else/initial
            current_nxt = current;
            table_i_nxt = table_i;
            table_w_nxt = table_w;
            
            // Next current:
            // The table_s or "status" bits per row determine whether to add or subtract the weight.
            // This would synthesize into an adder tree with inputs from all weights in the weight table ANDed with masks made up of row_idx_match[i].
            // Ideally in an ASIC this would be a bus to save area, but FPGAs don't have tri-state buffers so buses aren't synthesizable in our case.
            for (int i=0; i<P_TABLE_NUM_ROWS; i++)
                if (row_idx_match[i]) begin
                    if (!table_s[i])
                        current_nxt = current_nxt + table_w[i];
                    else
                        current_nxt = current_nxt - table_w[i];
                end
            
            // Next table:
            // The weight table has P_TABLE_NUM_ROWS rows. Each row has an index register (table_i), and a weight register (table_w) associated with the index.
            // All registers can be programmed through the memory interface (via software) to change which inputs the neuron should react to.
            if (m_we && m_waddr>=L_NUM_PARAM_REGS) begin // If write enable is asserted and the address is more than the number of parameter registers (which also occupy address space).
                if ((m_waddr-L_NUM_PARAM_REGS) % 2 == 0) // The weight table addresses start at m_waddr-L_NUM_PARAM_REGS. If this value is even, then it addresses an index register, else a weight register.
                    table_i_nxt[(m_waddr-L_NUM_PARAM_REGS) / 2] = $clog2(P_NUM_NEURONS-P_NUM_OUTPUTS+1)'(m_wdata);
                else
                    table_w_nxt[(m_waddr-L_NUM_PARAM_REGS) / 2] = (P_TABLE_WEIGHT_BW)'(m_wdata);
            end
        end

    end else begin: gen_no_w_table

        // If this is an input neuron, no weight table or current register. Just the const current.
        assign current = '0;

    end
endgenerate 


// Generating the API Output interface:
generate
    if (P_NEUR_CFG != 2) begin: gen_api_port

        // api_pending:
        //  - Should be asserted immediately after an evalulation if the neuron's output is high.
        //  - Should deassert immediately after (1 clock cycle after) api_granted is asserted.
        reg api_pending_r;
        always_ff @(posedge clk) begin
            if (rst || api_granted) // No need to reset this using nc_reset.
                // Deassert when granted comes in.
                api_pending_r <= 1'b0;
            else if (nc_evaluate)
                // Assert after evaluation. Hold until granted.
                // If granted isn't asserted in a given transmit period (because the
                // neuron isn't spiking), then this bit stays high with no conflicts.
                api_pending_r <= 1'b1;
        end 
        // if both the neuron is spiking (output_val=1), and granted hasn't asserted,
        // then assert api_pending.
        assign api_pending = output_val & api_pending_r;
        
        assign api_bus = api_pending & api_granted ? 
                         $bits(api_bus)'(P_NEUR_INDEX) :
                         'Z;
        
        // Step Counter Register + Output:
        //--------------------------------
        always_ff @(posedge clk) begin
            if (rst) begin
                output_val <= 1'b0;
                step_cntr <= '0;
                step_len <= $bits(step_len)'(P_DFLT_CNTR_VAL);
            end else begin
                if (nc_reset) begin
                    output_val <= 1'b0;
                    step_cntr <= '0;
                end else if (nc_evaluate && !nc_warmup || api_granted) begin
                    output_val <= output_val_nxt;
                    step_cntr <= step_cntr_nxt;
                end
                if (m_we && m_waddr==$bits(m_waddr)'(1))
                    step_len <= $bits(step_len)'(m_wdata);
            end
        end
        
        // We want the output value to be set when the neuron output counter is changing from non-zero to zero, or from zero to non-zero (i.e. spiking=1).
        // There is a special case for saturated spiking (spiking while the output counter is non-zero) when we want to suppress output_val asserting.
        // There's also a special case here when step_cntr==1 (triggering the output_val_nxt to be asserted because it senses a change) while at the same
        // time, the neuron spikes. This is a rare case, but the expected behaviour is that the output value would still saturate.
        assign output_val_nxt = (spiking && ~|step_cntr) || (~spiking && step_cntr==$bits(step_cntr)'(1)) ? 1'b1 : (api_granted ? 1'b0: output_val);
        
        always_comb begin
            // Default/else
            step_cntr_nxt = step_cntr;
            if (spiking) begin
                // Set to max value if spiking
                step_cntr_nxt = step_len;
            end else if (|step_cntr) begin
                // Decrement if non-zero and not spiking
                step_cntr_nxt -= $bits(step_cntr_nxt)'(1);
            end
        end 

    end else begin: gen_api_z

        assign api_bus = 'Z;
        assign api_pending = 1'b0;

    end
endgenerate


    // Izhikevich Neuron Model:
    //-------------------------
    always_ff @(posedge clk) begin
        if (rst || nc_reset) begin
            v <= $bits(v)'(L_IZH_V_RST_VAL <<< L_PRECISION_MODIFIER);
            u <= $bits(u)'(L_IZH_U_RST_VAL <<< L_PRECISION_MODIFIER);
        end else if (nc_evaluate) begin
            v <= v_nxt;
            u <= u_nxt;
        end
    end

    // Calculating the next v value:
    // Determining the bit widths of each wire:
    // max value of v: 29 = 29*1024 = 30690 = 15'h77E2
    // min value of v: -128 = -128*1024 = -131,072 = 18'hs2_0000
    //  This is assuming that v is never less than -128, which seems okay from simulation.
    //  Actually the minimum is something like -127.999 if we want v^2 to be less than 25 bits.
    // max value of v_sq: (-127.999*1024/sqrt(1024))^2 ~= 16,777,215 = 25'hs0FF_FFFF
    // max value of v_sq_x_const: 16,777,215*0.0400390625 ~= 671744 = 21'hs0A_4000
    // max value of v_x_const: -127.999*1024*5 ~= -655,355 = 21'hs06_0005
    assign v_pre_sq = v >>> (L_PRECISION_MODIFIER / 2); 
    assign v_sq = v_pre_sq * v_pre_sq; // = v^2
    //     25     13         13
    assign v_sq_x_const = (v_sq >>> 5) + (v_sq >>> 7) + (v_sq >>> 10); // ~= 0.04 * v^2
    //     20             
    assign v_x_const = (v <<< 2) + v; // = 5 * v
    //     21          20          18
    assign input_current = const_current + current;
    assign shifted_input_current = (140 <<< L_PRECISION_MODIFIER) + (input_current <<< (L_PRECISION_MODIFIER-P_TABLE_WEIGHT_PRECISION));
    
    assign vu_contrib = v_sq_x_const + v_x_const - u;
    assign v_dv = vu_contrib + shifted_input_current;
    assign v_nxt_nomux = v + (v_dv >>> 2); // = v + v_dv * tau = v + v_dv * 0.25
    //                   18    22
    
    // Spiking if the calculated next v value >30 and we are in an eval period.
    assign spiking = nc_evaluate & (v_nxt_nomux >>> L_PRECISION_MODIFIER) > ($bits(v_nxt_nomux)-L_PRECISION_MODIFIER)'(L_IZH_V_SPIKE_VAL);
    
    assign v_nxt = spiking ? $bits(v_nxt)'(L_IZH_C <<< L_PRECISION_MODIFIER) : v_nxt_nomux;

    // Calculating the next u value:
    assign v_xcmu = (v_nxt_nomux >>> 3) + (v_nxt_nomux >>> 4) + (v_nxt_nomux >>> 6) - u;
    //     19       15          14          12          18
    assign v_xcmu_x_const = (v_xcmu >>> 8) + (v_xcmu >>> 10);
    //     12               11               9
    assign u_nxt_nomux = v_xcmu_x_const + u;
    //     18            12               18
    
    assign u_nxt = spiking ? $bits(u_nxt)'((L_IZH_D <<< L_PRECISION_MODIFIER) + u) : u_nxt_nomux;
    
    // Output value to the output evaluator (if this is an output neuron):
    assign neur_output = spiking;

endmodule