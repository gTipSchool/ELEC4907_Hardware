/*
    sn_neuron_cfg:
        Updated neuron module with additional configurability:
        - Two API bus ports instead of one. One for input and one for output.
        - Most Izh neuron model parameters can now be configured.
        - Ability to enable or disable dynamic step counter modification.
        - Ability to enable or disable dynamic constant current modification.
        - Ability select CAM vs. UCAM (unaddressable CAM), whose constant keys can
          be specified via a new port "cfg_table_contents".

*/
module sn_neuron_cfg
    #(  
        // Neuron Configuration: 
        //  Can be Input (0), Hidden (1), or Output (2) neuron configuration.
        parameter P_NEUR_CFG=1,

        // Weight Table Configuration:
        //  Selection for addressable (1) vs. unaddressable (0) weight table CAM.
        parameter P_TABLE_IS_MUTABLE=1,
        //  Number of rows/entries in the table.
        parameter P_TABLE_NUM_ROWS=20,
        //  Bit-width of the table indices.
        parameter P_TABLE_IDX_BW=8,
        //  Bit-width of the table weights (including precision bits).
        parameter P_TABLE_WEIGHT_BW=7,
        //  Number of bits of precision for the weights.
        parameter P_TABLE_WEIGHT_PRECISION=2,

        // Input Current Configuration:
        //  Selection for mutable constant current. If selected, the constant current is 
        //  addressable via the memory interface.
        parameter P_CURRENT_CONST_IS_MUTABLE=1,
        //  Constant current if P_CURRENT_CONST_IS_MUTABLE=0.
        //  Parameter value should be int(curr * 2^P_TABLE_WEIGHT_PRECISION) where curr is
        //  is the requested current as a float type.
        parameter P_CURRENT_CONST_VAL=0,
        //  Bit-width of input current and constant current registers. Sized based on number of
        //  rows in the weight table, and bit-width of weight table weights. Precision of
        //  current registers is determined by P_TABLE_WEIGHT_PRECISION.
        parameter P_CURRENT_BW=9,

        // Memory Interface Configuration:
        //  Memory IF address bit-width.
        parameter P_MEM_ADDR_BW=5,
        //  Memory IF data bit-width.
        parameter P_MEM_DATA_BW=18,

        // Axon Protocol Interface Configuration:
        //  Bit-width of the input API bus.
        parameter P_API_IN_BW=8,
        //  Index of the neuron on the output API bus.
        parameter P_API_OUT_INDEX=1,
        //  Bit-width of the output API bus.
        parameter P_API_OUT_BW=8,
        
        // Output Spike Lengthening Configuration:
        //  Selection for mutable output step length.
        parameter P_CNTR_IS_MUTABLE=1,
        //  Output spike length in timesteps. This is the reset value if P_CNTR_IS_MUTABLE=1,
        //  and is the unmutable value if P_CNTR_IS_MUTABLE=0.
        parameter integer P_CNTR_VAL=40,
        //  Output step counter bit-width if P_CNTR_IS_MUTABLE=1.
        parameter P_CNTR_BW=$clog2(P_CNTR_VAL),

        // Neuron Model Configuration:
        //  Neuron model selection. 0=Izhikevich, 1=Integrate & Fire.
        parameter P_NEUR_MODEL_CFG = 0,
        // Izhikevich Variable Logic Configuration:
        //  Precision of the Izhikevich variables in bits.
        parameter P_NEUR_MODEL_PRECISION=10,
        //  Selection to enable high Izhikevich precision (>10). This allows the v^2 output
        //  to be larger than 25 bits in width.
        parameter P_IZH_HIGH_PREC_ENABLE=0
        // TODO configurable Izh params.
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
        // Axon Protocol Interfaces
            // Input
        input api_in_vld,
        input [P_API_IN_BW-1:0] api_in_bus,
            // Output
        input api_out_granted,
        output logic api_out_pending,
        output [P_API_OUT_BW-1:0] api_out_bus,
        // Memory Interface
        input m_we,
        input [P_MEM_ADDR_BW-1:0] m_waddr,
        input [P_MEM_DATA_BW-1:0] m_wdata,
        // Configuration Signals
        input [P_TABLE_NUM_ROWS-1:0][P_TABLE_IDX_BW+P_TABLE_WEIGHT_BW-1:0] cfg_table_contents,
        // For simulation only.
        output logic [P_NEUR_MODEL_PRECISION+(P_NEUR_MODEL_CFG==0?8:9)-1:0] v_out,
        output logic [P_NEUR_MODEL_PRECISION+8-1:0] u_out
    );

    // Declarations:
    //------------------
    // Number of parameter regs:
    //  1 for counter value (mem address 0)
    //  1 for constant current (mem address 1)
    localparam L_NUM_PARAM_REGS = 2;
    // Currents:
    logic signed [P_CURRENT_BW-1:0] current, const_current;
    // Output value and step counter to hold the output_val high:
    logic [P_CNTR_BW-1:0] step_cntr, step_cntr_nxt,
                          step_len;
    reg output_val;
    wire output_val_nxt;
    // Neuron Model:
    wire spiking;
    wire signed [P_CURRENT_BW-1:0] input_current;
    wire signed [P_CURRENT_BW+1+P_NEUR_MODEL_PRECISION-1:0] shifted_input_current;

    
