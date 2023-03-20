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
module sn_io_mgmt
    #(
      parameter P_NUM_NEURONS=100, // Includes inputs and outputs.
      parameter P_NUM_INPUTS=45,
      parameter P_NUM_OUTPUTS=3,
      parameter P_TABLE_WEIGHT_BW=7,
      parameter P_NEUR_CURRENT_BW=P_TABLE_WEIGHT_BW+2,
      parameter P_MAX_NUM_PERIODS=100,
      parameter P_NEUR_MEM_ADDR_MSB_BW=7,
      parameter P_NEUR_MEM_ADDR_LSB_BW=5,
      parameter P_NEUR_MEM_DATA_BW=P_NEUR_CURRENT_BW
    )
    (
     input clk,
     input rst,
     // Network controller
     input nc_reset,
     input nc_warmup,
     input nc_evaluate,
     input nc_io_done,
     output io_nc_start,
     input [$clog2(P_MAX_NUM_PERIODS+1)-1:0] nc_io_cur_per,
     output [$clog2(P_MAX_NUM_PERIODS+1)-1:0] io_nc_max_per,
     // API
     input api_vld,
     input [$clog2(P_NUM_NEURONS-P_NUM_OUTPUTS+1)-1:0] api_bus,
     // Network
     input [P_NUM_OUTPUTS-1:0] net_outputs,
     //     MMU
     output io_we,
     output [P_NEUR_MEM_ADDR_MSB_BW+P_NEUR_MEM_ADDR_LSB_BW-1:0] io_waddr,
     output [P_NEUR_MEM_DATA_BW-1:0] io_wdata,
     // Software interface (IO manager to/from IO protocol handler)
     input prot_enable, 
     input prot_r0w1, 
     input [7-1:0] prot_addr, 
     input [8-1:0] prot_wdata, 
     output logic [8-1:0] prot_rdata 
    );
    
    // Declarations
    //-------------------
    
    wire write_enable, read_enable;
    
    // Start reg
    wire sw_start_wen;
    wire sw_start_ren;
    // Current period reg
    wire sw_cur_per_msb_ren;
    wire sw_cur_per_lsb_ren;
    // Max period reg
    wire sw_max_per_msb_wen;
    wire sw_max_per_lsb_wen;
    wire sw_max_per_msb_ren;
    wire sw_max_per_lsb_ren;
    // MMU we reg
    wire sw_mmu_we_wen;
    // MMU waddr regs
    wire sw_mmu_waddr_23_16_wen;
    wire sw_mmu_waddr_15_8_wen;
    wire sw_mmu_waddr_7_0_wen;
    // MMU wdata regs
    wire sw_mmu_wdata_23_16_wen;
    wire sw_mmu_wdata_15_8_wen;
    wire sw_mmu_wdata_7_0_wen;
    // Counter select reg
    wire sw_cntr_sel_val_wen;
    // Selected output counter reg
    wire sw_selected_cntr_ren;
    // Debug monitor timestep selection regs
    wire sw_dbg_mon_time_sel_msb_wen;
    wire sw_dbg_mon_time_sel_lsb_wen;
    // Debug monitor partial timestep reg
    wire sw_dbg_mon_partial_time_sel_wen;
    // Debug monitor output
    wire sw_dbg_mon_output_ren;
    
    assign write_enable = prot_enable & prot_r0w1;
    assign read_enable = prot_enable & ~prot_r0w1;
    
    assign sw_start_wen =                    write_enable & (prot_addr == 7'd0);
    assign sw_start_ren =                    read_enable  & (prot_addr == 7'd0);
    assign sw_cur_per_msb_ren =              read_enable  & (prot_addr == 7'd1);
    assign sw_cur_per_lsb_ren =              read_enable  & (prot_addr == 7'd2);
    assign sw_max_per_msb_wen =              write_enable & (prot_addr == 7'd3);
    assign sw_max_per_lsb_wen =              write_enable & (prot_addr == 7'd4);
    assign sw_max_per_msb_ren =              read_enable  & (prot_addr == 7'd3);
    assign sw_max_per_lsb_ren =              read_enable  & (prot_addr == 7'd4);
    assign sw_mmu_we_wen =                   write_enable & (prot_addr == 7'd5);
    assign sw_mmu_waddr_23_16_wen =          write_enable & (prot_addr == 7'd6);
    assign sw_mmu_waddr_15_8_wen =           write_enable & (prot_addr == 7'd7);
    assign sw_mmu_waddr_7_0_wen =            write_enable & (prot_addr == 7'd8);
    assign sw_mmu_wdata_23_16_wen =          write_enable & (prot_addr == 7'd9);
    assign sw_mmu_wdata_15_8_wen =           write_enable & (prot_addr == 7'd10);
    assign sw_mmu_wdata_7_0_wen =            write_enable & (prot_addr == 7'd11);
    assign sw_cntr_sel_val_wen =             write_enable & (prot_addr == 7'd12);
    assign sw_selected_cntr_ren =            read_enable  & (prot_addr == 7'd13);
    assign sw_dbg_mon_time_sel_msb_wen =     write_enable & (prot_addr == 7'd14);
    assign sw_dbg_mon_time_sel_lsb_wen =     write_enable & (prot_addr == 7'd15);
    assign sw_dbg_mon_partial_time_sel_wen = write_enable & (prot_addr == 7'd16);
    assign sw_dbg_mon_output_ren =           read_enable  & (prot_addr == 7'd17);
    
    
    
    // The code progresses by describing each register, how software accesses it, and the addresses associated with the registers.
    
    // Network Controller regs
    //-------------------------
    // Here there are 3 registers occupying 5 addresses:
    //  - Start bit register: 1-bit (1 address), RW
    //      This is set by software to start network execution, and is unset by
    //      hardware (the network controller) when execution is done.
    //      This register only has one field.
    //          Address: 7'd0
    //  - Current period register: 16-bit (2 addresses), R
    //      This can be read by software during execution to compute % completion
    //      based on a comparison between the preset number of periods.
    //      This also can be used to see if the network has haulted for some reason.
    //      Fields:
    //          - MSB: upper 8 bits of the register (i.e. [15:8]).
    //                 Address: 7'd1
    //          - LSB: lower 8 bits of the register (i.e. [7:0]).
    //                 Address: 7'd2
    //  - Maximum period register: 16-bit (2 addresses), W
    //      This can be written by software before execution to set the number of
    //      periods (AKA time steps) that the network controller will execute
    //      once started.
    //      Fields:
    //          - MSB: upper 8 bits of the register (i.e. [15:8]).
    //                 Address: 7'd3
    //          - LSB: lower 8 bits of the register (i.e. [7:0]).
    //                 Address: 7'd4
    
    reg start_r, start_r_d;
    reg [7:0] max_per_msb_r, max_per_lsb_r;
    always_ff @(posedge clk) begin
        if (rst) begin
            start_r <= 1'b0;
            start_r_d <= 1'b0;
            max_per_msb_r <= 8'(16'(P_MAX_NUM_PERIODS)>>8);
            max_per_lsb_r <= 8'(P_MAX_NUM_PERIODS);
        end else begin
            start_r_d <= start_r;
            if (sw_start_wen) start_r <= 1'b1;
            else if (nc_io_done & start_r_d & start_r) start_r <= 1'b0;
            if (sw_max_per_msb_wen) max_per_msb_r <= prot_wdata;
            if (sw_max_per_lsb_wen) max_per_lsb_r <= prot_wdata;
        end
    end
    assign io_nc_start = start_r & ~start_r_d;
    assign io_nc_max_per = $bits(io_nc_max_per)'({max_per_msb_r, max_per_lsb_r});
    
    // Input & Weight Loading MMU regs
    //-----------------------------------
    // Here there are 3 registers occupying 7 addresses:
    //  - Write enable register: 1-bit (1 address), W
    //      This is set by software to after populating the associated addr and 
    //      data registers.
    //          Address: 7'd5
    //  - Write address register: 24-bit (3 addresses), W
    //      This is the address to write to. Software should populate all fields of 
    //      this register before writing to the write enable register.
    //      Fields:
    //          - 23_16: upper 8 bits of the register (i.e. [23:16]).
    //                 Address: 7'd6
    //          - 15_8: middle 8 bits of the register (i.e. [15:8]).
    //                 Address: 7'd7
    //          - 7_0: lower 8 bits of the register (i.e. [7:0]).
    //                 Address: 7'd8
    //  - Write data register: 24-bit (3 addresses), W
    //      This is the data to write. Software should populate all fields of 
    //      this register before writing to the write enable register.
    //      Fields:
    //          - 23_16: upper 8 bits of the register (i.e. [23:16]).
    //                 Address: 7'd9
    //          - 15_8: middle 8 bits of the register (i.e. [15:8]).
    //                 Address: 7'd10
    //          - 7_0: lower 8 bits of the register (i.e. [7:0]).
    //                 Address: 7'd11
    
    reg mmu_we_r;
    reg [7:0] mmu_waddr_23_16_r, mmu_waddr_15_8_r, mmu_waddr_7_0_r;
    reg [7:0] mmu_wdata_23_16_r, mmu_wdata_15_8_r, mmu_wdata_7_0_r;
    always_ff @(posedge clk) begin
        if (rst) begin
            mmu_we_r <= 1'b0;
            mmu_waddr_23_16_r <= '0;
            mmu_waddr_15_8_r <= '0;
            mmu_waddr_7_0_r <= '0;
            mmu_wdata_23_16_r <= '0;
            mmu_wdata_15_8_r <= '0;
            mmu_wdata_7_0_r <= '0;
        end else begin
            if (sw_mmu_we_wen) mmu_we_r <= 1'b1;
            else if (mmu_we_r) begin // Reset all the registers after writing.
                mmu_we_r <= 1'b0;
                mmu_waddr_23_16_r <= '0;
                mmu_waddr_15_8_r <= '0;
                mmu_waddr_7_0_r <= '0;
                mmu_wdata_23_16_r <= '0;
                mmu_wdata_15_8_r <= '0;
                mmu_wdata_7_0_r <= '0;
            end else begin
                if (sw_mmu_waddr_23_16_wen) mmu_waddr_23_16_r <= prot_wdata;
                if (sw_mmu_waddr_15_8_wen) mmu_waddr_15_8_r <= prot_wdata;
                if (sw_mmu_waddr_7_0_wen) mmu_waddr_7_0_r <= prot_wdata;
                if (sw_mmu_wdata_23_16_wen) mmu_wdata_23_16_r <= prot_wdata;
                if (sw_mmu_wdata_15_8_wen) mmu_wdata_15_8_r <= prot_wdata;
                if (sw_mmu_wdata_7_0_wen) mmu_wdata_7_0_r <= prot_wdata;
            end
        end
    end
    assign io_we = mmu_we_r;
    assign io_waddr = $bits(io_waddr)'({mmu_waddr_23_16_r, mmu_waddr_15_8_r, P_NEUR_MEM_ADDR_LSB_BW'(mmu_waddr_7_0_r)});
    assign io_wdata = $bits(io_wdata)'({mmu_wdata_23_16_r, mmu_wdata_15_8_r, mmu_wdata_7_0_r});
    
    
    // Output Spike Counters & Output Evaluation regs
    //------------------------------------------------
    // There are 2 registers used for output counters (2 addresses).
    //  - Output select: 8-bit (1 address), W
    //      This is written by software to select the output neuron to display the 
    //      counter value of. For example, if this is written with a value of 0, 
    //      then the value of the spike counter associated with the first (0th) 
    //      output neuron is displayed in the output counter register.
    //          Address: 7'd12
    //  - Output counter: 8-bit (1 address), R
    //      This is read by software after writing the appropriate value to the 
    //      'select' register. The counter associated with the value in the select
    //      register can be read from this register.
    //          Address 7'd13;
    
    localparam L_SPIKE_COUNTER_BW = 8;//$clog2((P_MAX_NUM_PERIODS%10)==0 ? P_MAX_NUM_PERIODS/10 : P_MAX_NUM_PERIODS/10 + 1); // Assuming maximum of 1 spike per 10 time steps.
    
    reg [P_NUM_OUTPUTS-1:0][L_SPIKE_COUNTER_BW-1:0] spike_cntr;
    always_ff @(posedge clk) begin
        if (rst || nc_reset)
            spike_cntr <= '0;
        else if (!nc_warmup)
            for (int i=0; i<P_NUM_OUTPUTS; i++)
                if (net_outputs[i] && ~&spike_cntr[i]) // ~&spike_cntr[i] ensures that the counters don't overflow, but instead saturate at 255.
                    spike_cntr[i] <= spike_cntr[i] + 'd1;
    end
    
    reg [$clog2(P_NUM_OUTPUTS)-1:0] cntr_sel_val_r;
    always_ff @(posedge clk) begin
        if (rst)
            cntr_sel_val_r <= '0;
        else if (sw_cntr_sel_val_wen)
            cntr_sel_val_r <= $bits(cntr_sel_val_r)'(prot_wdata);
    end
    
    // MUX of all counters:
    logic [L_SPIKE_COUNTER_BW-1:0] selected_cntr;
    always_comb begin
        selected_cntr = '0; // Default/else
        for (int i=0; i<P_NUM_OUTPUTS; i++)
            if (cntr_sel_val_r == i)
                selected_cntr = spike_cntr[i];
    end
    
    // Debug Monitor Logic & regs
    //----------------------------
    // There are 3 registers used for the debug monitor (2 addresses).
    //  - Timestep selection: 16-bit (2 addresses), W
    //      This is written by software to select the row of the debug monitor
    //      memory to display after a test.
    //          Address: MSB=7'd14, LSB=7'd15
    //  - Partial timestep selection: 8-bit (1 address), W
    //      This is written by software to select which part of the timestep to
    //      output. This is selecting which bits of one row from the debug monitor 
    //      memory to display on the output.
    //          Address: 7'd16
    //  - Output partial timestep: 8-bit (1 address), R
    //      This is read by software after writing the appropriate value to the 
    //      'timestep' and 'partial timestep' registers. The bits associated with
    //      the selection will be output.
    //          Address 7'd17;
    
    reg [P_NUM_NEURONS:1] spiking_state;
    logic [P_NUM_NEURONS:1] spiking_state_nxt;
    
    always_ff @(posedge clk) begin
        if (rst)
            spiking_state <= '0;
        else begin
            if (nc_reset)
                spiking_state <= '0;
            else begin
                if (api_vld && |api_bus)
                    spiking_state[P_NUM_NEURONS-P_NUM_OUTPUTS:1] <= spiking_state_nxt[P_NUM_NEURONS-P_NUM_OUTPUTS:1];
                if (|net_outputs && !nc_warmup)
                    spiking_state[P_NUM_NEURONS:P_NUM_NEURONS-P_NUM_OUTPUTS+1] <= spiking_state_nxt[P_NUM_NEURONS:P_NUM_NEURONS-P_NUM_OUTPUTS+1];
            end
        end
    end
    
    always_comb begin
        spiking_state_nxt = spiking_state; // Default/else
        for (int i=1; i<=P_NUM_NEURONS-P_NUM_OUTPUTS; i++)
            if (api_bus == $bits(api_bus)'(i))
                spiking_state_nxt[i] = ~spiking_state[i];
        spiking_state_nxt[P_NUM_NEURONS:P_NUM_NEURONS-P_NUM_OUTPUTS+1] = net_outputs;
    end
    
    reg [P_NUM_NEURONS-1:0] dbg_mon_cache;
    wire dbg_mon_mem_we, dbg_mon_mem_re_p;
    reg dbg_mon_mem_re,dbg_mon_mem_re_d;
    logic [P_NUM_NEURONS-1:0] dbg_mon_mem_rdata;
    reg [$clog2(P_MAX_NUM_PERIODS+1)-1:0] dbg_mon_time_sel_r;
    logic [$clog2(P_MAX_NUM_PERIODS+1)-1:0] dbg_mon_time_sel_nxt;
    localparam L_NUM_PARTIAL_TS_IDX = P_NUM_NEURONS%8==0 ? P_NUM_NEURONS/8 : P_NUM_NEURONS/8+1;
    reg [$clog2(L_NUM_PARTIAL_TS_IDX)-1:0] dbg_mon_partial_time_sel_r;
    logic [7:0] dbg_mon_output;
    
    assign dbg_mon_mem_we = nc_evaluate & ~nc_warmup;
    assign dbg_mon_mem_re_p = sw_dbg_mon_time_sel_msb_wen | sw_dbg_mon_time_sel_lsb_wen;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            dbg_mon_time_sel_r <= '0;
            dbg_mon_partial_time_sel_r <= '0;
            dbg_mon_mem_re <= 1'b0;
            dbg_mon_mem_re_d <= 1'b0;
            dbg_mon_cache <= '0;
        end else begin
            dbg_mon_mem_re <= dbg_mon_mem_re_p;
            dbg_mon_mem_re_d <= dbg_mon_mem_re;
            if (dbg_mon_mem_re_p)
                dbg_mon_time_sel_r <= dbg_mon_time_sel_nxt;
            if (sw_dbg_mon_partial_time_sel_wen)
                dbg_mon_partial_time_sel_r <= $bits(dbg_mon_partial_time_sel_r)'(prot_wdata);
            if (dbg_mon_mem_re_d)
                dbg_mon_cache <= dbg_mon_mem_rdata;
        end
    end
    
    always_comb begin
        dbg_mon_time_sel_nxt = dbg_mon_time_sel_r; // Default/else
        if (sw_dbg_mon_time_sel_msb_wen) dbg_mon_time_sel_nxt[$clog2(P_MAX_NUM_PERIODS+1)-1:8] = prot_wdata;
        if (sw_dbg_mon_time_sel_lsb_wen) dbg_mon_time_sel_nxt[7:0] = prot_wdata;
    end
    
    sn_1r1w_mem #(
        .P_NUM_ROWS(P_MAX_NUM_PERIODS+1),
        .P_DATA_WIDTH(P_NUM_NEURONS))
    dbg_mon_mem_i (
        .rclk(clk),
        .re(dbg_mon_mem_re),
        .raddr(dbg_mon_time_sel_r),
        .rdata(dbg_mon_mem_rdata),
        .wclk(clk),
        .we(nc_evaluate & ~nc_warmup),
        .waddr(nc_io_cur_per),
        .wdata(spiking_state));
        
    always_comb begin
        dbg_mon_output = '0; // Default/else
        if (dbg_mon_partial_time_sel_r == P_NUM_NEURONS/8 && P_NUM_NEURONS%8>0)
            dbg_mon_output = $bits(dbg_mon_output)'(dbg_mon_cache[P_NUM_NEURONS-1: P_NUM_NEURONS - (P_NUM_NEURONS%8)]);
        else
            dbg_mon_output = dbg_mon_cache[dbg_mon_partial_time_sel_r*8 +: 8];
    end

    // Rdata MUX
    //------------------
    always_comb begin
        prot_rdata = '0; // Default/else
        if (sw_start_ren)          prot_rdata = 8'(start_r);
        if (sw_cur_per_msb_ren)    prot_rdata = ($clog2(P_MAX_NUM_PERIODS+1)>8) ? 8'(nc_io_cur_per[$clog2(P_MAX_NUM_PERIODS+1)-1:8]) : '0;
        if (sw_cur_per_lsb_ren)    prot_rdata = 8'(nc_io_cur_per);
        if (sw_selected_cntr_ren)  prot_rdata = 8'(selected_cntr);
        if (sw_dbg_mon_output_ren) prot_rdata = 8'(dbg_mon_output);
        if (sw_max_per_msb_ren)    prot_rdata = max_per_msb_r;
        if (sw_max_per_lsb_ren)    prot_rdata = max_per_lsb_r;
    end
    
endmodule