/*
    sn_network:
        Generates neurons (input, hidden layer, output) based on P_NUM_NEURONS.
        Instantiates Axon Protocol Interface (API) controller.
        Instantiates network controller.
        Instantiates IO management module.
    Notes:
        - I've tried to name wires in the form "<where its coming from>_<where its going>_<name>"
          for example, if a wire or bus is being sourced from the network controller ("NC") and
          is used in the IO manager ("IO"), and has the name "test_done" to inform the IO manager
          that the network is done processing, then the label for the wire would be "nc_io_test_done".
          Sometimes wires come from one place, and are used in multiple places. In this case I label them
          like "<where its coming from>_<name>".
*/
module sn_network
    #(
      parameter P_NUM_NEURONS=100, // Includes inputs and outputs.
      parameter P_NUM_INPUTS=45,
      parameter P_NUM_OUTPUTS=3,
      parameter P_TABLE_NUM_ROWS=20,
      parameter P_TABLE_WEIGHT_BW=7,
      parameter P_TABLE_WEIGHT_PRECISION=2,
      parameter P_NEUR_CURRENT_BW=P_TABLE_WEIGHT_BW+$clog2(P_TABLE_NUM_ROWS), // Must be more than P_TABLE_WEIGHT_BW
      parameter P_NEUR_IZH_PRECISION=10,
      parameter P_NEUR_IZH_HIGH_PREC_EN=0,
      parameter P_DFLT_CNTR_VAL=10,
      parameter P_NEUR_STEP_CNTR_BW=$clog2(P_DFLT_CNTR_VAL),
      parameter P_MAX_NUM_PERIODS=100
    )
    (
     input clk,
     input rst,
     // Software interface (IO manager to/from IO protocol handler)
     input prot_enable, // Enable all <prot_*> signals
     input prot_r0w1, // 0=read operation, 1=write operation
     input [7-1:0] prot_addr, // Register address for reading or writing
     input [8-1:0] prot_wdata, // Data for writing
     output logic [8-1:0] prot_rdata, // Data returned during a read. Valid when prot_enable=1 (i.e. no read latency).
     output nc_evaluate_out,
     // Output Izhikevich parameter for simulation visibility only. Don't connect these in the instantiated module.
     output logic [P_NUM_NEURONS:1] [P_NEUR_IZH_PRECISION+8-1:0] v_out,
     output logic [P_NUM_NEURONS:1] [P_NEUR_IZH_PRECISION+8-1:0] u_out
     );

    // Declarations:
    //------------------
    localparam L_NUM_PARAM_REGS = 2;
    localparam L_NEUR_MEM_ADDR_MSB_BW=$clog2(P_NUM_NEURONS+1);
    localparam L_NEUR_MEM_ADDR_LSB_BW=$clog2(P_TABLE_NUM_ROWS*2+L_NUM_PARAM_REGS);
    localparam L_NEUR_MEM_DATA_BW=P_NEUR_CURRENT_BW;
    
    // Network controller:
    wire nc_evaluate,
         nc_transmit,
         nc_reset,
         nc_warmup,
         nc_io_done;
    wire [$clog2(P_MAX_NUM_PERIODS+1)-1:0] io_nc_max_per, nc_io_cur_per;
    // IO Manager:
    wire io_nc_start;
    // API Bus:
    wire [$clog2(P_NUM_NEURONS-P_NUM_OUTPUTS+1)-1:0] api_bus;
    // API Controller:
    wire [P_NUM_NEURONS-P_NUM_OUTPUTS:1] api_pending, api_granted;
    wire api_nc_done, api_vld;
    // Neurons:
    logic [P_NUM_NEURONS:1] net_outputs;
    // Weight Distribution:
    logic io_we;
    logic [P_NUM_NEURONS:1] m_we;
    logic [L_NEUR_MEM_ADDR_MSB_BW+L_NEUR_MEM_ADDR_LSB_BW-1:0] io_waddr;
    logic [P_NEUR_CURRENT_BW-1:0] io_wdata;
    
    assign nc_evaluate_out = nc_evaluate;
    
    // IO Manager
    //-------------------
    // Connections:
    //  - API bus: debug monitor observes the API bus to log spiking neurons over time.
    //  - Input Neurons: input currents from the input controller module.
    //  - Output Neurons: statuses from output neurons to the output evaluation module.
    //  - Network Controller: For starting network execution and reading status info.
    sn_io_mgmt 
    #(
        .P_NUM_NEURONS(P_NUM_NEURONS),
        .P_NUM_INPUTS(P_NUM_INPUTS),
        .P_NUM_OUTPUTS(P_NUM_OUTPUTS),
        .P_TABLE_WEIGHT_BW(P_TABLE_WEIGHT_BW),
        .P_NEUR_CURRENT_BW(P_NEUR_CURRENT_BW),
        .P_MAX_NUM_PERIODS(P_MAX_NUM_PERIODS),
        .P_NEUR_MEM_ADDR_MSB_BW(L_NEUR_MEM_ADDR_MSB_BW),
        .P_NEUR_MEM_ADDR_LSB_BW(L_NEUR_MEM_ADDR_LSB_BW),
        .P_NEUR_MEM_DATA_BW(L_NEUR_MEM_DATA_BW)
    ) io_mgmt_i (
        // Inputs:
        .clk(clk),
        .rst(rst),
        .net_outputs(net_outputs[P_NUM_NEURONS:P_NUM_NEURONS-P_NUM_OUTPUTS+1]), // output_val bits from output neurons.
        .api_vld(api_vld), // For debug monitor.
        .api_bus(api_bus), // For debug monitor.
        .nc_io_done(nc_io_done), // Tell IO (and consequetively software) when network execution is done.
        .nc_io_cur_per(nc_io_cur_per), // The current period.
        .nc_reset(nc_reset), // to reset output evaluation regs.
        .nc_warmup(nc_warmup),
        .nc_evaluate(nc_evaluate),
        // Outputs:
        .io_nc_start(io_nc_start), // io_mgmt to net_ctrlr: tells NC to start execution.
        .io_we(io_we), // Weight/parameter mem if write enable. Validates io_waddr and io_wdata.
        .io_waddr(io_waddr), // Weight/parameter mem if write address. MSB is neuron idx, LSB is the targetted neuron register.
        .io_wdata(io_wdata), // Weight/parameter mem if write data. Aligned to LSB.
        .io_nc_max_per(io_nc_max_per), // The maximum configured number of periods.
        // software interface
        .prot_enable(prot_enable),
        .prot_r0w1(prot_r0w1),
        .prot_addr(prot_addr),
        .prot_wdata(prot_wdata),
        .prot_rdata(prot_rdata)
    );

    // Network Controller
    //-------------------
    // Connections:
    //  - All Neurons: to broadcast the evaluate signal.
    //  - IO Manager: for control and status signals.
    //  - API Controller: to know when transmit is done.
    sn_net_ctrlr
    #(
        .P_NUM_NEURONS(P_NUM_NEURONS),
        .P_NUM_INPUTS(P_NUM_INPUTS),
        .P_NUM_OUTPUTS(P_NUM_OUTPUTS),
        .P_MAX_NUM_PERIODS(P_MAX_NUM_PERIODS)
    ) net_ctrlr_i (
        // Inputs:
        .clk(clk),
        .rst(rst),
        .io_nc_start(io_nc_start),
        .io_nc_max_per(io_nc_max_per),
        .api_nc_done(api_nc_done),
        // Outputs:
        .nc_evaluate(nc_evaluate),
        .nc_transmit(nc_transmit),
        .nc_reset(nc_reset),
        .nc_warmup(nc_warmup),
        .nc_io_cur_per(nc_io_cur_per),
        .nc_io_done(nc_io_done)
    );

    // Neurons
    //-------------------
    // Input Neurons: N = P_NUM_INPUTS
    //  Connections:
    //      - Network Controller
    //      - Input Controller
    //      - API Bus/Controller (write only)
    // Hidden Layer Neurons: N = P_NUM_NEURONS - P_NUM_INPUTS - P_NUM_OUTPUTS
    //  Connections:
    //      - Network Controller
    //      - API Bus/Controller
    // Output Neurons: N = P_NUM_OUTPUTS
    //  Connections:
    //      - Network Controller
    //      - API Controller (read only)
