/* gen_wrapper.c:
 *      Called to generate a top-level RTL wrapper configuring custom
 *      spiking neural network hardware.
 *      The configuration is specified through an network configuration input file
 *      called as the only argument, whose format is standardized and generated
 *      using a MATLAB script.
 *
 * Created by Grant Tippett on March 9th, 2023.
 */


#define _CRT_SECURE_NO_DEPRECATE
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <inttypes.h>
#include <sys/types.h>
#include <stdbool.h>
#include <math.h>
#include <string.h>

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
typedef struct Weight Weight;
struct Weight {
    int assoc_neuron;
    int value;
    Weight* next_weight;
};
struct Neuron {
    int idx;
    char id[30];
    int num_weights;
    int const_current;
    Weight* first_weight;
};

// Functions:
//============
int assignParams(struct HLParams* params, int param_arr[]) {
    struct HLParams params_cpy;
    params_cpy.l_num_neurons = param_arr[0];
    params_cpy.l_num_inputs = param_arr[1];
    params_cpy.l_num_outputs = param_arr[2];
    params_cpy.l_max_num_periods = param_arr[3];
    params_cpy.l_dflt_cntr_val = param_arr[4];
    params_cpy.l_neur_model_precision = param_arr[5];
    params_cpy.l_table_weight_precision = param_arr[6];
    params_cpy.l_table_weight_bw = 9;
    params_cpy.l_table_max_num_rows = 0;
    params_cpy.l_table_dflt_num_rows = 0;
    params_cpy.l_neur_current_bw = 0;
    params_cpy.l_neur_step_cntr_bw = 0;
    params_cpy.l_uart_clks_per_bit = 87;
    params_cpy.l_uart_bits_per_pkt = 10;
    params_cpy.l_prot_watchdog_time = params_cpy.l_uart_clks_per_bit * params_cpy.l_uart_bits_per_pkt * 1000000;
    params_cpy.l_neur_model_cfg = 0; //0 for izh, 1 for i&f
    params_cpy.l_neur_izh_high_prec_en = 0;
    *params = params_cpy;
    return 0;
}
int findNeur(struct Neuron neur_arr[], int num_neurons, int dest_idx) {
    // Search the list for the destination neuron and return the index. If it can't be found, return -1.
    for (int i = 0; i < num_neurons; i++) if (neur_arr[i].idx == dest_idx) return i;
    return -1;
}
void printNeur(struct Neuron neur_arr[], int num_neurons, int idx, bool print_weights) {
    Weight* cur_weight;
    int i = findNeur(neur_arr, num_neurons, idx);
    printf("%s: id=%d", neur_arr[i].id, neur_arr[i].idx);
    if (print_weights) {
        printf("\t\nConstant Current: %d\n", neur_arr[i].const_current);
        cur_weight = neur_arr[i].first_weight;
        printf("\tWeights: %d\n", neur_arr[i].num_weights);
        while (cur_weight != nullptr) {
            printf("\t\tValue: %d, Source: %s (idx=%d)\n", cur_weight->value, neur_arr[findNeur(neur_arr, num_neurons, cur_weight->assoc_neuron)].id, neur_arr[i].idx);
            cur_weight = cur_weight->next_weight;
        }
    }
    return;
}
void printNetwork(struct Neuron neur_arr[], int num_neurons, bool print_weights) {
    printf("\nIdentified Network Stucture:\n");
    for (int i = 0; i < num_neurons; i++) {
        printNeur(neur_arr, num_neurons, i, print_weights);
    }
    return;
}
void addWeight(struct Neuron* neur, int src_idx, double value, int precision) {
    if (src_idx == 0) {
        // Not a weight, but a constant current.
        neur->const_current = (int)(value * pow(2, (double)precision));
    }
    else {
        // Normal weight.
        Weight* new_weight = (Weight*)malloc(sizeof(Weight)); 
        new_weight->assoc_neuron = src_idx;
        new_weight->value = (int)(value * pow(2, (double)precision)); // Convert it to an int with the specified fixed point precision.
        new_weight->next_weight = nullptr;
        neur->num_weights++;

        // Find the last weight in the neuron's weight list.
        if (neur->first_weight == nullptr){
            neur->first_weight = new_weight;
        } else {
            Weight* current = neur->first_weight;
            while (current->next_weight != nullptr) current = current->next_weight;
            current->next_weight = new_weight;
        }
    }
    return;
}
void calcRemParams(struct Neuron neur_arr[], struct HLParams* params) {
    int max_rows = 0;
    int max_weight = 0;
    int spec_max_weight;
    int max_const_current = 0;
    int spec_max_const_current;
    int wc_current = 0; // This calculation will not produce the actual worst case because it uses sum of absolute weight/current values.
    int spec_wc_current;
    struct Neuron cur_neuron;
    struct Weight* cur_weight;

    for (int i = 0; i < params->l_num_neurons; i++) {
        cur_neuron = neur_arr[i];
        // Update max const current.
        spec_max_const_current = abs(cur_neuron.const_current);
        if (spec_max_const_current > max_const_current) max_const_current = spec_max_const_current;
        spec_wc_current = spec_max_const_current;
        // Update the max num weights.
        if (cur_neuron.num_weights > max_rows) max_rows = cur_neuron.num_weights;
        // Update the maximum weight value and worst case current.
        cur_weight = cur_neuron.first_weight;
        while (cur_weight != nullptr) {
            spec_max_weight = abs(cur_weight->value);
            if (spec_max_weight > max_weight) max_weight = spec_max_weight;
            spec_wc_current += spec_max_weight;
            cur_weight = cur_weight->next_weight;
        }
        // Update worst-case current.
        if (spec_wc_current > wc_current) wc_current = spec_wc_current;
    }
    // Update params:
    params->l_table_max_num_rows = max_rows;
    params->l_table_dflt_num_rows = 0;
    params->l_table_weight_bw = (int)ceil(log2(max_weight));
    params->l_neur_current_bw = (int)ceil(log2(wc_current));
    return;
}
void printRTLParams(struct HLParams params) {
    printf("Final Hardware Model Parameters:\n--------------------------------\n");
    printf("\t%s\t\t = %d\n", "L_NUM_NEURONS", params.l_num_neurons);
    printf("\t%s\t\t = %d\n", "L_NUM_INPUTS", params.l_num_inputs);
    printf("\t%s\t\t = %d\n", "L_NUM_OUTPUTS", params.l_num_outputs);
    printf("\t%s\t = %d\n", "L_MAX_NUM_PERIODS", params.l_max_num_periods);
    printf("\t%s\t\t = %d\n", "L_DFLT_CNTR_VAL", params.l_dflt_cntr_val);
    printf("\t%s\t = %d\n", "L_NEUR_MODEL_PRECISION", params.l_neur_model_precision);
    printf("\t%s = %d\n", "L_TABLE_WEIGHT_PRECISION", params.l_table_weight_precision);
    printf("\t%s\t = %d\n", "L_TABLE_WEIGHT_BW", params.l_table_weight_bw);
    printf("\t%s\t = %d\n", "L_TABLE_MAX_NUM_ROWS", params.l_table_max_num_rows);
    printf("\t%s\t = %d\n", "L_TABLE_DFLT_NUM_ROWS", params.l_table_dflt_num_rows);
    printf("\t%s\t = %d\n", "L_NEUR_CURRENT_BW", params.l_neur_current_bw);
    printf("\t%s\t = %d\n", "L_NEUR_STEP_CNTR_BW", params.l_neur_step_cntr_bw);
    printf("\t%s\t = %d\n", "L_UART_CLKS_PER_BIT", params.l_uart_clks_per_bit);
    printf("\t%s\t = %d\n", "L_UART_BITS_PER_PKT", params.l_uart_bits_per_pkt);
    printf("\t%s\t = %d\n", "L_PROT_WATCHDOG_TIME", params.l_prot_watchdog_time);
    printf("\t%s\t = %d\n", "L_NEUR_MODEL_CFG", params.l_neur_model_cfg);
    printf("\t%s\t = %d\n", "L_NEUR_IZH_HIGH_PREC_EN", params.l_neur_izh_high_prec_en);
    return;
}
void printTableContents(FILE* outfile, struct Neuron neur_arr[], struct HLParams params) {
    fprintf(outfile, "\tassign cfg_table_contents = {\n");
    int idx = 0; 
    struct Weight* cur_w;
    for (int i = params.l_num_neurons; i > params.l_num_inputs; i--) {
        idx = findNeur(neur_arr, params.l_num_neurons, i);
        fprintf(outfile, "\t\t//N%d (%s)\n", neur_arr[idx].idx, neur_arr[idx].id);
        if (neur_arr[idx].first_weight == nullptr) fprintf(outfile, "\t\tL_CTC_PER_NEUR_BW'({'0");
        else {
            cur_w = neur_arr[idx].first_weight;
            fprintf(outfile, "\t\tL_CTC_PER_NEUR_BW'({\n");
            while (cur_w != nullptr) {
                fprintf(outfile, "\t\t\tL_TABLE_IDX_BW'(%d),L_TABLE_WEIGHT_BW'(%d)", cur_w->assoc_neuron, cur_w->value);
                cur_w = cur_w->next_weight;
                if (cur_w != nullptr) fprintf(outfile, ",\n");
            }
        }
        if (i > params.l_num_inputs+1) fprintf(outfile, "}),\n");
        else fprintf(outfile, "})};\n\n");
    }
    return;
}
bool checkNetwork(struct Neuron neur_arr[], struct HLParams params) {
    struct Neuron cur_neuron;
    struct Weight* cur_weight1;
    struct Weight* cur_weight2;
    int idx;
    char msg[100] = "\nChecking Network Structure:\n---------------------------\n";
    char warnings[10000] = "  CATEGORY \"WARNING\":\n";
    char errors[10000] = "  CATEGORY \"ERROR\":\n";
    char temp[300];
    bool w, e;
    w = false;
    e = false;
    
    // Check input neurons:
    for (int i = 1; i <= params.l_num_inputs; i++) {
        cur_neuron = neur_arr[findNeur(neur_arr, params.l_num_neurons, i)];
        if (abs(cur_neuron.const_current) > 0) {
            sprintf(temp, "   * WARNING: Input neuron \"%s\" (index %d) has a constant current value %d that will be ignored.\n\n", cur_neuron.id, cur_neuron.idx, (int)(cur_neuron.const_current / pow(2, (double)params.l_table_weight_precision)));
            strcat(warnings, temp);
            w = true;
        }
        if (cur_neuron.num_weights > 0) {
            sprintf(temp, "   * WARNING: Input neuron \"%s\" (index %d) has weights that will be ignored.\n\n", cur_neuron.id, cur_neuron.idx);
            strcat(warnings, temp);
            w = true;
        }
    }
    // Check hidden neurons:
    for (int i = params.l_num_inputs+1; i <= params.l_num_neurons-params.l_num_outputs; i++) {
        cur_neuron = neur_arr[findNeur(neur_arr, params.l_num_neurons, i)];
        if (cur_neuron.num_weights == 0) {
            if (cur_neuron.const_current == 0) {
                sprintf(temp, "   * WARNING: Hidden neuron \"%s\" (index %d) has no weights and no constant current.\n\t      Consider removing this neuron from the network as it consumes unnecessary resources.\n\n", cur_neuron.id, cur_neuron.idx);
                strcat(warnings, temp);
                w = true;
            }
        }
        else {
            cur_weight1 = cur_neuron.first_weight;
            bool exit_flag = false;
            while (cur_weight1 != nullptr) {
                cur_weight2 = cur_neuron.first_weight;
                while (cur_weight2 != nullptr && !exit_flag) {
                    if (cur_weight1 != cur_weight2 && cur_weight1->assoc_neuron == cur_weight2->assoc_neuron){
                        sprintf(temp, "   * ERROR: Hidden neuron \"%s\" (index %d) has two weights (value1=%d, value2=%d) for the same\n\t    source neuron \"%s\" (index %d). Group these before rerunning.\n\n", cur_neuron.id, cur_neuron.idx,(int)(cur_weight1->value / pow(2, (double)params.l_table_weight_precision)),(int)(cur_weight2->value / pow(2, (double)params.l_table_weight_precision)),neur_arr[findNeur(neur_arr,params.l_num_neurons,cur_weight1->assoc_neuron)].id, cur_weight1->assoc_neuron);
                        strcat(errors, temp);
                        e = true;
                        exit_flag = true;
                        break;
                    }
                    cur_weight2 = cur_weight2->next_weight;
                }
                if (cur_weight1->assoc_neuron == cur_neuron.idx && (int)(cur_weight1->value / pow(2, (double)params.l_table_weight_precision)) > 20) {
                    sprintf(temp, "   * WARNING: Hidden neuron \"%s\" (index %d) has a large weight (value=%d) associated with itself.\n\t      This may cause instability and deviation from the MATLAB model when implemented in hardware. \n\n", cur_neuron.id, cur_neuron.idx, (int)(cur_weight1->value / pow(2, (double)params.l_table_weight_precision)));
                    strcat(warnings, temp);
                    w = true;
                }
                cur_weight1 = cur_weight1->next_weight;
            }
        }
    }
    // Check output neurons:
    for (int i = params.l_num_neurons-params.l_num_outputs+1; i <= params.l_num_neurons; i++) {
        cur_neuron = neur_arr[findNeur(neur_arr, params.l_num_neurons, i)];
        if (cur_neuron.num_weights == 0) {
            sprintf(temp, "   * WARNING: Output neuron \"%s\" (index %d) has no weights. Consider removing\n\t    this neuron from the network.\n\n", cur_neuron.id, cur_neuron.idx);
            strcat(warnings, temp);
            w = true;
        }
        else {
            cur_weight1 = cur_neuron.first_weight;
            bool exit_flag = false;
            while (cur_weight1 != nullptr) {
                cur_weight2 = cur_neuron.first_weight;
                while (cur_weight2 != nullptr && !exit_flag) {
                    if (cur_weight1 != cur_weight2 && cur_weight1->assoc_neuron == cur_weight2->assoc_neuron) {
                        sprintf(temp, "   * ERROR: Output neuron \"%s\" (index %d) has two weights (value1=%d, value2=%d)\n\t    for the same source neuron \"%s\" (index %d). Group these before rerunning.\n\n", cur_neuron.id, cur_neuron.idx, (int)(cur_weight1->value / pow(2, (double)params.l_neur_model_precision)), (int)(cur_weight2->value / pow(2, (double)params.l_neur_model_precision)), neur_arr[findNeur(neur_arr, params.l_num_neurons, cur_weight1->assoc_neuron)].id, cur_weight1->assoc_neuron);
                        strcat(errors, temp);
                        e = true;
                        exit_flag = true;
                        break;
                    }
                    cur_weight2 = cur_weight2->next_weight;
                }
                cur_weight1 = cur_weight1->next_weight;
            }
        }
        if ((int)(cur_neuron.const_current / pow(2, (double)params.l_table_weight_precision)) > 20) {
            sprintf(temp, "   * WARNING: Output neuron \"%s\" (index %d) has a large constant current of value %d.\n\t      This may cause the output counter value to saturate with larger number of execution periods.\n\n", cur_neuron.id, cur_neuron.idx, (int)(cur_neuron.const_current / pow(2, (double)params.l_table_weight_precision)));
            strcat(warnings, temp);
            w = true;
        }
    }
    // Check for floating neurons:
    bool* neur_is_used = (bool*)calloc(params.l_num_neurons, sizeof(bool));
    for (int i = 0; i < params.l_num_neurons; i++) {
        cur_neuron = neur_arr[i];
        cur_weight1 = cur_neuron.first_weight;
        while (cur_weight1 != nullptr) {
            for (int j = 1; j <= params.l_num_neurons; j++) if (cur_weight1->assoc_neuron == j) neur_is_used[j - 1] = true;
            cur_weight1 = cur_weight1->next_weight;
        }
    }
    for (int i = 0; i < params.l_num_neurons; i++) {
        if (neur_is_used[i] == false && i<params.l_num_neurons-params.l_num_outputs) {
            sprintf(temp, "   * WARNING: Neuron \"%s\" (index %d) has no weights associated with it in any other neurons.\n\t      Consider removing it to decrease hardware area.\n\n", neur_arr[findNeur(neur_arr,params.l_num_neurons,i+1)].id, i+1);
            strcat(warnings, temp);
            w = true;
        }
        else if (neur_is_used[i] == true && i >= params.l_num_neurons - params.l_num_outputs) {
            sprintf(temp, "   * ERROR: Output neuron \"%s\" (index %d) has weights associated with it in\n\t    other neurons. This must be removed as back-propagation of output neurons is not supported.\n\n", neur_arr[findNeur(neur_arr, params.l_num_neurons, i + 1)].id, i + 1);
            strcat(errors, temp);
            e = true;
        }
    }
    free(neur_is_used);
    // Check parameters:
    if (params.l_neur_model_precision % 2 == 1 || params.l_neur_model_precision<0) {
        sprintf(temp, "   * ERROR: Neuron model precision parameter value %d is allowed. It must be a positive multiple of 2.\n\n", params.l_neur_model_precision);
        strcat(errors, temp);
        e = true;
    }
    if (params.l_table_weight_precision<0) {
        sprintf(temp, "   * ERROR: Weight precision parameter value %d is allowed. It must be a positive multiple of 2.\n\n", params.l_table_weight_precision);
        strcat(errors, temp);
        e = true;
    }
    if (params.l_table_weight_precision > params.l_neur_model_precision) {
        sprintf(temp, "   * ERROR: Weight precision parameter value %d is more than the neuron model precision value %d.\n\n", params.l_table_weight_precision, params.l_neur_model_precision);
        strcat(errors, temp);
        e = true;
    }
    if (params.l_max_num_periods > 65535) {
        sprintf(temp, "   * ERROR: Maximum periods parameter value %d is more than the maximum value of 65535.\n\n", params.l_max_num_periods);
        strcat(errors, temp);
        e = true;
    }
    if (params.l_table_max_num_rows > 255) {
        sprintf(temp, "   * ERROR: The maximum number of weights for one or more neurons is %d\n\t    which is more than the maximum value of 255.\n\n", params.l_max_num_periods);
        strcat(errors, temp);
        e = true;
    }
    if (params.l_neur_izh_high_prec_en&& params.l_neur_model_cfg == 0 && params.l_neur_model_precision>8) {
        sprintf(temp, "   * WARNING: High Izhikevich neuron model precision is configured and the model precision is %d.\n\t      This will not utilize DSP multipliers, impacting timing.\n\n", params.l_max_num_periods);
        strcat(warnings, temp);
        w = true;
    }
    if (!params.l_neur_izh_high_prec_en && params.l_neur_model_precision > 10) {
        sprintf(temp, "   * ERROR: Specified neuron model precision value %d is more than max value 10. Enable the high\n\t    precision parameter if a precision above 10 bits is desired.\n\n", params.l_neur_model_precision);
        strcat(errors, temp);
        e = true;
    }
    printf(msg);
    if (e) printf("%s",errors);
    if (w) printf(warnings);
    if (!w && !e) {
        printf("No errors or warnings identified.\n\n");
        printf("\t  **\t **\n");
        printf("\t  **\t **\n");
        printf("\t  **\t **\n\n");
        printf("\t*\t    *\n");
        printf("\t**\t   **\n");
        printf("\t ***\t ***\n");
        printf("\t   *******\n\n");
    }
    return !e;
}
void freeNeuronWeights(struct Neuron neur_arr[], int len) {
    for (int i = 0; i < len; i++) {
        if (neur_arr[i].first_weight != nullptr) {
            Weight* current = neur_arr[i].first_weight;
            Weight* next;
            while (current != NULL) {
                next = current->next_weight; // save the pointer to the next node
                free(current); // free the memory for the current node
                current = next; // move to the next node
            }
        }
    }
}
bool strcmpl(const char* str1, const char* str2, int limit) {
    for (int i = 0; i < limit; i++) {
        if (*(str1 + i) == '\0' && *(str2 + i) == '\0') break;
        if (*(str1 + i) != *(str2 + i)) return false;
    }
    return true;
}
bool strstrip(char* str, const char delimiter) {
    for (int i = 0; str; i++) {
        if (*(str + i) == '\0') break;
        else if (*(str + i) == delimiter) {
            *(str + i) = '\0'; return true;
        }
    }
    return false;
}

