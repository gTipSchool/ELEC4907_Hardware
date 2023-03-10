/* gen_wrapper.c:
 *      Called to generate a top-level RTL wrapper configuring custom 
 *      spiking neural network hardware.
 *      The configuration is specified through an network configuration input file 
 *      called as the only argument, whose format is standardized and generated 
 *      using a MATLAB script.
 *
 * Created by Grant Tippett on March 9th, 2023.
 */

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <inttypes.h>
#include <sys/types.h>
#include <stdbool.h>
#include <math.h>

// Data Structures:
//==================
struct HLParams {
    int l_num_neurons;
    int l_num_inputs;
    int l_num_outputs;
    int l_max_num_periods;
    int l_dflt_cntr_val;
    int l_neur_model_precision;
    int l_table_weight_precision;
    int l_table_weight_bw;
    int l_table_max_num_rows;
    int l_table_dflt_num_rows;
    int l_neur_current_bw;
    int l_neur_step_cntr_bw;
    int l_uart_clks_per_bit;
    int l_uart_bits_per_pkt;
    long l_prot_watchdog_time;
    bool l_neur_model_cfg;
    bool l_neur_izh_high_prec_en;
};
 typedef struct Neuron Neuron;
 struct Weight {
    int assoc_neuron;
    int value;
    Weight* next_weight;
 };
 struct Neuron {
    int idx;
    char id [30];
    int num_weights;
    int const_current;
    Weight* first_weight;
 };

// Functions:
//============
void assignParams(struct HLParams params, int param_arr[]){
    params.l_num_neurons = param_arr[0];
    params.l_num_inputs = param_arr[1];
    params.l_num_outputs = param_arr[2];
    params.l_max_num_periods = param_arr[3];
    params.l_dflt_cntr_val = param_arr[4];
    params.l_neur_model_precision = param_arr[5];
    params.l_table_weight_precision = param_arr[6];
    params.l_table_weight_bw = 9;
    params.l_table_max_num_rows = 0// TODO calculated in another func in a later step;
    params.l_table_dflt_num_rows = 0; // TODO ^
    params.l_neur_current_bw = 0; // TODO ^
    params.l_neur_step_cntr_bw = 0;
    params.l_uart_clks_per_bit = 87;
    params.l_uart_bits_per_pkt = 10;
    params.l_prot_watchdog_time = params.l_uart_clks_per_bit * params.l_uart_bits_per_pkt * 1000000;
    params.l_neur_model_cfg = 0; //0 for izh, 1 for i&f
    params.l_neur_izh_high_prec_en = 0;
}
int findNeur(struct Neuron neur_arr[], int num_neurons, int dest_idx){
    // Search the list for the destination neuron and return the index. If it can't be found, return -1.
    for (int i=0; i<num_neurons; i++) if (neur_arr[i].idx==dest_idx) return i;
    return -1;
}
void addWeight(struct Neuron* neur, int src_idx, double value, int precision){
    if (src_icx==0){
        // Not a weight, but a constant current.
        neur->const_current = (int)(value * 2^precision);
    }
    else {
        // Normal weight.
        struct Weight* cur_weight = neur.first_weight;
        // Find the last weight in the neuron's weight list.
        while (cur_weight != NULL) cur_weight = cur_weight.next_weight;
        // Create the weight and add it to the list.
        cur_weight = (Weight*)malloc(sizeof(Weight));
        cur_weight->assoc_neuron = src_idx;
        cur_weight->value = (int)(value * 2^precision); // Convert it to an int with the specified fixed point precision.
        cur_weight->next_weight = NULL;
        neur->num_weights++;
    }
    return;
}
void calcRemParams(struct Neuron neur_arr[], struct HLParams params){
    int max_rows=0;
    int max_weight=0;
    int spec_max_weight;
    int max_const_current=0;
    int spec_max_const_current;
    int wc_current=0; // This calculation will not produce the actual worst case because it uses sum of absolute weight/current values.
    int spec_wc_current;
    struct Neuron* cur_neuron;
    struct Weight* cur_weight;

    for (int i=0; i<params.l_num_neurons; i++){
        cur_neuron = neur_arr[i];
        // Update max const current.
        spec_max_const_current = abs(cur_neuron->const_current);
        if (spec_max_const_current > max_const_current) max_const_current = spec_max_const_current;
        spec_wc_current = spec_max_const_current;
        // Update the max num weights.
        if (cur_neuron->num_weights > max_rows) max_rows = cur_neuron->num_weights;
        // Update the maximum weight value and worst case current.
        cur_weight = cur_neuron->const_current;
        while (cur_weight != NULL){
            spec_max_weight = abs(cur_weight->value);
            if (spec_max_weight > max_weight) max_weight = spec_max_weight;
            spec_wc_current += spec_max_weight;
            cur_weight = cur_weight->next_weight;
        }
        // Update worst-case current.
        if (spec_wc_current > wc_current) wc_current = spec_wc_current;
    }
    // Update params:
    params.l_table_max_num_rows = max_rows;
    params.l_table_dflt_num_rows = 0;
    params.l_table_weight_bw = (int)ceil(log2(max_weight));
    params.l_neur_current_bw = (int)ceil(log2(wc_current));
    return;
}
bool strcmpl(const char* str1, const char* str2, int limit){
    for (int i=0; i<limit; i++){
        if (*(str1+i)=='\0' && *(str2+i)=='\0') break;
        if (*(str1+i)!=*(str2+i)) return false;
    }
    return true;
 }
 bool strstrip(char* str, const char delimiter){
    for (int i=0; src; i++){
        if (*(src+i)=='\0') return false;
        else if (*(src+i)==delimiter){
            *(src+i)='\0'; return true;
        }
    }
 }

