/* sn_network_top_wrapper_generated:
 *	Generated RTL wrapper for sn_network_top module.
 *	The configured top-level parameters are calculated for a specific network configuration.
 *	The weights, constant currents, and step lengths for all neurons are configured automatically.
 *	DO NOT MODIFY.
 */ 
module sn_network_top_wrapper_generated
	(
	 // Top clock and reset.
	 input clk_in1_p,
	 input clk_in1_n,
	 input rst,
	 // UART signals
	 input rx_input,
	 output tx_output
	);

	// Declarations:
	//---------------
	localparam L_NEUR_MODEL_CFG = 0;
	localparam L_NUM_NEURONS = 41;
	localparam L_NUM_INPUTS = 23;
	localparam L_NUM_OUTPUTS = 3;
	localparam L_TABLE_WEIGHT_BW = 7;
	localparam L_TABLE_WEIGHT_PRECISION = 1;
	localparam L_TABLE_MAX_NUM_ROWS = 5;
	localparam L_TABLE_DFLT_NUM_ROWS = 0;
	localparam L_NEUR_CURRENT_BW = 8;
	localparam L_NEUR_MODEL_PRECISION = 10;
	localparam L_NEUR_IZH_HIGH_PREC_EN = 0;
	localparam L_DFLT_CNTR_VAL = 40;
	localparam L_NEUR_STEP_CNTR_BW = 0;
	localparam L_MAX_NUM_PERIODS = 5000;
	localparam L_TABLE_IDX_BW = $clog2(L_NUM_NEURONS-L_NUM_OUTPUTS+1);

	localparam L_UART_CLKS_PER_BIT = 87;
	localparam L_UART_BITS_PER_PKT = 10;
	localparam L_PROT_WATCHDOG_TIME = 870000000;
	localparam integer L_TABLE_NUM_ROWS_ARRAY [L_NUM_NEURONS-L_NUM_INPUTS:1] = {2,1,2,3,3,2,2,3,3,3,3,3,3,3,5,3,3,3};
	localparam integer L_NEUR_CONST_CURRENT_ARRAY [L_NUM_NEURONS-L_NUM_INPUTS:1] = {0,0,0,0,0,0,8,0,0,0,0,0,0,0,0,0,0,0};
	localparam integer L_NEUR_CNTR_VAL_ARRAY [L_NUM_NEURONS:1] = {40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40};

	localparam L_CTC_PER_NEUR_BW = L_TABLE_MAX_NUM_ROWS*(L_TABLE_WEIGHT_BW+L_TABLE_IDX_BW);
	logic [L_NUM_NEURONS-L_NUM_INPUTS:1] [L_TABLE_MAX_NUM_ROWS-1:0] [L_TABLE_WEIGHT_BW+L_TABLE_IDX_BW-1:0] cfg_table_contents;

	assign cfg_table_contents = {
		//N41 (Subsystem_Left_Output_41)
		L_CTC_PER_NEUR_BW'({
			L_TABLE_IDX_BW'(27),L_TABLE_WEIGHT_BW'(-60),
			L_TABLE_IDX_BW'(38),L_TABLE_WEIGHT_BW'(16)}),
		//N40 (Subsystem_Forward_Output_40)
		L_CTC_PER_NEUR_BW'({
			L_TABLE_IDX_BW'(27),L_TABLE_WEIGHT_BW'(28)}),
		//N39 (Subsystem_Right_Output_39)
		L_CTC_PER_NEUR_BW'({
			L_TABLE_IDX_BW'(27),L_TABLE_WEIGHT_BW'(-60),
			L_TABLE_IDX_BW'(37),L_TABLE_WEIGHT_BW'(16)}),
		//N38 (Subsystem 38)
		L_CTC_PER_NEUR_BW'({
			L_TABLE_IDX_BW'(36),L_TABLE_WEIGHT_BW'(12),
			L_TABLE_IDX_BW'(35),L_TABLE_WEIGHT_BW'(-12),
			L_TABLE_IDX_BW'(34),L_TABLE_WEIGHT_BW'(20)}),
		//N37 (Subsystem 37)
		L_CTC_PER_NEUR_BW'({
			L_TABLE_IDX_BW'(36),L_TABLE_WEIGHT_BW'(-12),
			L_TABLE_IDX_BW'(33),L_TABLE_WEIGHT_BW'(20),
			L_TABLE_IDX_BW'(35),L_TABLE_WEIGHT_BW'(12)}),
		//N36 (Subsystem 36)
		L_CTC_PER_NEUR_BW'({
			L_TABLE_IDX_BW'(33),L_TABLE_WEIGHT_BW'(-12),
			L_TABLE_IDX_BW'(34),L_TABLE_WEIGHT_BW'(-12)}),
		//N35 (Subsystem 35)
		L_CTC_PER_NEUR_BW'({
			L_TABLE_IDX_BW'(34),L_TABLE_WEIGHT_BW'(-12),
			L_TABLE_IDX_BW'(33),L_TABLE_WEIGHT_BW'(2)}),
		//N34 (Subsystem 34)
		L_CTC_PER_NEUR_BW'({
			L_TABLE_IDX_BW'(27),L_TABLE_WEIGHT_BW'(-80),
			L_TABLE_IDX_BW'(31),L_TABLE_WEIGHT_BW'(-24),
			L_TABLE_IDX_BW'(32),L_TABLE_WEIGHT_BW'(24)}),
		//N33 (Subsystem 33)
		L_CTC_PER_NEUR_BW'({
			L_TABLE_IDX_BW'(27),L_TABLE_WEIGHT_BW'(-80),
			L_TABLE_IDX_BW'(32),L_TABLE_WEIGHT_BW'(-24),
			L_TABLE_IDX_BW'(31),L_TABLE_WEIGHT_BW'(24)}),
		//N32 (Subsystem 32)
		L_CTC_PER_NEUR_BW'({
			L_TABLE_IDX_BW'(30),L_TABLE_WEIGHT_BW'(24),
			L_TABLE_IDX_BW'(29),L_TABLE_WEIGHT_BW'(24),
			L_TABLE_IDX_BW'(28),L_TABLE_WEIGHT_BW'(24)}),
		//N31 (Subsystem 31)
		L_CTC_PER_NEUR_BW'({
			L_TABLE_IDX_BW'(24),L_TABLE_WEIGHT_BW'(24),
			L_TABLE_IDX_BW'(25),L_TABLE_WEIGHT_BW'(24),
			L_TABLE_IDX_BW'(26),L_TABLE_WEIGHT_BW'(24)}),
		//N30 (Subsystem 30)
		L_CTC_PER_NEUR_BW'({
			L_TABLE_IDX_BW'(22),L_TABLE_WEIGHT_BW'(18),
			L_TABLE_IDX_BW'(23),L_TABLE_WEIGHT_BW'(18),
			L_TABLE_IDX_BW'(21),L_TABLE_WEIGHT_BW'(18)}),
		//N29 (Subsystem 29)
		L_CTC_PER_NEUR_BW'({
			L_TABLE_IDX_BW'(20),L_TABLE_WEIGHT_BW'(18),
			L_TABLE_IDX_BW'(18),L_TABLE_WEIGHT_BW'(18),
			L_TABLE_IDX_BW'(19),L_TABLE_WEIGHT_BW'(18)}),
		//N28 (Subsystem 28)
		L_CTC_PER_NEUR_BW'({
			L_TABLE_IDX_BW'(16),L_TABLE_WEIGHT_BW'(18),
			L_TABLE_IDX_BW'(17),L_TABLE_WEIGHT_BW'(18),
			L_TABLE_IDX_BW'(15),L_TABLE_WEIGHT_BW'(18)}),
		//N27 (Subsystem 27)
		L_CTC_PER_NEUR_BW'({
			L_TABLE_IDX_BW'(11),L_TABLE_WEIGHT_BW'(28),
			L_TABLE_IDX_BW'(12),L_TABLE_WEIGHT_BW'(28),
			L_TABLE_IDX_BW'(14),L_TABLE_WEIGHT_BW'(28),
			L_TABLE_IDX_BW'(13),L_TABLE_WEIGHT_BW'(28),
			L_TABLE_IDX_BW'(10),L_TABLE_WEIGHT_BW'(28)}),
		//N26 (Subsystem 26)
		L_CTC_PER_NEUR_BW'({
			L_TABLE_IDX_BW'(9),L_TABLE_WEIGHT_BW'(18),
			L_TABLE_IDX_BW'(8),L_TABLE_WEIGHT_BW'(18),
			L_TABLE_IDX_BW'(7),L_TABLE_WEIGHT_BW'(18)}),
		//N25 (Subsystem 25)
		L_CTC_PER_NEUR_BW'({
			L_TABLE_IDX_BW'(6),L_TABLE_WEIGHT_BW'(18),
			L_TABLE_IDX_BW'(5),L_TABLE_WEIGHT_BW'(18),
			L_TABLE_IDX_BW'(4),L_TABLE_WEIGHT_BW'(18)}),
		//N24 (Subsystem 24)
		L_CTC_PER_NEUR_BW'({
			L_TABLE_IDX_BW'(3),L_TABLE_WEIGHT_BW'(18),
			L_TABLE_IDX_BW'(2),L_TABLE_WEIGHT_BW'(18),
			L_TABLE_IDX_BW'(1),L_TABLE_WEIGHT_BW'(18)})};

	// Network Top Module Instance:
	//------------------------------
	sn_network_top_cfg #(
		.P_NUM_NEURONS(L_NUM_NEURONS),
		.P_NUM_INPUTS(L_NUM_INPUTS),
		.P_NUM_OUTPUTS(L_NUM_OUTPUTS),
		.P_TABLE_NUM_ROWS_ARRAY(L_TABLE_NUM_ROWS_ARRAY),
		.P_TABLE_MAX_NUM_ROWS(L_TABLE_MAX_NUM_ROWS),
		.P_NEUR_CONST_CURRENT_ARRAY(L_NEUR_CONST_CURRENT_ARRAY),
		.P_NEUR_CNTR_VAL_ARRAY(L_NEUR_CNTR_VAL_ARRAY),
		.P_TABLE_DFLT_NUM_ROWS(L_TABLE_DFLT_NUM_ROWS),
		.P_TABLE_WEIGHT_BW(L_TABLE_WEIGHT_BW),
		.P_TABLE_WEIGHT_PRECISION(L_TABLE_WEIGHT_PRECISION),
		.P_NEUR_CURRENT_BW(L_NEUR_CURRENT_BW),
		.P_NEUR_MODEL_CFG(L_NEUR_MODEL_CFG),
		.P_NEUR_MODEL_PRECISION(L_NEUR_MODEL_PRECISION),
		.P_NEUR_IZH_HIGH_PREC_EN(L_NEUR_IZH_HIGH_PREC_EN),
		.P_DFLT_CNTR_VAL(L_DFLT_CNTR_VAL),
		.P_NEUR_STEP_CNTR_BW(L_NEUR_STEP_CNTR_BW),
		.P_MAX_NUM_PERIODS(L_MAX_NUM_PERIODS),
		.P_UART_CLKS_PER_BIT(L_UART_CLKS_PER_BIT),
		.P_UART_BITS_PER_PKT(L_UART_BITS_PER_PKT),
		.P_PROT_WATCHDOG_TIME(L_PROT_WATCHDOG_TIME),
		.P_CLK_GEN_EN(1))
	network_i (
		.clk_in1_p(clk_in1_p),
		.clk_in1_n(clk_in1_n),
		.rst(rst),
		// UART Interface
		.rx_input(rx_input),
		.tx_output(tx_output),
		// CFG
		.cfg_table_contents(cfg_table_contents));

endmodule