generate
    for (genvar g=1; g<=P_NUM_NEURONS; g++) begin
        // Start at 1 because neuron index 0 is reserved.
        if (g<=P_NUM_INPUTS) begin: gen_in_neurons

            sn_neuron
            #(
                .P_NUM_NEURONS(P_NUM_NEURONS),
                .P_NUM_OUTPUTS(P_NUM_OUTPUTS),
                .P_DFLT_CNTR_VAL(P_DFLT_CNTR_VAL),
                .P_TABLE_NUM_ROWS(0),
                .P_TABLE_WEIGHT_BW(0),
                .P_TABLE_WEIGHT_PRECISION(P_TABLE_WEIGHT_PRECISION),
                .P_NEUR_CURRENT_BW(P_NEUR_CURRENT_BW),
                .P_NEUR_STEP_CNTR_BW(P_NEUR_STEP_CNTR_BW),
                .P_NEUR_MEM_ADDR_BW(1), // 2 addresses only for input neurons.
                .P_NEUR_MEM_DATA_BW(L_NEUR_MEM_DATA_BW),
                .P_NEUR_INDEX(g),
                .P_NEUR_CFG(0), // 0 for input, 1 for hidden, 2 for output
                .P_NEUR_IZH_PRECISION(P_NEUR_IZH_PRECISION),
                .P_NEUR_IZH_HIGH_PREC_EN(P_NEUR_IZH_HIGH_PREC_EN)
            ) neuron_input_i (
                // Inputs:
                .clk(clk),
                .rst(rst),
                .nc_evaluate(nc_evaluate),
                .nc_reset(nc_reset),
                .nc_warmup(nc_warmup),
                .api_vld(1'b0),
                .api_granted(api_granted[g]),
                .m_we(m_we[g]),
                .m_waddr(io_waddr[L_NEUR_MEM_ADDR_LSB_BW-1:0]),
                .m_wdata(io_wdata),
                // In/Out:
                .api_bus(api_bus),
                // Output:
                .api_pending(api_pending[g]),
                .neur_output(net_outputs[g]),
                .v_out(v_out[g]),
                .u_out(u_out[g])
            );

        end
        else if (g<=P_NUM_NEURONS-P_NUM_OUTPUTS) begin: gen_hidden_neurons

            sn_neuron
            #(
                .P_NUM_NEURONS(P_NUM_NEURONS),
                .P_NUM_OUTPUTS(P_NUM_OUTPUTS),
                .P_DFLT_CNTR_VAL(P_DFLT_CNTR_VAL),
                .P_TABLE_NUM_ROWS(P_TABLE_NUM_ROWS),
                .P_TABLE_WEIGHT_BW(P_TABLE_WEIGHT_BW),
                .P_NEUR_CURRENT_BW(P_NEUR_CURRENT_BW),
                .P_TABLE_WEIGHT_PRECISION(P_TABLE_WEIGHT_PRECISION),
                .P_NEUR_STEP_CNTR_BW(P_NEUR_STEP_CNTR_BW),
                .P_NEUR_MEM_ADDR_BW(L_NEUR_MEM_ADDR_LSB_BW),
                .P_NEUR_MEM_DATA_BW(L_NEUR_MEM_DATA_BW),
                .P_NEUR_INDEX(g),
                .P_NEUR_CFG(1), // 0 for input, 1 for hidden, 2 for output
                .P_NEUR_IZH_PRECISION(P_NEUR_IZH_PRECISION),
                .P_NEUR_IZH_HIGH_PREC_EN(P_NEUR_IZH_HIGH_PREC_EN)
            ) neuron_hidden_i (
                // Inputs:
                .clk(clk),
                .rst(rst),
                .nc_evaluate(nc_evaluate),
                .nc_reset(nc_reset),
                .nc_warmup(nc_warmup),
                .api_vld(api_vld),
                .api_granted(api_granted[g]),
                .m_we(m_we[g]),
                .m_waddr(io_waddr[L_NEUR_MEM_ADDR_LSB_BW-1:0]),
                .m_wdata(io_wdata),
                // In/Out:
                .api_bus(api_bus),
                // Output:
                .api_pending(api_pending[g]),
                .neur_output(net_outputs[g]),
                .v_out(v_out[g]),
                .u_out(u_out[g])
            );
        
        end 
        else begin: gen_out_neurons

            sn_neuron
            #(
                .P_NUM_NEURONS(P_NUM_NEURONS),
                .P_NUM_OUTPUTS(P_NUM_OUTPUTS),
                .P_DFLT_CNTR_VAL(P_DFLT_CNTR_VAL),
                .P_TABLE_NUM_ROWS(P_TABLE_NUM_ROWS),
                .P_TABLE_WEIGHT_BW(P_TABLE_WEIGHT_BW),
                .P_NEUR_CURRENT_BW(P_NEUR_CURRENT_BW),
                .P_TABLE_WEIGHT_PRECISION(P_TABLE_WEIGHT_PRECISION),
                .P_NEUR_STEP_CNTR_BW(P_NEUR_STEP_CNTR_BW),
                .P_NEUR_MEM_ADDR_BW(L_NEUR_MEM_ADDR_LSB_BW),
                .P_NEUR_MEM_DATA_BW(L_NEUR_MEM_DATA_BW),
                .P_NEUR_INDEX(g),
                .P_NEUR_CFG(2), // 0 for input, 1 for hidden, 2 for output
                .P_NEUR_IZH_PRECISION(P_NEUR_IZH_PRECISION),
                .P_NEUR_IZH_HIGH_PREC_EN(P_NEUR_IZH_HIGH_PREC_EN)
            ) neuron_output_i (
                // Inputs:
                .clk(clk),
                .rst(rst),
                .nc_evaluate(nc_evaluate),
                .nc_reset(nc_reset),
                .nc_warmup(nc_warmup),
                .api_vld(api_vld),
                .api_granted('0),
                .m_we(m_we[g]),
                .m_waddr(io_waddr[L_NEUR_MEM_ADDR_LSB_BW-1:0]),
                .m_wdata(io_wdata),
                // In/Out:
                .api_bus(api_bus),
                // Output:
                .api_pending(),
                .neur_output(net_outputs[g]),//g-(P_NUM_NEURONS-P_NUM_OUTPUTS+1)])
                .v_out(v_out[g]),
                .u_out(u_out[g])
            );
            
        end
    end
endgenerate

    // Neuron Memory Addressing:
    always_comb begin
        m_we = '0; // Default/else
        for (int i=1; i<=P_NUM_NEURONS; i++)
            m_we[i] = io_we & io_waddr[L_NEUR_MEM_ADDR_MSB_BW+L_NEUR_MEM_ADDR_LSB_BW-1:L_NEUR_MEM_ADDR_LSB_BW]==(L_NEUR_MEM_ADDR_MSB_BW)'(i);
    end 

    // API Controller
    //-------------------
    // Connections:
    //  - All Neurons: for pending, granted, and bus valid signals.
    //  - Network Controller: for signalling start and end of transmit.
    sn_api_ctrlr 
    #(
        .P_NUM_NEURONS(P_NUM_NEURONS),
        .P_NUM_INPUTS(P_NUM_INPUTS),
        .P_NUM_OUTPUTS(P_NUM_OUTPUTS)
    ) api_ctrlr_i (
        // Inputs:
        .clk(clk),
        .rst(rst),
        .api_pending(api_pending),
        .nc_transmit(nc_transmit),
        // Outputs:
        .api_vld(api_vld),
        .api_granted(api_granted),
        .api_nc_done(api_nc_done)
    );

endmodule