// Main Function:
//================
int main(int argc, char* argv[]) {
    // Error checking:
    //-----------------
    /*if (argc!=2){
        printf("Error in gen_wrapper.c: No network configuration file specified.\n");
        return 0;
    }*/
    const bool dbg = false;

    if (dbg) printf("Attempting to open input file\n");
    char infilename[] = "./net_cfg_template3.txt";//argv[1];
    FILE* infile;
    errno_t err = fopen_s(&infile, infilename, "r+t");
    if (err != 0) {
        printf("Error in gen_wrapper.c: Can't open %s\n", infilename);
        return 0;
    }
    if (dbg) printf("Opened %s\n", infilename);

    // Variable Declarations:
    //------------------------
    // High level params:
    const int c_num_file_params = 8;
    int file_params[c_num_file_params];
    struct HLParams rtl_params;
    // TODO l_table_num_rows_array, l_neur_const_current_array, l_neur_cntr_val_array

    // Loop vars:
    char line[300];
    int line_cnt = 0;
    int parse_step = 0; // current step in the process of parsing the input file.
    const int c_last_parse_step = 3;
    int param_cnt = 0; // Used in step 1 to identify the parameter.
    char* token; // Used in parsing LUT and weights in steps 2/3.
    int cur_dest_idx = 0;
    int cur_src_idx = 0;
    double cur_weight = 0;
    // Neuron list:
    Neuron* neurons = nullptr;
    int neur_cnt = 0;

    // Output file:
    // Module name
    char outfilename_short[] = "sn_network_top_wrapper_generated";
    // File name
    char outfilename[50];
    strcpy(outfilename, outfilename_short);
    strcat(outfilename, ".sv");
    if (dbg) printf("Starting to parse %s: ", infilename);
    // Parsing the input file:
    //-------------------------
    do {
        // Get a line from the file:
        if (fgets(line, sizeof(line), infile) == NULL) break;
        line_cnt++;

        // Conditionally do something with the line:
        switch (parse_step) {
        case 0: // Search lines until an identifier is found that starts a parse step:
            if (strcmpl(line, "High-Level", 10)) {
                parse_step = 1;
                if (dbg) printf("Step 1: Starting to parse high-level params.\n=========================================\n");
                else printf("Parsing Parameters: ");
            }
            else if (strcmpl(line, "Neuron ID/Address", 10)) {
                parse_step = 2;
                if (dbg) printf("Step 2: Starting to parse neuron ID look-up table.\n=========================================\n");
                else printf("Parsing Neuron ID LUT: ");
            }
            else if (strcmpl(line, "Sources", 7)) {
                parse_step = 3;
                if (dbg) printf("Step 3: Starting to parse weights.\n=========================================\n");
                else printf("Parsing Weights: ");
            }
            break;

        case 1: // Collect all high-level params:
            if (dbg) printf("Step 1: parsing line %d\n", line_cnt);
            // Check if we've reached the end of the params section (empty line).
            if (*line == '\n') {
                // Setup for next step: populate rtl_params struct and create array of neuron.
                assignParams(&rtl_params, file_params);
                neurons = (Neuron*)malloc(rtl_params.l_num_neurons * sizeof(Neuron));
                parse_step = 0;
                if (dbg) printf("Finished Step 1.\n");
                else printf(" Done.\n");
                continue;
            }
            if (strstrip(line, ' ') == false) {
                printf("Error parsing high level params at %s: unexpected content on line %d.\n", infilename,line_cnt);
                fclose(infile);
                return 0;
            }
            file_params[param_cnt] = atoi(line);
            param_cnt++;
            printf(".");
            break;

        case 2: // Create a lookup table for neuron IDs and indices:
            if (dbg) printf("Step 2: parsing line %d\n", line_cnt);
            // Check if we've reached the end of the LUT section (empty line).
            if (*line == '\n') {
                parse_step = 0;
                if (dbg) printf("Finished Step 2.\n");
                else printf(" Done.\n");
                if (dbg) printNetwork(neurons, rtl_params.l_num_neurons, false);
                continue;
            }
            // Error check: ensure that the length of the LUT is the same as the number of neurons.
            if (neur_cnt == rtl_params.l_num_neurons) {
                printf("Error parsing lookup table in %s:%d: Neuron ID Table is longer than the specified number of neurons (%d). Fix this before rerunning.",infilename,line_cnt,rtl_params.l_num_neurons);
                fclose(infile);
                return 0;
            }
            token = strtok(line, " ");
            if (token == NULL) {
                printf("Error parsing lookup table in %s: not enough tokens on line %d.\n", infilename, line_cnt);
                fclose(infile);
                return 0;
            }
            neurons[neur_cnt].idx = atoi(token);
            token = strtok(NULL, "\n");
            if (token == NULL) {
                printf("Error parsing lookup table in %s: not enough tokens on line %d.\n", infilename, line_cnt);
                fclose(infile);
                return 0;
            }
            strcpy(neurons[neur_cnt].id, token);
            neurons[neur_cnt].first_weight = nullptr;
            neurons[neur_cnt].num_weights = 0;
            neurons[neur_cnt].const_current = 0;
            neur_cnt++;
            printf(".");
            break;

        case 3: // Populate the netlist datastructure:
            if (dbg) printf("Step 3: parsing line %d\n", line_cnt);
            token = strtok(line, " ");
            if (token == NULL) {
                if (dbg) printf("Error parsing weight list in %s: not enough tokens on line %d.\n", infilename, line_cnt);
                fclose(infile);
                return 0;
            }
            cur_dest_idx = atoi(token);
            token = strtok(NULL, " ");
            if (token == NULL) {
                printf("Error parsing weight list in %s: not enough tokens on line %d.\n", infilename, line_cnt);
                fclose(infile);
                return 0;
            }
            // Check if the source is "Constant", indicating that this is a constant weight.
            if (strcmpl(token, "Constant", 8) || strcmpl(token, "constant", 8)) cur_src_idx = 0;
            else cur_src_idx = atoi(token);
            token = strtok(NULL, "\n");
            if (token == NULL) {
                printf("Error parsing weight list in %s: not enough tokens on line %d.\n", infilename, line_cnt);
                fclose(infile);
                return 0;
            }
            cur_weight = atof(token);
            // Now find the dest neuron and add the weight.
            cur_dest_idx = findNeur(neurons, rtl_params.l_num_neurons, cur_dest_idx);
            if (cur_dest_idx == -1) {
                printf("Error parsing weight list in %s: Destination neuron on line %d does not exist in the lookup table.\n", infilename, line_cnt);
                fclose(infile);
                return 0;
            }
            addWeight(&neurons[cur_dest_idx], cur_src_idx, cur_weight, rtl_params.l_table_weight_precision);
            printf(".");
            break;
        }
    } while (!feof(infile));
    // Error check:
    if (parse_step != c_last_parse_step) {
        printf("Error parsing %s: File is incomplete.\n", infilename);
        return 0;
    }
    if (dbg) printf("Finished Step 3.\n");
    else printf(" Done.\n\n");
    if (dbg) printNetwork(neurons, rtl_params.l_num_neurons, true);

    fclose(infile);

    // Calculate the remaining of RTL parameters:
    //--------------------------------------------
    // L_TABLE_NUM_ROWS_ARRAY can be found by looping through neurons.
    // L_NEUR_CONST_CURRENT_ARRAY can be done by looping through neurons.
    // L_NEUR_CNTR_VAL_ARRAY for now just set to the default value.
    // Calculate max num rows by iterating through all the neurons and finding the max
    if (dbg) printf("Calculating remaining RTL parameters and finishing population of the Network datastructure.\n");
    calcRemParams(neurons, &rtl_params);
    printRTLParams(rtl_params);

    // Do some error checks:
    //----------------------
    // - Can't have two weights sourced from the same neuron. Loop through each neuron and check that no two weights have the same index.
    // - Input neurons can't have any weights.
    // - Input neurons can't have constant currents (they are always variable).
    // + many more
    if (checkNetwork(neurons, rtl_params) == false) {
        printf("\nErrors have been identified in the network configuration file %s.\nSkipping RTL generation.\n", infilename);
        freeNeuronWeights(neurons, rtl_params.l_num_neurons);
        free(neurons);
        return 0;
    }

    // Generating the top-level wrapper:
    //-----------------------------------
    if (dbg) printf("Starting generation of RTL wrapper.\n");
    FILE* outfile = fopen(outfilename, "w");
    if (outfile == NULL) {
        printf("Error opening output file %s\n", outfilename);
        freeNeuronWeights(neurons, rtl_params.l_num_neurons);
        free(neurons);
        return 0;
    }
    fprintf(outfile, "/* %s:\n *\tGenerated RTL wrapper for sn_network_top module.\n"
        " *\tThe configured top-level parameters are calculated for a specific network configuration.\n"
        " *\tThe weights, constant currents, and step lengths for all neurons are configured automatically.\n"
        " *\tDO NOT MODIFY.\n */ \n", outfilename_short);
    fprintf(outfile, "module %s\n", outfilename_short);
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
        "\t// Declarations:\n"
        "\t//---------------\n");
    fprintf(outfile, "\tlocalparam L_NEUR_MODEL_CFG = %d;\n", rtl_params.l_neur_model_cfg);
    fprintf(outfile, "\tlocalparam L_NUM_NEURONS = %d;\n", rtl_params.l_num_neurons);
    fprintf(outfile, "\tlocalparam L_NUM_INPUTS = %d;\n", rtl_params.l_num_inputs);
    fprintf(outfile, "\tlocalparam L_NUM_OUTPUTS = %d;\n", rtl_params.l_num_outputs);
    fprintf(outfile, "\tlocalparam L_TABLE_WEIGHT_BW = %d;\n", rtl_params.l_table_weight_bw);
    fprintf(outfile, "\tlocalparam L_TABLE_WEIGHT_PRECISION = %d;\n", rtl_params.l_table_weight_precision);
    fprintf(outfile, "\tlocalparam L_TABLE_MAX_NUM_ROWS = %d;\n", rtl_params.l_table_max_num_rows);
    fprintf(outfile, "\tlocalparam L_TABLE_DFLT_NUM_ROWS = %d;\n", rtl_params.l_table_dflt_num_rows);
    fprintf(outfile, "\tlocalparam L_NEUR_CURRENT_BW = %d;\n", rtl_params.l_neur_current_bw);
    fprintf(outfile, "\tlocalparam L_NEUR_MODEL_PRECISION = %d;\n", rtl_params.l_neur_model_precision);
    fprintf(outfile, "\tlocalparam L_NEUR_HIGH_PREC_EN = %d;\n", rtl_params.l_neur_izh_high_prec_en);
    fprintf(outfile, "\tlocalparam L_DFLT_CNTR_VAL = %d;\n", rtl_params.l_dflt_cntr_val);
    fprintf(outfile, "\tlocalparam L_NEUR_STEP_CNTR_BW = %d;\n", rtl_params.l_neur_step_cntr_bw);
    fprintf(outfile, "\tlocalparam L_MAX_NUM_PERIODS = %d;\n", rtl_params.l_max_num_periods);
    fprintf(outfile, "\tlocalparam L_TABLE_IDX_BW = $clog2(L_NUM_NEURONS-L_NUM_OUTPUTS+1);\n");
    fprintf(outfile, "\n\tlocalparam L_UART_CLKS_PER_BIT = %d;\n", rtl_params.l_uart_clks_per_bit);
    fprintf(outfile, "\tlocalparam L_UART_BITS_PER_PKT = %d;\n", rtl_params.l_uart_bits_per_pkt);
    fprintf(outfile, "\tlocalparam L_PROT_WATCHDOG_TIME = %d;\n", rtl_params.l_prot_watchdog_time);
    //L_TABLE_NUM_ROWS_ARRAY
    fprintf(outfile, "\tlocalparam L_TABLE_NUM_ROWS_ARRAY [L_NUM_NEURONS-L_NUM_INPUTS:1] = {");
    for (int i = rtl_params.l_num_neurons; i > rtl_params.l_num_inputs; i--) {
        fprintf(outfile, "%d", neurons[findNeur(neurons, rtl_params.l_num_neurons, i)].num_weights);
        if (i != rtl_params.l_num_inputs+1) fprintf(outfile, ",");
    }
    fprintf(outfile, "};\n");
    //L_NEUR_CONST_CURRENT_ARRAY
    fprintf(outfile, "\tlocalparam L_NEUR_CONST_CURRENT_ARRAY [L_NUM_NEURONS-L_NUM_INPUTS:1] = {");
    for (int i = rtl_params.l_num_neurons; i > rtl_params.l_num_inputs; i--) {
        fprintf(outfile, "%d", neurons[findNeur(neurons, rtl_params.l_num_neurons, i)].const_current);
        if (i != rtl_params.l_num_inputs+1) fprintf(outfile, ",");
    }
    fprintf(outfile, "};\n");
    //L_NEUR_CNTR_VAL_ARRAY
    fprintf(outfile, "\tlocalparam L_NEUR_CNTR_VAL_ARRAY [L_NUM_NEURONS:1] = {");
    for (int i = rtl_params.l_num_neurons; i > 0; i--) {
        fprintf(outfile, "%d", rtl_params.l_dflt_cntr_val); // FIXME if at some point all neurons have differing step lengths.
        if (i != 1) fprintf(outfile, ",");
    }
    fprintf(outfile, "};\n\n");

    // Weight contents:
    fprintf(outfile, "\tlocalparam L_CTC_PER_NEUR_BW = L_TABLE_MAX_NUM_ROWS*(L_TABLE_WEIGHT_BW+L_TABLE_IDX_BW);\n");
    fprintf(outfile, "\tlogic [L_NUM_NEURONS-L_NUM_INPUTS:1] [L_TABLE_MAX_NUM_ROWS-1:0] [L_TABLE_WEIGHT_BW+L_TABLE_IDX_BW-1:0] cfg_table_contents;\n\n");
    printTableContents(outfile, neurons, rtl_params);

    // network_top_cfg Instantiation:
    fprintf(outfile,"\t// Network Top Module Instance:\n");
    fprintf(outfile,"\t//------------------------------\n");
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
        "\t\t.P_CLK_GEN_EN(1))\n"
        "\tnetwork_i (\n"
        "\t\t.clk_in1_p(clk_in1_p),\n"
        "\t\t.clk_in1_n(clk_in1_n),\n"
        "\t\t.rst(rst),\n"
        "\t\t// UART Interface\n"
        "\t\t.rx_input(rx_input),\n"
        "\t\t.tx_output(tx_output),\n"
        "\t\t// CFG\n"
        "\t\t.cfg_table_contents(cfg_table_contents));\n");
    // End of the module:
    fprintf(outfile, "\nendmodule");
    fclose(outfile);
    if (dbg) printf("Finished generating RTL wrapper.\n");
    printf("\nGenerated RTL Wrapper: %s\n", outfilename);

    // Create Testbench file: TODO

    // Free the allocated memory for the weights in the neuron list and then the neurons themselves:
    freeNeuronWeights(neurons, rtl_params.l_num_neurons);
    free(neurons);
}