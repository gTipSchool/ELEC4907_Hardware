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
module sn_1r1w_mem
    #(
        parameter P_DATA_WIDTH=21,
        parameter P_NUM_ROWS=1000
    )
    (
        input wclk,
        input we,
        input [$clog2(P_NUM_ROWS)-1:0] waddr,
        input [P_DATA_WIDTH-1:0] wdata,
        input rclk,
        input re,
        input [$clog2(P_NUM_ROWS)-1:0] raddr,
        output logic [P_DATA_WIDTH-1:0] rdata
    );

    // Declarations:
    //------------------
    reg [P_DATA_WIDTH-1:0] mem [P_NUM_ROWS];
    wire [P_DATA_WIDTH-1:0] rdata_p;
    reg [P_DATA_WIDTH-1:0] rdata_ff;
    
    // Memory flops
    always_ff @(posedge wclk) begin
        if (we) mem[waddr] <= wdata;
    end
    
    // Unstaged output read data
    assign rdata_p = mem[raddr];
    
    // Staged output read data
    always_ff @(posedge rclk) begin
        if (re) rdata_ff <= rdata_p;
    end
    
    assign rdata = rdata_ff;

endmodule