// Main Function:
//================
 int main(int argc, char *argv[]){
    // Error checking:
    //-----------------
    if (argc!=2){
        printf("Error in gen_wrapper.c: No network configuration file specified.\n");
        return 0;
    }
    
    char* infilename = argv[1];
    FILE *infile = fopen(infilename,"r+t");
    if (infile == NULL){
        printf("Error in gen_wrapper.c: Can't open %s\n",infilename);
        fclose(infile);
        return 0;
    }
    // Variable Declarations:
    //------------------------
    // High level params:
    int num_file_params=8;
    int file_params [num_file_params];
    struct HLParams rtl_params;
    // TODO l_table_num_rows_array, l_neur_const_current_array, l_neur_cntr_val_array
    
    // Loop vars:
    char line [300];
    int line_cnt=0;
    int parse_step = 0; // current step in the process of parsing the input file.
    const int c_last_parse_step = 3;
    int param_cnt = 0; // Used in step 1 to identify the parameter.
    char* token; // Used in parsing LUT and weights in steps 2/3.
    int cur_dest_idx = 0;
    int cur_src_idx = 0;
    double cur_weight = 0;
    // Neuron list:
    Neuron* neurons;
    int neur_cnt=0;

    // Output file:
    // Module name
    char outfilename_short [] = "sn_network_top_wrapper_generated";
    // File name
    char outfilename [] = strcat(strcpy(outfilename_short),".sv");

    // Parsing the input file:
    //-------------------------
    do {
        // Get a line from the file:
        if (fgets(line, sizeof(line), infile) == 0) { 
            // EOF?
            if (feof(inFile)) break;
        }
        line_cnt++;

        // Conditionally do something with the line:
        switch (parse_step){
            case 0: // Search lines until an identifier is found that starts a parse step:
                if (strcmpl(line,"High-level",10)) parse_step = 1;
                else if (strcmpl(line,"Neuron ID/Address",10)) parse_step = 2;
                else if (strcmpl(line,"Sources",7)) parse_step = 3;

            case 1: // Collect all high-level params:
                // Check if we've reached the end of the params section (empty line).
                if (*line=='\n'){
                    // Setup for next step: populate rtl_params struct and create array of neuron.
                    assignParams(rtl_params,file_params);
                    neurons = malloc(rtl_params.l_num_neurons * sizeof(Neuron));
                    parse_step = 0;
                    continue;
                }
                if (strstrip(line,' ')==false){
                    printf("Error parsing high level params in %s: unexpected content on line %d.\n",infilename,line_cnt);
                    fclose(infile);
                    return 0;
                }
                file_params[param_cnt] = atoi(line);
                param_cnt++;
            
            case 2: // Create a lookup table for neuron IDs and indices:
                // Check if we've reached the end of the LUT section (empty line).
                if (*line=='\n'){
                    parse_step = 0;
                    continue;
                }
                token = strtok(line," ");
                if (token==NULL){
                    printf("Error parsing lookup table in %s: not enough tokens on line %d.\n",infilename,line_cnt);
                    fclose(infile);
                    return 0;
                }
                neurons[neur_cnt].idx = atoi(token);
                token = strtok(NULL,"\n");
                if (token==NULL){
                    printf("Error parsing lookup table in %s: not enough tokens on line %d.\n",infilename,line_cnt);
                    fclose(infile);
                    return 0;
                }
                strcpy(neurons[neur_cnt].id,token);
                neurons[neur_cnt].first_weight = NULL;
                neurons[neur_cnt].num_weights = 0;
                neur_cnt++;
                
            case 3: // Populate the netlist datastructure:
                token = strtok(line," ");
                if (token==NULL){
                    printf("Error parsing weight list in %s: not enough tokens on line %d.\n",infilename,line_cnt);
                    fclose(infile);
                    return 0;
                }
                cur_dest_idx = atoi(token);
                token = strtok(NULL," ");
                if (token==NULL){
                    printf("Error parsing weight list in %s: not enough tokens on line %d.\n",infilename,line_cnt);
                    fclose(infile);
                    return 0;
                }
                // Check if the source is "Constant", indicating that this is a constant weight.
                if (strcmpl(token,"Constant",8)) cur_src_idx = 0;
                else cur_src_idx = atoi(token);
                token = strtok(NULL,"\n");
                if (token==NULL){
                    printf("Error parsing weight list in %s: not enough tokens on line %d.\n",infilename,line_cnt);
                    fclose(infile);
                    return 0;
                }
                cur_weight = atof(token);
                // Now find the dest neuron and add the weight.
                cur_dest_idx = findNeur(neurons,rtl_params.l_num_neurons,cur_dest_idx)
                if (cur_dest_idx==-1){
                    printf("Error parsing weight list in %s: Destination neuron on line %d does not exist in the lookup table.\n",infilename,line_cnt);
                    fclose(infile);
                    return 0;
                }
                addWeight(neurons[cur_dest_idx],cur_src_idx,cur_weight,rtl_params.l_table_weight_precision);
        }
    } while true;
    fclose(infile);
    // Error check:
    if (parse_step != c_last_parse_step){
        printf("Error parsing %s: File is incomplete.\n",infilename);
        return 0;
    }

    // Calculate the remaining of RTL parameters:
    //--------------------------------------------
    // Calculate max num rows by iterating through all the neurons and finding the max 
    calcRemParams(neurons,rtl_params);
    //L_TABLE_NUM_ROWS_ARRAY can be found by looping through neurons.
    //L_NEUR_CONST_CURRENT_ARRAY can be done by looping through neurons.
    //L_NEUR_CNTR_VAL_ARRAY for now just set to the default value.

    // Generating the top-level wrapper:
    //-----------------------------------
    FILE* outfile = fopen(outfilename, "w");
    if (f == NULL){
        printf("Error opening output file %s\n", outfilename);
        return 0;
    }
    fprintf(outfile,"/* %s:\n *\tGenerated RTL wrapper for sn_network_top module.\n"
                            " *\tThe configured top-level parameters are calculated, \n"
                            " *\tDO NOT MODIFY.\n */\n",outfilename_short);
    fprintf(outfile,"module %s\n",outfilename_short);
    fprintf(outfile,
        "\t(\n"
        "\t // Top clock and reset.\n"
        "\t input clk_in1_p,\n"
        "\t input clk_in1_n,\n"
        "\t input rst,\n"
        "\t // UART signals\n"
        "\t input rx_input,\n"
        "\t output tx_output\n"
        "\t);\n"
        "\n"
        "\t// Declarations\n"
        "\t//-------------------\n");
    fprintf(outfile,"\tlocalparam L_NEUR_MODEL_CFG = %d;\n",rtl_params.l_neur_model_cfg);
    fprintf(outfile,"\tlocalparam L_NUM_NEURONS = %d;\n",rtl_params.l_num_neurons);
    fprintf(outfile,"\tlocalparam L_NUM_INPUTS = %d;\n",rtl_params.l_num_inputs);
    fprintf(outfile,"\tlocalparam L_NUM_OUTPUTS = %d;\n",rtl_params.l_num_outputs);
    fprintf(outfile,"\tlocalparam L_TABLE_WEIGHT_BW = %d;\n",rtl_params.l_table_weight_bw);
    fprintf(outfile,"\tlocalparam L_TABLE_WEIGHT_PRECISION = %d;\n",rtl_params.l_table_weight_precision);
    fprintf(outfile,"\tlocalparam L_TABLE_MAX_NUM_ROWS = %d;\n",rtl_params.l_table_max_num_rows);
    fprintf(outfile,"\tlocalparam L_TABLE_DFLT_NUM_ROWS = %d;\n",rtl_params.l_table_dflt_num_rows);
    fprintf(outfile,"\tlocalparam L_NEUR_CURRENT_BW = %d;\n",rtl_params.l_neur_current_bw);
    fprintf(outfile,"\tlocalparam L_NEUR_MODEL_PRECISION = %d;\n",rtl_params.l_neur_model_precision);
    fprintf(outfile,"\tlocalparam L_NEUR_HIGH_PREC_EN = %d;\n",rtl_params.l_neur_izh_high_prec_en);
    fprintf(outfile,"\tlocalparam L_DFLT_CNTR_VAL = %d;\n",rtl_params.l_dflt_cntr_val);
    fprintf(outfile,"\tlocalparam L_NEUR_STEP_CNTR_BW = %d;\n",rtl_params.l_neur_step_cntr_bw);
    fprintf(outfile,"\tlocalparam L_MAX_NUM_PERIODS = %d;\n",rtl_params.l_max_num_periods);
    fprintf(outfile,"\tlocalparam L_TABLE_IDX_BW = $clog2(L_NUM_NEURONS-L_NUM_OUTPUTS+1);\n");
    fprintf(outfile,"\n\tlocalparam L_UART_CLKS_PER_BIT = %d;\n",rtl_params.l_uart_clks_per_bit);
    fprintf(outfile,"\tlocalparam L_UART_BITS_PER_PKT = %d;\n",rtl_params.l_uart_bits_per_pkt);
    fprintf(outfile,"\tlocalparam L_PROT_WATCHDOG_TIME = %d;\n",rtl_params.l_prot_watchdog_time);
    //L_TABLE_NUM_ROWS_ARRAY
    fprintf(outfile,"\tlocalparam L_TABLE_NUM_ROWS_ARRAY = {");
    for (int i=rtl_params.l_num_neurons-1; i>=rtl_params.l_num_inputs; i++){
        fprintf(outfile,"%s",neurons[findNeur(neurons,rtl_params.l_num_neurons,i)].num_weights);
        if (i!=rtl_params.l_num_inputs) fprintf(outfile,",");
    }
    fprintf(outfile,"};\n");
    //L_NEUR_CONST_CURRENT_ARRAY
    fprintf(outfile,"\tlocalparam L_NEUR_CONST_CURRENT_ARRAY = {");
    for (int i=rtl_params.l_num_neurons-1; i>=rtl_params.l_num_inputs; i++){
        fprintf(outfile,"%s",neurons[findNeur(neurons,rtl_params.l_num_neurons,i)].const_current);
        if (i!=rtl_params.l_num_inputs) fprintf(outfile,",");
    }
    fprintf(outfile,"};\n");
    //L_NEUR_CNTR_VAL_ARRAY
    fprintf(outfile,"\tlocalparam L_NEUR_CNTR_VAL_ARRAY = {");
    for (int i=rtl_params.l_num_neurons-1; i>=0; i++){
        fprintf(outfile,"%s",rtl_params.l_dflt_cntr_val); // FIXME if at some point all neurons have differing step lengths.
        if (i!=0) fprintf(outfile,",");
    }
    fprintf(outfile,"};\n\n");

    // Weight contents:
    fprintf(outfile,"\tlocalparam L_CTC_PER_NEUR_BW = L_TABLE_MAX_NUM_ROWS*(L_TABLE_WEIGHT_BW+L_TABLE_IDX_BW);\n");
    fprintf(outfile,"\tlogic [L_NUM_NEURONS-L_NUM_INPUTS:1] [L_TABLE_MAX_NUM_ROWS-1:0] [L_TABLE_WEIGHT_BW+L_TABLE_IDX_BW-1:0] cfg_table_contents;\n");
    fprintf(outfile,"\tassign cfg_table_contents = {\n");
    Weight* cur_weight;
    for (int i=rtl_params.l_num_neurons-1; i>=rtl_params.l_num_inputs; i++){
        cur_weight = neurons[i].first_weight;
        fprintf(outfile,"\t\tL_CTC_PER_NEUR_BW'({\n");
        while (cur_weight != NULL){
            fprintf(outfile,"\t\t\tL_TABLE_IDX_BW'(%d),L_TABLE_WEIGHT_BW'(%d)",cur_weight.assoc_neuron,cur_weight.value);
            if (cur_weight!=NULL) fprintf(outfile,",\n");
        }
        if (i!=rtl_params.l_num_inputs) fprintf(outfile,"}),\n");
        else fprintf(outfile,"})};\n");
    }

    // network_top_cfg Instantiation:
    fprintf(outfile,
        "\tsn_network_top_cfg #(\n"
        "\t\t.P_NUM_NEURONS(L_NUM_NEURONS),\n"
        "\t\t.P_NUM_INPUTS(L_NUM_INPUTS),\n"
        "\t\t.P_NUM_OUTPUTS(L_NUM_OUTPUTS),\n"
        "\t\t.P_TABLE_NUM_ROWS_ARRAY(L_TABLE_NUM_ROWS_ARRAY),\n"
        "\t\t.P_TABLE_MAX_NUM_ROWS(L_TABLE_MAX_NUM_ROWS),\n"
        "\t\t.P_NEUR_CONST_CURRENT_ARRAY(L_NEUR_CONST_CURRENT_ARRAY),\n"
        "\t\t.P_NEUR_CNTR_VAL_ARRAY(L_NEUR_CNTR_VAL_ARRAY),\n"
        "\t\t.P_TABLE_DFLT_NUM_ROWS(L_TABLE_DFLT_NUM_ROWS),\n"
        "\t\t.P_TABLE_WEIGHT_BW(L_TABLE_WEIGHT_BW),\n"
        "\t\t.P_TABLE_WEIGHT_PRECISION(L_TABLE_WEIGHT_PRECISION),\n"
        "\t\t.P_NEUR_CURRENT_BW(L_NEUR_CURRENT_BW),\n"
        "\t\t.P_NEUR_MODEL_CFG(L_NEUR_MODEL_CFG),\n"
        "\t\t.P_NEUR_MODEL_PRECISION(L_NEUR_MODEL_PRECISION),\n"
        "\t\t.P_NEUR_IZH_HIGH_PREC_EN(L_NEUR_IZH_HIGH_PREC_EN),\n"
        "\t\t.P_DFLT_CNTR_VAL(L_DFLT_CNTR_VAL),\n"
        "\t\t.P_NEUR_STEP_CNTR_BW(L_NEUR_STEP_CNTR_BW),\n"
        "\t\t.P_MAX_NUM_PERIODS(L_MAX_NUM_PERIODS),\n"
        "\t\t.P_UART_CLKS_PER_BIT(L_UART_CLKS_PER_BIT),\n"
        "\t\t.P_UART_BITS_PER_PKT(L_UART_BITS_PER_PKT),\n"
        "\t\t.P_PROT_WATCHDOG_TIME(L_PROT_WATCHDOG_TIME),\n"
        "\t\t.P_CLK_GEN_EN(1)\n"
        "\t\t)\n"
        "\tnetwork_i (\n"
        "\t\t.clk_in1_p(clk_in1_p),\n"
        "\t\t.clk_in1_n(clk_in1_n),\n"
        "\t\t.rst(rst),\n"
        "\t\t// UART Interface\n"
        "\t\t.rx_input(rx_input),\n"
        "\t\t.tx_output(tx_output),\n"
        "\t\t// CFG\n"
        "\t\t.cfg_table_contents(cfg_table_contents)\n"
        "\t);\n");
    // End of the module:
    fprintf(outfile,"\nendmodule");
    fclose(outfile);

    // Create Testbench file:

    // Free the allocated memory for the weights in the neuron list and then the neurons themselves:

 }