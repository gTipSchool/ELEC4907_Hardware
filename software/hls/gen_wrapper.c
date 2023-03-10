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
    //int p_neur_step_cntr_bw;
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
    Weight* first_weight;
 };

// Functions:
//============
void assignParams(struct HLParams params, int param_arr[]){
    params.l_num_neurons = param_arr[0];
    params.l_num_inputs = param_arr[1];;
    params.l_num_outputs = param_arr[2];;
    params.l_max_num_periods = param_arr[3];;
    params.l_dflt_cntr_val = param_arr[4];
    params.l_neur_model_precision = param_arr[5];;
    params.l_table_weight_precision = param_arr[6];;
    params.l_table_weight_bw = 9;
    params.l_table_max_num_rows = 0// TODO calculated in another func in a later step;
    params.l_table_dflt_num_rows = 0; // TODO ^
    params.l_neur_current_bw = 0; // TODO ^
    //params.p_neur_step_cntr_bw = ;
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
void addWeight(struct Neuron* neur, int src_idx, double value){
    struct Weight* cur_weight = neur.first_weight;
    // Find the end of the list.
    while (cur_weight != NULL) cur_weight = cur_weight.next_weight;
    // Create the weight and add it to the list.
    cur_weight = (Weight*)malloc(sizeof(Weight));
    cur_weight->assoc_neuron = src_idx;
    cur_weight->value = value;
    cur_weight->next_weight = NULL;
    neur->num_weights++;
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
    if (infile == NULL) printf("Error in gen_wrapper.c: Can't open %s\n",infilename);
    
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
    char outfilename [] = "sn_network_top_wrapper.sv";

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
                    return 0;
                }
                neurons[neur_cnt].idx = atoi(token);
                token = strtok(NULL,"\n");
                if (token==NULL){
                    printf("Error parsing lookup table in %s: not enough tokens on line %d.\n",infilename,line_cnt);
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
                    return 0;
                }
                cur_dest_idx = atoi(token);
                token = strtok(NULL," ");
                if (token==NULL){
                    printf("Error parsing weight list in %s: not enough tokens on line %d.\n",infilename,line_cnt);
                    return 0;
                }
                // Check if the source is "Constant", indicating that this is a constant weight.
                if (strcmpl(token,"Constant",8)) cur_src_idx = 0;
                else cur_src_idx = atoi(token);
                token = strtok(NULL,"\n");
                if (token==NULL){
                    printf("Error parsing weight list in %s: not enough tokens on line %d.\n",infilename,line_cnt);
                    return 0;
                }
                cur_weight = atof(token);
                // Now find the dest neuron and add the weight.
                cur_dest_idx = findNeur(neurons,rtl_params.l_num_neurons,cur_dest_idx)
                if (cur_dest_idx==-1){
                    printf("Error parsing weight list in %s: Destination neuron on line %d does not exist in the lookup table.\n",infilename,line_cnt);
                    return 0;
                }
                addWeight(neurons[cur_dest_idx],cur_src_idx,cur_weight);
        }
    } while true;
    // Error check:
    if (parse_step != c_last_parse_step){
        printf("Error parsing %s: File is incomplete.\n",infilename);
        return 0;
    }

    // Calculate the rest of the detected parameters:
    // max_table_rows
    // weight_bw
    // current_bw

    // Generating the top-level wrapper:
    //-----------------------------------
    FILE* outfile = fopen(outfilename, "w");
    if (f == NULL){
        printf("Error opening output file %s\n", outfilename);
        return 0;
    }
    fprintf(outfile,
        "module sn_network_top_wrapper\n"
        "(\n"
        " // Top clock and reset.\n"
        " input clk_in1_p,\n"
        " input clk_in1_n,\n"
        " input rst,\n"
        " // UART signals\n"
        " input rx_input,\n"
        " output tx_output\n"
        ");\n"
        "\n"
        "// Declarations\n"
        "//-------------------\n");
    fprintf(outfile,"localparam L_NEUR_MODEL_CFG = %d",rtl_params.l_neur_model_cfg);
    fprintf(outfile,"localparam L_NUM_NEURONS = %d",rtl_params.l_num_neurons);
    fprintf(outfile,"localparam L_NUM_INPUTS = %d",rtl_params.l_num_inputs);
    fprintf(outfile,"localparam L_NUM_OUTPUTS = %d",rtl_params.l_num_outputs);
    fprintf(outfile,"localparam L_TABLE_WEIGHT_BW = %d",rtl_params.l_table_weight_bw);
    fprintf(outfile,"localparam L_TABLE_WEIGHT_PRECISION = %d",rtl_params.l_table_weight_precision);
    fprintf(outfile,"localparam L_TABLE_MAX_NUM_ROWS = %d",rtl_params.l_table_max_num_rows);
    fprintf(outfile,"localparam L_TABLE_WEIGHT_BW = %d",rtl_params.l_table_weight_bw);
    fprintf(outfile,"localparam L_TABLE_WEIGHT_BW = %d",rtl_params.l_table_weight_bw);
    fprintf(outfile,"localparam L_TABLE_WEIGHT_BW = %d",rtl_params.l_table_weight_bw);
    fprintf(outfile,"localparam L_TABLE_WEIGHT_BW = %d",rtl_params.l_table_weight_bw);

 }