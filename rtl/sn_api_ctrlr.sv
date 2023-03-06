/*
    sn_api_ctrlr:
    Arbitrates access to the Axon Protocol Bus
    for all neurons.
    Note: This might be able to be optimized.
          Currently every transmit period will
          take as many cycles as there are neurons.
          There may be a way to optimize, by only
          allowing spiking neurons to transmit.
*/
module sn_api_ctrlr
    #(
        parameter P_NUM_NEURONS=100,
        parameter P_NUM_INPUTS=45,
        parameter P_NUM_OUTPUTS=3
    )
    (
        // Generic
        input clk,
        input rst,
        // Network Controller
        input nc_transmit,
        output api_nc_done,
        // Neurons
        input [P_NUM_NEURONS-P_NUM_OUTPUTS:1] api_pending,
        output logic [P_NUM_NEURONS-P_NUM_OUTPUTS:1] api_granted,
        output api_vld
    );

    // Declarations:
    //------------------
    reg [P_NUM_NEURONS-P_NUM_OUTPUTS:2] idx_vld_sr;
    reg nc_transmit_d;
    wire nc_transmit_pe; // pe=positive edge
    wire no_pending, no_pending_at_trans;
    wire api_nc_done_w;
    wire pending;
    
    assign pending = |api_pending; // If any of the neurons are pending.
    assign no_pending_at_trans = nc_transmit & ~pending; // For debug only.

    assign nc_transmit_pe = ~nc_transmit_d & nc_transmit;
    always_ff @(posedge clk) begin
        if (rst) begin
            idx_vld_sr <= '0;
            nc_transmit_d <= '0;
        end else begin
            nc_transmit_d <= nc_transmit;
            if (api_nc_done_w)
                idx_vld_sr <= '0;
            else if (nc_transmit)
                idx_vld_sr <= $bits(idx_vld_sr)'({idx_vld_sr, nc_transmit_pe & pending});
        end
    end
    
    assign api_nc_done_w = ~pending & nc_transmit;//(idx_vld_sr[P_NUM_NEURONS-P_NUM_OUTPUTS] | ~pending) & nc_transmit;
    assign api_nc_done = api_nc_done_w;

    always_comb begin
        api_granted = '0; // Default/Else
        api_granted[1] = api_pending[1] & nc_transmit_pe;
        for (int i=2; i<=P_NUM_NEURONS-P_NUM_OUTPUTS; i++)
            api_granted[i] = api_pending[i] & idx_vld_sr[i];
    end

    assign api_vld = |api_granted;
    
endmodule