// Constant current:
generate
    if (P_NEUR_CFG==0 || P_CURRENT_CONST_IS_MUTABLE==1) begin: gen_mutable_ccur

        always_ff @(posedge clk) begin
            if (rst) begin
                const_current <= '0;
            end else if (m_we && m_waddr==$bits(m_waddr)'(0)) begin
                const_current <= $bits(const_current)'(m_wdata);
            end
        end 

    end: gen_mutable_ccur
    else begin: gen_unmutable_ccur

        assign const_current = $bits(const_current)'(P_CURRENT_CONST_VAL);

    end: gen_unmutable_ccur
endgenerate
                
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
        logic [P_API_IN_BW-1:0] api_bus_d;
        logic api_vld_d;
        // Next current (declared here because otherwise it is a wire).
        logic signed [P_CURRENT_BW-1:0] current_nxt;
        // Weight table:
        logic [P_TABLE_NUM_ROWS-1:0] table_s;
        logic [P_TABLE_NUM_ROWS-1:0][P_TABLE_IDX_BW-1:0] table_i;
        logic signed [P_TABLE_NUM_ROWS-1:0][P_TABLE_WEIGHT_BW-1:0] table_w;
        // Output from weight table. Output 1 for each row if there is a match with the API bus contents.
        logic [P_TABLE_NUM_ROWS-1:0] row_idx_match;
        
        // This is the output from an equality check for every row of the weight table, comparing stored indices with the API index.
        for (genvar row=0; row<P_TABLE_NUM_ROWS; row++) begin: gen_t_match_sig
            assign row_idx_match[row] = api_vld_d & api_bus_d == table_i[row];
        end

        always_ff @(posedge clk) begin
            if (rst || nc_reset) begin
                api_bus_d <= '0;
                api_vld_d <= 1'b0;
                current <= '0;
                table_s <= '0;
            end else begin
                // Simply just flop the API bus and use the flop as the input into the weight table. This is because the API bus is a critical path otherwise (for large networks).
                api_vld_d <= api_in_vld;
                if (api_in_vld) api_bus_d <= api_in_bus;
                
                if (nc_evaluate || api_vld_d) // We only need to change the value of the current register if a signal is asserted that should trigger a value change (most of the time). This is "clock gating" and is common practice to save dynamic power.
                    current <= current_nxt;
                if (api_vld_d) 
                    for (int i=0; i<P_TABLE_NUM_ROWS; i++)
                        if (row_idx_match[i])
                            table_s[i] <= ~table_s[i];
            end
        end 
        // Next current:
        always_comb begin
            // Default/else/initial
            current_nxt = current;
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
        end

        if (P_TABLE_IS_MUTABLE==1) begin: gen_mutable_table

            logic [P_TABLE_NUM_ROWS-1:0][P_TABLE_IDX_BW-1:0] table_i_nxt;
            logic signed [P_TABLE_NUM_ROWS-1:0][P_TABLE_WEIGHT_BW-1:0] table_w_nxt;

            always_ff @(posedge clk) begin
                if (rst) begin
                    table_i <= '0;
                    table_w <= '0;
                end else if (m_we) begin
                    table_i <= table_i_nxt;
                    table_w <= table_w_nxt;
                end
            end 
            // Next table:
            always_comb begin
                // Default/else/initial
                table_i_nxt = table_i;
                table_w_nxt = table_w;
                // The weight table has P_TABLE_NUM_ROWS rows. Each row has an index register (table_i), and a weight register (table_w) associated with the index.
                // All registers can be programmed through the memory interface (via software) to change which inputs the neuron should react to.
                if (m_we && m_waddr>=L_NUM_PARAM_REGS) begin // If write enable is asserted and the address is more than the number of parameter registers (which also occupy address space).
                    if ((m_waddr-L_NUM_PARAM_REGS) % 2 == 0) // The weight table addresses start at m_waddr-L_NUM_PARAM_REGS. If this value is even, then it addresses an index register, else a weight register.
                        table_i_nxt[(m_waddr-L_NUM_PARAM_REGS) / 2] = (P_TABLE_IDX_BW)'(m_wdata);
                    else
                        table_w_nxt[(m_waddr-L_NUM_PARAM_REGS) / 2] = (P_TABLE_WEIGHT_BW)'(m_wdata);
                end
            end

        end: gen_mutable_table
        else begin: gen_unmutable_table

            // Contents of the weight table are constant, based on the input cfg_table_contents.
            always_comb
                for (int row=0;row<P_TABLE_NUM_ROWS;row++) begin
                    table_i[row] = cfg_table_contents[row][P_TABLE_IDX_BW+P_TABLE_WEIGHT_BW-1:P_TABLE_WEIGHT_BW];
                    table_w[row] = cfg_table_contents[row][P_TABLE_WEIGHT_BW-1:0];
                end

        end: gen_unmutable_table
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
            if (rst || api_out_granted) // No need to reset this using nc_reset.
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
        assign api_out_pending = output_val & api_pending_r;
        
        assign api_out_bus = api_out_pending & api_out_granted ? 
                             $bits(api_out_bus)'(P_API_OUT_INDEX) :
                             'Z;

        // Step length:
        if (P_CNTR_IS_MUTABLE==1) begin: gen_mutable_cntr

            always_ff @(posedge clk) begin
                if (rst)
                    step_len <= $bits(step_len)'(P_CNTR_VAL);
                else if (m_we && m_waddr==$bits(m_waddr)'(1))
                    step_len <= $bits(step_len)'(m_wdata);
            end

        end: gen_mutable_cntr
        else begin: gen_unmutable_cntr
            
            assign step_len = (P_CNTR_BW)'(P_CNTR_VAL);

        end: gen_unmutable_cntr
        
        // Step Counter Register + Output:
        //--------------------------------
        always_ff @(posedge clk) begin
            if (rst) begin
                output_val <= 1'b0;
                step_cntr <= '0;
            end else begin
                if (nc_reset) begin
                    output_val <= 1'b0;
                    step_cntr <= '0;
                end else if (nc_evaluate && !nc_warmup || api_out_granted) begin
                    output_val <= output_val_nxt;
                    step_cntr <= step_cntr_nxt;
                end
            end
        end
        
        // We want the output value to be set when the neuron output counter is changing from non-zero to zero, or from zero to non-zero (i.e. spiking=1).
        // There is a special case for saturated spiking (spiking while the output counter is non-zero) when we want to suppress output_val asserting.
        // There's also a special case here when step_cntr==1 (triggering the output_val_nxt to be asserted because it senses a change) while at the same
        // time, the neuron spikes. This is a rare case, but the expected behaviour is that the output value would still saturate.
        assign output_val_nxt = (spiking && ~|step_cntr) || (~spiking && step_cntr==$bits(step_cntr)'(1)) ? 1'b1 : (api_out_granted ? 1'b0: output_val);
        
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

        assign api_out_bus = 'Z;
        assign api_out_pending = 1'b0;

    end
endgenerate

// Generating the neuron model logic:
generate
    if (P_NEUR_MODEL_CFG==0) begin: gen_izh

        localparam L_IZH_V_SPIKE_VAL = 30;
        localparam L_IZH_U_RST_VAL = -20;
        localparam L_IZH_V_RST_VAL = -70;
        localparam L_IZH_C = -65;
        localparam L_IZH_D = 6;
        reg signed [P_NEUR_MODEL_PRECISION+8-1:0] v, u;
        wire signed [P_NEUR_MODEL_PRECISION+8-1:0] v_nxt, u_nxt;
        wire signed [P_NEUR_MODEL_PRECISION/2+8-1:0] v_pre_sq;
        wire signed [(P_NEUR_MODEL_PRECISION+16-1>25&&P_IZH_HIGH_PREC_ENABLE==0?25:P_NEUR_MODEL_PRECISION+16)-1:0] v_sq;
        wire signed [P_NEUR_MODEL_PRECISION+8+3-1:0] v_x_const;
        wire signed [P_NEUR_MODEL_PRECISION+11-1:0] v_sq_x_const;
        wire signed [P_NEUR_MODEL_PRECISION+12-1:0] vu_contrib;
        wire signed [P_NEUR_MODEL_PRECISION+13-1:0] v_dv;
        wire signed [P_NEUR_MODEL_PRECISION+11-1:0] v_nxt_nomux;
        wire signed [P_NEUR_MODEL_PRECISION+9-1:0] v_xcmu; // xc="*const", mu="-u"
        wire signed [P_NEUR_MODEL_PRECISION+2-1:0] v_xcmu_x_const; // (v * const - u) * const
        wire signed [P_NEUR_MODEL_PRECISION+8-1:0] u_nxt_nomux;

        // Izhikevich Neuron Model:
        //-------------------------
        always_ff @(posedge clk) begin
            if (rst || nc_reset) begin
                v <= $bits(v)'(L_IZH_V_RST_VAL <<< P_NEUR_MODEL_PRECISION);
                u <= $bits(u)'(L_IZH_U_RST_VAL <<< P_NEUR_MODEL_PRECISION);
            end else if (nc_evaluate) begin
                v <= v_nxt;
                u <= u_nxt;
            end
        end

        // Calculating the next v value:
        assign v_pre_sq = v >>> (P_NEUR_MODEL_PRECISION / 2); 
        assign v_sq = v_pre_sq * v_pre_sq; // = v^2
        assign v_sq_x_const = (v_sq >>> 5) + (v_sq >>> 7) + (v_sq >>> 10); // ~= 0.04 * v^2
        assign v_x_const = (v <<< 2) + v; // = 5 * v

        //  Model input current:
        assign input_current = const_current + current;
        assign shifted_input_current = (140 <<< P_NEUR_MODEL_PRECISION) + (input_current <<< (P_NEUR_MODEL_PRECISION-P_TABLE_WEIGHT_PRECISION));
        
        assign vu_contrib = v_sq_x_const + v_x_const - u;
        assign v_dv = vu_contrib + shifted_input_current;
        assign v_nxt_nomux = v + (v_dv >>> 2); // = v + v_dv * tau = v + v_dv * 0.25
        
        //  Spiking condition: if the calculated next v value >30 and we are in an eval period.
        assign spiking = nc_evaluate & (v_nxt_nomux >>> P_NEUR_MODEL_PRECISION) > ($bits(v_nxt_nomux)-P_NEUR_MODEL_PRECISION)'(L_IZH_V_SPIKE_VAL);
        
        assign v_nxt = spiking ? $bits(v_nxt)'(L_IZH_C <<< P_NEUR_MODEL_PRECISION) : v_nxt_nomux;

        // Calculating the next u value:
        assign v_xcmu = (v_nxt_nomux >>> 3) + (v_nxt_nomux >>> 4) + (v_nxt_nomux >>> 6) - u;
        assign v_xcmu_x_const = (v_xcmu >>> 8) + (v_xcmu >>> 10);
        assign u_nxt_nomux = v_xcmu_x_const + u;
        
        assign u_nxt = spiking ? $bits(u_nxt)'((L_IZH_D <<< P_NEUR_MODEL_PRECISION) + u) : u_nxt_nomux;
    
        // v and u variables to view in waveforms during simulation:
        assign v_out = v;
        assign u_out = u;

    end else begin: gen_i_and_f
        
        localparam L_IF_NEG_THRES = -256;
        localparam L_IF_V_SPIKE_VAL = 30;
        localparam L_IF_V_RST_VAL = -70;
        localparam L_IF_C = -65;
        reg signed [P_NEUR_MODEL_PRECISION+9-1:0] v;
        wire signed [P_NEUR_MODEL_PRECISION+9-1:0] v_nxt;
        wire signed [P_NEUR_MODEL_PRECISION+10-1:0] v_nxt_premux;
        wire signed [P_NEUR_MODEL_PRECISION+10-1:0] v_nxt_nomux;
        wire signed [P_NEUR_MODEL_PRECISION+7-1:0] v_xc;


        // Integrate and Fire Neuron Model:
        //-------------------------
        always_ff @(posedge clk) begin
            if (rst || nc_reset)
                v <= $bits(v)'(L_IF_V_RST_VAL <<< P_NEUR_MODEL_PRECISION);
            else if (nc_evaluate)
                v <= v_nxt;
        end

        //  Model input current:
        assign input_current = const_current + current;
        assign shifted_input_current = (input_current <<< (P_NEUR_MODEL_PRECISION-P_TABLE_WEIGHT_PRECISION)) - (8 <<< P_NEUR_MODEL_PRECISION);
        
        assign v_xc = (v>>>3)+(v>>>6)+(v>>>7);
        assign v_nxt_premux = ((shifted_input_current - v_xc)>>>2) + v;
        assign v_nxt_nomux = (v_nxt_premux >>> P_NEUR_MODEL_PRECISION) < ($bits(v_nxt_premux)-P_NEUR_MODEL_PRECISION)'(L_IF_NEG_THRES) ? $bits(v_nxt_nomux)'(L_IF_NEG_THRES <<< P_NEUR_MODEL_PRECISION) : v_nxt_premux;
        assign spiking = nc_evaluate & (v_nxt_nomux >>> P_NEUR_MODEL_PRECISION) > ($bits(v_nxt_nomux)-P_NEUR_MODEL_PRECISION)'(L_IF_V_SPIKE_VAL); 
        assign v_nxt = spiking ? $bits(v_nxt)'(L_IF_C <<< P_NEUR_MODEL_PRECISION) : v_nxt_nomux;

        // v and u variables to view in waveforms during simulation:
        assign v_out = v;
        assign u_out = '0;
    end
endgenerate

    // Outputs:
    //----------
    // Output value to the output evaluator (if this is an output neuron):
    assign neur_output = spiking;

endmodule