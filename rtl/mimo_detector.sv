module mimo_detector #(
    parameter INT_LENGTH_Z = 6,
    parameter FRAC_LENGTH_Z = 10,
    parameter INT_LENGTH_R = 4,
    parameter FRAC_LENGTH_R = 12,

    parameter WORD_LENGTH_IN = 16
) (
    input clk,
    input rst,
    input flagChannelorData,
    input [3*2*WORD_LENGTH_IN-1:0] InData,
    input i_valid,
    output o_valid,
    output [3*4-1:0] OutData
);
localparam int K_BEST_array [0:5] = {4,16,8,8,2,1};
localparam signed [2:0] symbols [0:3] = {3'd3, 3'd1, -3'd1, -3'd3}; // 16-QAM with RVD symbol set
localparam WORD_LENGTH = 20;
localparam WORD_LENGTH_R = WORD_LENGTH_IN;
localparam WORD_LENGTH_Z = WORD_LENGTH_IN + FRAC_LENGTH_R - FRAC_LENGTH_Z;


// 6x6 upper triangular R matrix
// R = [R1[1] R1[2] R1[3] R1[4] R1[5] R1[6];
//      0     R2[2] R2[3] R2[4] R2[5] R2[6];
//      0     0     R3[3] R3[4] R3[5] R3[6];
//      0     0     0     R4[4] R4[5] R4[6];
//      0     0     0     0     R5[5] R5[6];
//      0     0     0     0     0     R6[6]];
logic signed [WORD_LENGTH_R-1:0] R_matrix_w [0:(1+2+3+4+5+6)-1], R_matrix_r [0:(1+2+3+4+5+6)-1];
logic signed [WORD_LENGTH_R-1:0] R1 [1:6];
logic signed [WORD_LENGTH_R-1:0] R2 [2:6];
logic signed [WORD_LENGTH_R-1:0] R3 [3:6];
logic signed [WORD_LENGTH_R-1:0] R4 [4:6];
logic signed [WORD_LENGTH_R-1:0] R5 [5:6];
logic signed [WORD_LENGTH_R-1:0] R6 [6:6];
genvar g, h;
integer i;
generate
    for(g=1; g <= 6; g = g + 1) begin : r_matrix_assign_gen
        assign R1[g] = R_matrix_r[g - 1];
    end
    for(g=2; g <= 6; g = g + 1) begin : r_matrix_assign_gen2
        assign R2[g] = R_matrix_r[g + 4];
    end
    for(g=3; g <= 6 ; g = g + 1) begin : r_matrix_assign_gen3
        assign R3[g] = R_matrix_r[g + 8];
    end
    for(g=4; g <= 6; g = g + 1) begin : r_matrix_assign_gen4
        assign R4[g] = R_matrix_r[g + 11];
    end
    for(g=5; g <= 6; g = g + 1) begin : r_matrix_assign_gen5
        assign R5[g] = R_matrix_r[g + 13];
    end
    assign R6[6] = R_matrix_r[20];
endgenerate

logic signed [WORD_LENGTH_Z-1:0] z_in_w [0:5], z_in_r [0:5];
logic [WORD_LENGTH_Z-1:0] z [0:5];


// state machine and counters
localparam LOAD_MATRIX = 1'b0;
localparam CALCULATE = 1'b1;
logic state_w, state_r;
logic [9:0] counter_w, counter_r;

// state machine logic
always @(*) begin
    state_w = state_r;
    counter_w = counter_r;
    case(state_r)
        LOAD_MATRIX: begin
            if(i_valid) begin
                counter_w = counter_r + 1;
                if(counter_r == 10'd3) begin
                    state_w = CALCULATE;
                    counter_w = 10'd0;
                end 
            end
        end
        CALCULATE: begin
            counter_w = counter_r + 1;
            state_w = CALCULATE;
        end
    endcase
end

// combinational logic
logic signed [WORD_LENGTH-1:0] PEDs_w [0:3], PEDs_r [0:3], PEDs [0:3];
logic signed [WORD_LENGTH-1:0] histories_w [0:3], histories_r [0:3], histories [0:3];
logic signed [2:0] path_indices_w [0:3][0:0], path_indices_r [0:3][0:0];
//pipeline registers for z values
logic signed [WORD_LENGTH_Z-1:0] z0_w [0:(K_BEST_array[3]+K_BEST_array[2]+3)], z0_r[0:(K_BEST_array[3]+K_BEST_array[2]+3)]; // 1 + K_BEST_LAYER3 + K_BEST_LAYER2 + K_BEST_LAYER1 stages pipeline for z0
logic signed [WORD_LENGTH_Z-1:0] z1_w [0:(K_BEST_array[2]+2)], z1_r[0:(K_BEST_array[2]+K_BEST_array[1]+2)]; // 1 + K_BEST_LAYER2 + K_BEST_LAYER1 stages pipeline for z1
logic signed [WORD_LENGTH_Z-1:0] z2_w [0:1], z2_r[0:1]; // 1 + K_BEST_LAYER1 stages pipeline for z2
logic signed [WORD_LENGTH_Z-1:0] z3_w, z3_r; // 1 stage pipeline for z3
logic signed [WORD_LENGTH_Z-1:0] z4_w, z4_r; // 1 stage pipeline for z4

// layer enable logic

logic layer_enable_w [0:5], layer_enable_r [0:5];
// output logic
logic o_valid_w, o_valid_r;
logic [3:0] output_symbols_w [0:2], output_symbols_r [0:2];
logic signed [2:0] final_path_indices [0:K_BEST_array[5]-1][0:5];
assign OutData = {output_symbols_r[0], output_symbols_r[1], output_symbols_r[2]};
assign o_valid = o_valid_r;

always @(*) begin
    // default assignments
    for(i = 0; i < (1+2+3+4+5+6); i = i + 1) begin
        R_matrix_w[i] = R_matrix_r[i];
    end
    for(i = 0; i < 6; i = i + 1) begin
        z_in_w[i] = z_in_r[i];
    end
    for(i = 0; i < 4; i = i + 1) begin
        PEDs_w[i] = PEDs_r[i];
        histories_w[i] = histories_r[i];
        path_indices_w[i][0] = path_indices_r[i][0];
    end
    // pipeline registers for z values
    for(i = 0; i <= (K_BEST_array[3]+K_BEST_array[2]+K_BEST_array[1]+3); i = i + 1) begin
        z0_w[i] = z0_r[i];
    end
    for(i = 0; i <= (K_BEST_array[2]+K_BEST_array[1]+2); i = i + 1) begin
        z1_w[i] = z1_r[i];
    end
    for(i = 0; i <= (K_BEST_array[1]+1); i = i + 1) begin
        z2_w[i] = z2_r[i];
    end
    z3_w = z3_r;
    // layer enable logic
    for(i = 0; i < 6; i = i + 1) begin
        layer_enable_w[i] = layer_enable_r[i];
    end
    // output registers
    for(i = 0; i < 3; i = i + 1) begin
        output_symbols_w[i] = output_symbols_r[i];
    end
    o_valid_w = 1'b0;
    case(state_r)
        LOAD_MATRIX: begin
            if(i_valid) begin
                for(int i = 0; i < 6; i = i + 1) begin
                    // load should be load 16 bit instead 20.
                    R_matrix_w[6*counter_r + i] = InData[WORD_LENGTH_IN*(6-i)-1 -: WORD_LENGTH_IN];
                end
            end
        end
        CALCULATE: begin
            if(counter_r >= (1 + K_BEST_array[2] + K_BEST_array[3] + K_BEST_array[4] + K_BEST_array[5] + 1)) begin // here modify
                o_valid_w = 1'b1;
            end else begin
                o_valid_w = 1'b0;
            end
            if(i_valid) begin
                for(int i = 0; i < 6; i = i + 1) begin
                    z_in_w[i] = InData[WORD_LENGTH_IN*(6-i)-1 -: WORD_LENGTH_IN] << (FRAC_LENGTH_R - FRAC_LENGTH_Z);
                end
                layer_enable_w[0] = 1'b1;
            end
            if (layer_enable_r[0] && counter_r >= K_BEST_array[1]+1) begin
                layer_enable_w[1] = 1'b1;
            end
            if (layer_enable_r[1] && counter_r >= K_BEST_array[2]+K_BEST_array[1]+1) begin
                layer_enable_w[2] = 1'b1;
            end
            if (layer_enable_r[2] && counter_r >= K_BEST_array[3]+K_BEST_array[2]+K_BEST_array[1]+1) begin
                layer_enable_w[3] = 1'b1;
            end
            if (layer_enable_r[3] && counter_r >= K_BEST_array[4]+K_BEST_array[3]+K_BEST_array[2]+K_BEST_array[1]+1) begin
                layer_enable_w[4] = 1'b1;
            end
            if (layer_enable_r[4] && counter_r >= K_BEST_array[5]+K_BEST_array[4]+K_BEST_array[3]+K_BEST_array[2]+K_BEST_array[1]+1) begin
                layer_enable_w[5] = 1'b1;
            end
            // initial layer: 4 MCU and 4 HCU calculations
            if(counter_r >= 10'd0) begin
                for(int i = 0; i < 4; i = i + 1) begin
                    PEDs_w[i] = PEDs[i];
                    histories_w[i] = histories[i]; // initial history is z6
                    for(int j = 0; j < 1; j = j + 1) begin
                        path_indices_w[i][j] = symbols[i];
                    end
                end
            end
            // pipeline z values
            for( i = 0; i < (K_BEST_array[3]+K_BEST_array[2]+K_BEST_array[1]+3); i = i + 1) begin
                z0_w[i+1] = z0_r[i];
            end
            z0_w[0] = z_in_r[0];
            for( i = 0; i < (K_BEST_array[2]+K_BEST_array[1]+2); i = i + 1) begin
                z1_w[i+1] = z1_r[i];
            end
            z1_w[0] = z_in_r[1];
            for( i = 0; i < (K_BEST_array[1]+1); i = i + 1) begin
                z2_w[i+1] = z2_r[i];
            end
            z2_w[0] = z_in_r[2];
            z3_w = z_in_r[3];
            z4_w = z_in_r[4];
            // map back to 16 QAM symbols for output
            // 16-QAM constelation mapping to binary:
            // 1101 | 1001 | 0001 | 0101
            // 1101 | 1000 | 0000 | 0100
            // 1110 | 1010 | 0010 | 0110
            // 1111 | 1011 | 0011 | 0111
            // 0000 -> 1+1j
            // 0001 -> 1+3j
            // 0010 -> 1-1j
            // 0011 -> 1-3j
            // 0100 -> 3+1j
            // 0101 -> 3+3j
            // 0110 -> 3-1j 
            // 0111 -> 3-3j
            // 1000 -> -1+1j
            // 1001 -> -1+3j
            // 1010 -> -1-1j
            // 1011 -> -1-3j
            // 1100 -> -3+1j
            // 1101 -> -3+3j
            // 1110 -> -3-1j
            // 1111 -> -3-3j
            case(final_path_indices[0][0]) // [Real(1), Real(2), Real(3), Imag(1), Imag(2), Imag(3)]
                3'd3: begin
                    case(final_path_indices[0][3])
                        3'd3: output_symbols_w[0] = 4'b0101; // 3+3j
                        3'd1: output_symbols_w[0] = 4'b0100; // 3+1j
                        -3'd1: output_symbols_w[0] = 4'b0110; // 3-1j
                        -3'd3: output_symbols_w[0] = 4'b0111; // 3-3j
                    endcase
                end
                3'd1: begin
                    case(final_path_indices[0][3])
                        3'd3: output_symbols_w[0] = 4'b0001; // 1+3j
                        3'd1: output_symbols_w[0] = 4'b0000; // 1+1j
                        -3'd1: output_symbols_w[0] = 4'b0010; // 1-1j
                        -3'd3: output_symbols_w[0] = 4'b0011; // 1-3j
                    endcase
                end
                -3'd1: begin
                    case(final_path_indices[0][3])
                        3'd3: output_symbols_w[0] = 4'b1001; // -1+3j
                        3'd1: output_symbols_w[0] = 4'b1000; // -1+1j
                        -3'd1: output_symbols_w[0] = 4'b1010; // -1-1j
                        -3'd3: output_symbols_w[0] = 4'b1011; // -1-3j
                    endcase
                end
                -3'd3: begin
                    case(final_path_indices[0][3])
                        3'd3: output_symbols_w[0] = 4'b1101; // -3+3j
                        3'd1: output_symbols_w[0] = 4'b1100; // -3+1j
                        -3'd1: output_symbols_w[0] = 4'b1110; // -3-1j
                        -3'd3: output_symbols_w[0] = 4'b1111; // -3-3j
                    endcase
                end
            endcase
            case(final_path_indices[0][1]) // [Real(1), Real(2), Real(3), Imag(1), Imag(2), Imag(3)]
                3'd3: begin
                    case(final_path_indices[0][4])
                        3'd3: output_symbols_w[1] = 4'b0101; // 3+3j
                        3'd1: output_symbols_w[1] = 4'b0100; // 3+1j
                        -3'd1: output_symbols_w[1] = 4'b0110; // 3-1j
                        -3'd3: output_symbols_w[1] = 4'b0111; // 3-3j
                    endcase
                end
                3'd1: begin
                    case(final_path_indices[0][4])
                        3'd3: output_symbols_w[1] = 4'b0001; // 1+3j
                        3'd1: output_symbols_w[1] = 4'b0000; // 1+1j
                        -3'd1: output_symbols_w[1] = 4'b0010; // 1-1j
                        -3'd3: output_symbols_w[1] = 4'b0011; // 1-3j
                    endcase
                end
                -3'd1: begin
                    case(final_path_indices[0][4])
                        3'd3: output_symbols_w[1] = 4'b1001; // -1+3j
                        3'd1: output_symbols_w[1] = 4'b1000; // -1+1j
                        -3'd1: output_symbols_w[1] = 4'b1010; // -1-1j
                        -3'd3: output_symbols_w[1] = 4'b1011; // -1-3j
                    endcase
                end
                -3'd3: begin
                    case(final_path_indices[0][4])
                        3'd3: output_symbols_w[1] = 4'b1101; // -3+3j
                        3'd1: output_symbols_w[1] = 4'b1100; // -3+1j
                        -3'd1: output_symbols_w[1] = 4'b1110; // -3-1j
                        -3'd3: output_symbols_w[1] = 4'b1111; // -3-3j
                    endcase
                end
            endcase
            case(final_path_indices[0][2]) // [Real(1), Real(2), Real(3), Imag(1), Imag(2), Imag(3)]
                3'd3: begin
                    case(final_path_indices[0][5])
                        3'd3: output_symbols_w[2] = 4'b0101; // 3+3j
                        3'd1: output_symbols_w[2] = 4'b0100; // 3+1j
                        -3'd1: output_symbols_w[2] = 4'b0110; // 3-1j
                        -3'd3: output_symbols_w[2] = 4'b0111; // 3-3j
                    endcase
                end
                3'd1: begin
                    case(final_path_indices[0][5])
                        3'd3: output_symbols_w[2] = 4'b0001; // 1+3j
                        3'd1: output_symbols_w[2] = 4'b0000; // 1+1j
                        -3'd1: output_symbols_w[2] = 4'b0010; // 1-1j
                        -3'd3: output_symbols_w[2] = 4'b0011; // 1-3j
                    endcase
                end
                -3'd1: begin
                    case(final_path_indices[0][5])
                        3'd3: output_symbols_w[2] = 4'b1001; // -1+3j
                        3'd1: output_symbols_w[2] = 4'b1000; // -1+1j
                        -3'd1: output_symbols_w[2] = 4'b1010; // -1-1j
                        -3'd3: output_symbols_w[2] = 4'b1011; // -1-3j
                    endcase
                end
                -3'd3: begin
                    case(final_path_indices[0][5])
                        3'd3: output_symbols_w[2] = 4'b1101; // -3+3j
                        3'd1: output_symbols_w[2] = 4'b1100; // -3+1j
                        -3'd1: output_symbols_w[2] = 4'b1110; // -3-1j
                        -3'd3: output_symbols_w[2] = 4'b1111; // -3-3j
                    endcase
                end
            endcase
        end
    endcase
end


// logic signed [WORD_LENGTH-1:0] temp_histories [0:0];
// logic signed [2:0] temp_path_histories [0:3][0:0];
// logic signed [WORD_LENGTH_IN-1:0] temp_R_matrix [0:0];
// assign temp_histories[0] = z_in_r[5];
// assign temp_R_matrix[0] = R5[6];
// for(g=0; g < 4; g = g + 1) begin : initial_layer_gen
//     assign temp_path_histories[g][0] = symbols[g];
//     MCU #(
//         .WORD_LENGTH(WORD_LENGTH)
//     ) mcu_initial_inst (
//         .PED (20'b0),
//         .history (temp_histories[0]),
//         .rii (R6[6]),
//         .si (symbols[g]),
//         .new_PED (PEDs[g])
//     );
//     HCU #(
//         .WORD_LENGTH(WORD_LENGTH),
//         .STAGE(0)
//     ) hcu_initial_inst (
//         .z (z_in_r[4]),
//         .path_history (temp_path_histories[g]),
//         .Rij (temp_R_matrix),
//         .history (histories[g])
//     );
// end

//wires connecting the k best layer instances
// logic signed [WORD_LENGTH-1:0] PEDs1to2 [0:K_BEST_array[1]-1], histories1to2 [0:K_BEST_array[1]-1];
logic signed [WORD_LENGTH-1:0] PEDs16_w [0:15], PEDs16_r [0:15];
logic signed [WORD_LENGTH-1:0] histories16_w [0:15], histories16_r [0:15];
logic signed [2:0] path_indices16 [0:15][0:1];
// logic signed [2:0] path_indices1to2 [0:K_BEST_array[1]-1][0:1];
logic signed [WORD_LENGTH-1:0] PEDs2to3 [0:K_BEST_array[2]-1], histories2to3 [0:K_BEST_array[2]-1];
logic signed [2:0] path_indices2to3 [0:K_BEST_array[2]-1][0:2];
logic signed [WORD_LENGTH-1:0] PEDs3to4 [0:K_BEST_array[3]-1], histories3to4 [0:K_BEST_array[3]-1];
logic signed [2:0] path_indices3to4 [0:K_BEST_array[3]-1][0:3];
logic signed [WORD_LENGTH-1:0] PEDs4to5 [0:K_BEST_array[4]-1], histories4to5 [0:K_BEST_array[4]-1];
logic signed [2:0] path_indices4to5 [0:K_BEST_array[4]-1][0:4];

generate
    // enumerate 16 paths
    for(g = 0; g < 4; g = g+1)begin : initial_layer_gen
        for(h = 0; h < 4; h = h + 1) begin 
            assign path_indices16[4*g + h][0] = symbols[h];
            assign path_indices16[4*g + h][1] = symbols[g];
        end
    end
endgenerate


//directly calculate the first sixteen paths without k-best layer
logic signed [WORD_LENGTH-1:0] first_PED_w [0:3], first_PED_r [0:3];

always @(*) begin
    // PED of first layer
    for(int g = 0; g < 4; g = g + 1) begin : first_mcu_gen
        first_PED_w[g] = z_in_r[5] - (R6[6] * symbols[g]);
    end

    //path {3, 3} : history = z3 - (R4[5]*3 + R4[6]*3)
    histories16_w[0] = z3_r - ((R4[5] * 3'sd3) + (R4[6] * 3'sd3));
    PEDs16_w[0] = first_PED_r[0] + z4_r - ((R5[5] * 3'sd3) * (R5[5] * 3'sd3));

    //path {1, 3} : history = z3 - (R4[5]*1 + R4[6]*3)
    histories16_w[1] = z3_r - ((R4[5] * 3'sd1) + (R4[6] * 3'sd3));
    PEDs16_w[1] = first_PED_r[0] + z4_r - ((R5[5] * 3'sd1) * (R5[5] * 3'sd3));
    //path {-1, 3}: history = z3 - (R4[5]*-1 + R4[6]*3)
    histories16_w[2] = z3_r - ((R4[5] * -3'sd1) + (R4[6] * 3'sd3));
    PEDs16_w[2] = first_PED_r[0] + z4_r - ((R5[5] * -3'sd1) * (R5[5] * 3'sd3));

    //path {-3, 3}: history = z3 - (R4[5]*-3 + R4[6]*3)
    histories16_w[3] = z3_r - ((R4[5] * -3'sd3) + (R4[6] * 3'sd3));
    PEDs16_w[3] = first_PED_r[0] + z4_r - ((R5[5] * -3'sd3) * (R5[5] * 3'sd3));

    //path {3, 1}: history = z3 - (R4[5]*3 + R4[6]*1)
    histories16_w[4] = z3_r - ((R4[5] * 3'sd3) + (R4[6] * 3'sd1));
    PEDs16_w[4] = first_PED_r[1] + z4_r - ((R5[5] * 3'sd3) * (R5[5] * 3'sd1));

    //path {1, 1}: history = z3 - (R4[5]*1 + R4[6]*1)
    histories16_w[5] = z3_r - ((R4[5] * 3'sd1) + (R4[6] * 3'sd1));
    PEDs16_w[5] = first_PED_r[1] + z4_r - ((R5[5] * 3'sd1) * (R5[5] * 3'sd1));

    //path {-1, 1}: history = z3 - (R4[5]*-1 + R4[6]*1)
    histories16_w[6] = z3_r - ((R4[5] * -3'sd1) + (R4[6] * 3'sd1));
    PEDs16_w[6] = first_PED_r[1] + z4_r - ((R5[5] * -3'sd1) * (R5[5] * 3'sd1));

    //path {-3, 1}: history = z3 - (R4[5]*-3 + R4[6]*1)
    histories16_w[7] = z3_r - ((R4[5] * -3'sd3) + (R4[6] * 3'sd1));
    PEDs16_w[7] = first_PED_r[1] + z4_r - ((R5[5] * -3'sd3) * (R5[5] * 3'sd1));

    //path {3, -1}: history = z3 - (R4[5]*3 + R4[6]*-1)
    histories16_w[8] = z3_r - ((R4[5] * 3'sd3) + (R4[6] * -3'sd1));
    PEDs16_w[8] = first_PED_r[2] + z4_r - ((R5[5] * 3'sd3) * (R5[5] * -3'sd1));

    //path {1, -1}: history = z3 - (R4[5]*1 + R4[6]*-1)
    histories16_w[9] = z3_r - ((R4[5] * 3'sd1) + (R4[6] * -3'sd1));
    PEDs16_w[9] = first_PED_r[2] + z4_r -  ((R5[5] * 3'sd1) * (R5[5] * -3'sd1));

    //path {-1, -1}: history = z3 - (R4[5]*-1 + R4[6]*-1)
    histories16_w[10] = z3_r - ((R4[5] * -3'sd1) + (R4[6] * -3'sd1));
    PEDs16_w[10] = first_PED_r[2] + z4_r - ((R5[5] * -3'sd1) * (R5[5] * -3'sd1));
    
    //path {-3, -1}: history = z3 - (R4[5]*-3 + R4[6]*-1)
    histories16_w[11] = z3_r - ((R4[5] * -3'sd3) + (R4[6] * -3'sd1));
    PEDs16_w[11] = first_PED_r[2] + z4_r - ((R5[5] * -3'sd3) * (R5[5] * -3'sd1));

    //path {3, -3}: history = z3 - (R4[5]*3 + R4[6]*-3)
    histories16_w[12] = z3_r - ((R4[5] * 3'sd3) + (R4[6] * -3'sd3));
    PEDs16_w[12] = first_PED_r[3] + z4_r - ((R5[5] * 3'sd3) * (R5[5] * -3'sd3));

    //path {1, -3}: history = z3 - (R4[5]*1 + R4[6]*-3)
    histories16_w[13] = z3_r - ((R4[5] * 3'sd1) + (R4[6] * -3'sd3));
    PEDs16_w[13] = first_PED_r[3] + z4_r - ((R5[5] * 3'sd1) * (R5[5] * -3'sd3));

    //path {-1, -3}: history = z3 - (R4[5]*-1 + R4[6]*-3)
    histories16_w[14] = z3_r - ((R4[5] * -3'sd1) + (R4[6] * -3'sd3));
    PEDs16_w[14] = first_PED_r[3] + z4_r - ((R5[5] * -3'sd1) * (R5[5] * -3'sd3));

    //path {-3, -3}: history = z3 - (R4[5]*-3 + R4[6]*-3)
    histories16_w[15] = z3_r - ((R4[5] * -3'sd3) + (R4[6] * -3'sd3));
    PEDs16_w[15] = first_PED_r[3] + z4_r - ((R5[5] * -3'sd3) * (R5[5] * -3'sd3));
end



// // k-best layer instances
// k_best_layer #(
//     .WORD_LENGTH(WORD_LENGTH),
//     .WORD_LENGTH_R(WORD_LENGTH_R),
//     .WORD_LENGTH_Z(WORD_LENGTH_Z),
//     .K(K_BEST_array[0]),
//     .K_next(K_BEST_array[1]),
//     .STAGE(1)
// ) k_best_layer1_inst (
//     .clk (clk),
//     .rst (rst),
//     .PEDs (PEDs_r),
//     .histories (histories_r),
//     .path_indices (path_indices_r),
//     .R_matrix (R4[5:6]),
//     .Rii (R5[5]),
//     .z_value (z3_r),
//     .next_PEDs (PEDs1to2),
//     .next_histories (histories1to2),
//     .next_path_indices (path_indices1to2)
// );

k_best_layer #(
    .WORD_LENGTH(WORD_LENGTH),
    .WORD_LENGTH_R(WORD_LENGTH_R),
    .WORD_LENGTH_Z(WORD_LENGTH_Z),
    .K(K_BEST_array[1]),
    .K_next(K_BEST_array[2]),
    .STAGE(2)
) k_best_layer2_inst (
    .clk (clk),
    .rst (rst),
    .PEDs (PEDs16_r),
    .histories (histories16_r),
    .path_indices (path_indices16),
    .R_matrix (R3[4:6]),
    .Rii (R4[4]),
    .z_value (z2_r[0]),
    .next_PEDs (PEDs2to3),
    .next_histories (histories2to3),
    .next_path_indices (path_indices2to3)
);

k_best_layer #(
    .WORD_LENGTH(WORD_LENGTH),
    .WORD_LENGTH_R(WORD_LENGTH_R),
    .WORD_LENGTH_Z(WORD_LENGTH_Z),
    .K(K_BEST_array[2]),
    .K_next(K_BEST_array[3]),
    .STAGE(3)
) k_best_layer3_inst (
    .clk (clk),
    .rst (rst),
    .PEDs (PEDs2to3),
    .histories (histories2to3),
    .path_indices (path_indices2to3),
    .R_matrix (R2[3:6]),
    .Rii (R3[3]),
    .z_value (z1_r[K_BEST_array[2]]),
    .next_PEDs (PEDs3to4),
    .next_histories (histories3to4),
    .next_path_indices (path_indices3to4)
);

k_best_layer #(
    .WORD_LENGTH(WORD_LENGTH),
    .WORD_LENGTH_R(WORD_LENGTH_R),
    .WORD_LENGTH_Z(WORD_LENGTH_Z),
    .K(K_BEST_array[3]),
    .K_next(K_BEST_array[4]),
    .STAGE(4)
) k_best_layer4_inst (
    .clk (clk),
    .rst (rst),
    .PEDs (PEDs3to4),
    .histories (histories3to4),
    .path_indices (path_indices3to4),
    .R_matrix (R1[2:6]),
    .Rii (R2[2]),
    .z_value (z0_r[K_BEST_array[3]]),
    .next_PEDs (PEDs4to5),
    .next_histories (histories4to5),
    .next_path_indices (path_indices4to5)
);

k_best_layer #(
    .WORD_LENGTH(WORD_LENGTH),
    .WORD_LENGTH_R(WORD_LENGTH_R),
    .WORD_LENGTH_Z(WORD_LENGTH_Z),
    .K(K_BEST_array[4]),
    .K_next(K_BEST_array[5]),
    .STAGE(5)
) k_best_layer5_inst (
    .clk (clk),
    .rst (rst),
    .PEDs (PEDs4to5),
    .histories (histories4to5),
    .path_indices (path_indices4to5),
    .R_matrix (),
    .Rii (R1[1]),
    .z_value (),
    .next_PEDs (),
    .next_histories (),
    .next_path_indices (final_path_indices)
);

// sequential logic
always @(posedge clk or posedge rst) begin
    if(rst) begin
        state_r <= LOAD_MATRIX;
        counter_r <= 10'd0;
        for(i = 0; i < (1+2+3+4+5+6); i = i + 1) begin
            R_matrix_r[i] <= 0;
        end
        for(i = 0; i < 6; i = i + 1) begin
            z_in_r[i] <= 0;
        end
        for(i = 0; i < 4; i = i + 1) begin
            PEDs_r[i] <= 0;
            histories_r[i] <= 0;
            path_indices_r[i][0] <= 0;
        end
        // pipeline registers for z values
        for(i = 0; i <= (K_BEST_array[3]+K_BEST_array[2]+K_BEST_array[1]); i = i + 1) begin
            z0_r[i] <= 0;
        end
        for(i = 0; i <= (K_BEST_array[2]+K_BEST_array[1]); i = i + 1) begin
            z1_r[i] <= 0;
        end
        for(i = 0; i <= (K_BEST_array[1]); i = i + 1) begin
            z2_r[i] <= 0;
        end
        z3_r <= 0;
        // layer enable registers
        for(i = 0; i < 6; i = i + 1) begin
            layer_enable_r[i] <= 1'b0;
        end
        // output registers
        for(i = 0; i < 3; i = i + 1) begin
            output_symbols_r[i] <= 0;
        end
        for(i = 0; i < 4; i = i + 1) begin
            first_PED_r[i] <= 0;
        end
        for(i = 0; i < 16; i = i + 1) begin
            histories16_r[i] <= 0;
            PEDs16_r[i] <= 0;
        end
        o_valid_r <= 1'b0;
    end else begin
        state_r <= state_w;
        counter_r <= counter_w;
        for(i = 0; i < (1+2+3+4+5+6); i = i + 1) begin
            R_matrix_r[i] <= R_matrix_w[i];
        end
        for(i = 0; i < 6; i = i + 1) begin
            z_in_r[i] <= z_in_w[i];
        end
        for(i = 0; i < 4; i = i + 1) begin
            PEDs_r[i] <= PEDs_w[i];
            histories_r[i] <= histories_w[i];
            path_indices_r[i][0] <= path_indices_w[i][0];
        end
        // pipeline registers for z values
        for(i = 0; i <= (K_BEST_array[3]+K_BEST_array[2]+K_BEST_array[1]+3); i = i + 1) begin
            z0_r[i] <= z0_w[i];
        end
        for(i = 0; i <= (K_BEST_array[2]+K_BEST_array[1]+2); i = i + 1) begin
            z1_r[i] <= z1_w[i];
        end
        for(i = 0; i <= (K_BEST_array[1]+1); i = i + 1) begin
            z2_r[i] <= z2_w[i];
        end
        z3_r <= z3_w;
        // layer enable registers
        for(i = 0; i < 6; i = i + 1) begin
            layer_enable_r[i] <= layer_enable_w[i];
        end
        // output registers
        for(i = 0; i < 3; i = i + 1) begin
            output_symbols_r[i] <= output_symbols_w[i];
        end
        o_valid_r <= o_valid_w;
        for(i = 0; i < 4; i = i + 1) begin
            first_PED_r[i] <= first_PED_w[i];
        end
        for(i = 0; i < 16; i = i + 1) begin
            histories16_r[i] <= histories16_w[i];
            PEDs16_r[i] <= PEDs16_w[i];
        end
    end
end
    
endmodule

module k_best_layer #(
    parameter WORD_LENGTH = 16,
    parameter WORD_LENGTH_R = 16,
    parameter WORD_LENGTH_Z = 18,
    // number of nodes at this layer
    parameter K = 8,  
    // number of nodes at next layer
    parameter K_next = 8,
    // current stage index
    parameter STAGE = 1
) (
    input clk,
    input rst,
    // K input nodes, each with PED, history, and path index
    // Partial Euclidean Distance for K input nodes
    input signed [WORD_LENGTH-1:0] PEDs [0:K-1],
    // History for K input nodes
    input signed [WORD_LENGTH-1:0] histories [0:K-1],
    // previously chosen path indices
    input signed [2:0] path_indices [0:K-1][0:STAGE-1],

    // R matrix for History Computation
    input signed [WORD_LENGTH_R-1:0] R_matrix [0:STAGE],
    // diagnonal element Rii for current stage
    input signed [WORD_LENGTH_R-1:0] Rii,
    // z
    input signed [WORD_LENGTH_Z-1:0] z_value,

    output signed [WORD_LENGTH-1:0] next_PEDs [0:K_next-1],
    output signed [WORD_LENGTH-1:0 ] next_histories [0:K_next-1],
    output signed [2:0] next_path_indices [0:K_next-1][0:(STAGE+1)-1]
);

localparam INDEX_LENGTH = $clog2(K);
integer i, j, k;
genvar g, h;

// output registers require pipelining, (K_next - i) stages of registers for output of stage i
logic signed [WORD_LENGTH-1:0] next_PEDs_w [0:K_next-1][0:K_next], next_PEDs_r [0:K_next-1][0:K_next];
logic signed [WORD_LENGTH-1:0 ] next_histories_w [0:K_next-1] [0:K_next], next_histories_r [0:K_next-1][0:K_next];
logic signed [2:0] next_path_indices_w [0:K_next-1][0:K_next][0:STAGE], next_path_indices_r [0:K_next-1][0:K_next][0:STAGE];

// step 1: for each of the K input nodes, compute Schnorr-Euchner (SE) order with ascending branch metrics ei(si) by enumeration.
logic signed [2:0] SE_orders_w [0:K_next-1][0:K-1][0:3], SE_orders_r [0:K_next-1][0:K-1][0:3];
generate
    for(g=0; g < K; g = g + 1) begin : se_order_gen
        SE_list #(
            .WORD_LENGTH(WORD_LENGTH),
            .WORD_LENGTH_R(WORD_LENGTH_R)
        ) se_list_inst (
            .history (histories[g]),
            .rii (Rii),
            .SE_order (SE_orders_w[0][g])
        );
    end
endgenerate

// step 2: initial sorting stage contains K MCUs and a full comparator tree
// pipeline registers for original PED and history values for MCU update in later stages
logic signed [WORD_LENGTH-1:0] stage_PEDs_w [0:K_next-1][0:K-1], stage_PEDs_r [0:K_next-1][0:K-1];
logic signed [WORD_LENGTH-1:0] stage_histories_w [0:K_next-1][0:K-1], stage_histories_r [0:K_next-1][0:K-1];

//MCU updated PED values for the initial comparator tree
logic signed [WORD_LENGTH-1:0] updated_PEDs [0:K-1];

// pipeline registers for intermediate comparator tree results at each stage
logic signed [WORD_LENGTH-1:0] intermediate_results_w [0:K_next-1][0:K-2], intermediate_results_r [0:K_next-1][0:K-2];
logic [INDEX_LENGTH-1:0] intermediate_indices_w [0:K_next-1][0:K-2], intermediate_indices_r [0:K_next-1][0:K-2];

// minimum PED and index outputs from each comparator tree stage
logic signed [WORD_LENGTH-1:0] min_PEDs [0:K_next-1];
logic [INDEX_LENGTH-1:0] min_indices_w [0:K_next-1], min_indices_r [0:K_next-1];

// next sibling MCU updated PEDs for reduced comparator tree stages
logic signed [WORD_LENGTH-1:0] next_sibling_PEDs [0:K_next-1];

// pipeline registers for z value
logic signed [WORD_LENGTH_Z-1:0] z_value_w [0:K_next-1], z_value_r [0:K_next-1];

// pipeline registers for path indices
logic signed [2:0] stage_path_indices_w [0:K_next-1][0:K-1][0:STAGE-1], stage_path_indices_r [0:K_next-1][0:K-1][0:STAGE-1];

// pipeline register for R matrix
logic signed [WORD_LENGTH_R-1:0] stage_R_matrix_w [0:K_next-1][0:STAGE], stage_R_matrix_r [0:K_next-1][0:STAGE];
logic signed [WORD_LENGTH_R-1:0] Rii_w [0:K_next-1], Rii_r [0:K_next-1];

generate
    for(g=0; g < K; g = g + 1) begin : mcu_gen
        MCU #(
            .WORD_LENGTH(WORD_LENGTH),
            .WORD_LENGTH_R(WORD_LENGTH_R)
        ) mcu_inst (
            .PED (PEDs[g]),
            .history (histories[g]),
            .rii (Rii),
            .si (SE_orders_w[0][g][0]), // first candidate
            .new_PED (updated_PEDs[g])
        );
    end
endgenerate
comparator_tree #(
    .WORD_LENGTH(WORD_LENGTH),
    .K_in(K)
) comparator_tree_inst (
    .PEDs_in (updated_PEDs),
    .intermediate_results (intermediate_results_w[0]),
    .intermediate_index (intermediate_indices_w[0]),
    .o_min_PED (min_PEDs[0]),
    .o_min_index (min_indices_w[0])
);

// step 3: intermediate stages with reduced comparator trees
// total of K_next-1 stages
generate
    for(g=1; g < K_next; g = g + 1) begin : reduced_tree_gen
        // first, update the PED of the previous minimum PED node with the next candidate symbol
        MCU #(
            .WORD_LENGTH(WORD_LENGTH)
        ) mcu_stage_inst (
            .PED (stage_PEDs_r[g-1][min_indices_r[g-1]]),
            .history (stage_histories_r[g-1][min_indices_r[g-1]]),
            .rii (Rii_r[g-1]),
            .si (SE_orders_r[g-1][min_indices_r[g-1]][1]), // 1 st candidate
            .new_PED (next_sibling_PEDs[g-1])
        );
        reduced_comparator_tree #(
            .WORD_LENGTH(WORD_LENGTH),
            .K_in(K)
        ) reduced_comparator_tree_inst (
            .new_PEDs_in (next_sibling_PEDs[g-1]),
            .new_index_in (min_indices_r[g-1]),
            .intermediate_results_in (intermediate_results_r[g-1]),
            .intermediate_index_in (intermediate_indices_r[g-1]),
            .new_intermediate_results_out (intermediate_results_w[g]),
            .new_intermediate_index_out (intermediate_indices_w[g]),
            .o_min_PED (min_PEDs[g]),
            .o_min_index (min_indices_w[g])
        );
    end
endgenerate

// step 4: calculate output histories
generate
    for(g=0; g < K_next; g = g + 1) begin : history_gen
        HCU #(
            .WORD_LENGTH(WORD_LENGTH),
            .STAGE(STAGE)
        ) hcu_inst (
            .z (z_value_w[g]),
            .path_history (next_path_indices_w[g][0]),
            .Rij (stage_R_matrix_w[g]),
            .history (next_histories_w[g][0])
        );
    end
endgenerate



// register pipeline logic
// based on chosen min index, we need to update the SE orders for next stages
always@(*) begin

    // pass inputs into the pipeline registers
    for(j = 0; j < K; j = j + 1) begin
        stage_PEDs_w[0][j] = PEDs[j];
        stage_histories_w[0][j] = histories[j];
        for(k = 0; k < STAGE; k = k + 1) begin
            stage_path_indices_w[0][j][k] = path_indices[j][k];
        end
    end
    for(j = 0; j <= STAGE; j = j + 1) begin
        stage_R_matrix_w[0][j] = R_matrix[j];
    end
    z_value_w[0] = z_value;
    Rii_w[0] = Rii;

    // pass current stage pipeline registers to next stages
    for(i=0; i < K_next-1; i = i + 1) begin
        for(j=0; j < K; j = j + 1) begin
            stage_PEDs_w[i+1][j] = stage_PEDs_r[i][j];
            stage_histories_w[i+1][j] = stage_histories_r[i][j];
            for(k = 0; k < STAGE; k = k + 1) begin
                stage_path_indices_w[i+1][j][k] = stage_path_indices_r[i][j][k];
            end
            for(k = 0; k < 4; k = k + 1) begin
                SE_orders_w[i+1][j][k] = SE_orders_r[i][j][k];
            end
        end
        for(j = 0; j <= STAGE; j = j + 1) begin
            stage_R_matrix_w[i+1][j] = stage_R_matrix_r[i][j];
        end
        z_value_w[i+1] = z_value_r[i];
        Rii_w[i+1] = Rii_r[i];
    end
    
    // for the chosen min index, shift left the SE order list to remove the chosen candidate
    for(i = 0; i < K_next-1; i = i + 1) begin
        for(k = 0; k < 3; k = k + 1) begin
            SE_orders_w[i+1][min_indices_r[i]][k] = SE_orders_r[i][min_indices_r[i]][k+1];
        end
        SE_orders_w[i+1][min_indices_r[i]][3] = 3'd0; // padding
    end

    // output pipeline register logic
    for(i = 0; i < K_next; i = i + 1) begin
        for(j=0; j < K_next; j = j + 1) begin
            next_PEDs_w[i][j+1] = next_PEDs_r[i][j];
            next_histories_w[i][j+1] = next_histories_r[i][j];
            for(k = 0; k <= STAGE; k = k + 1) begin
                next_path_indices_w[i][j+1][k] = next_path_indices_r[i][j][k];
            end
        end
        // assign the minimum PED and corresponding path index to output
        next_PEDs_w[i][0] = min_PEDs[i];
        for(k = 1; k <= STAGE; k = k + 1) begin
            next_path_indices_w[i][0][k] = stage_path_indices_w[i][min_indices_w[i]][k-1];
        end
        next_path_indices_w[i][0][0] = SE_orders_w[i][min_indices_w[i]][0]; // new chosen symbol
    end
end

// output assignment logic: the i th output passes through (K_next - i) stages of registers
generate
    for(g=0; g < K_next; g = g + 1) begin : output_assign_gen
        assign next_PEDs[g] = next_PEDs_r[g][K_next-g-1];
        assign next_histories[g] = next_histories_r[g][K_next-g-1];
        assign next_path_indices[g] = next_path_indices_r[g][K_next-g-1];
    end
endgenerate

// sequential logic for pipeline registers
always @(posedge clk or posedge rst) begin
    if(rst) begin
        // reset all pipeline registers
        for(i=0; i < K_next; i = i + 1) begin
            for(j=0; j < K; j = j + 1) begin
                stage_PEDs_r[i][j] <= 0;
                stage_histories_r[i][j] <= 0;
                for(k = 0; k < STAGE; k = k + 1) begin
                    stage_path_indices_r[i][j][k] <= 0;
                end
                for(k = 0; k < 4; k = k + 1) begin
                    SE_orders_r[i][j][k] <= 0;
                end
            end
            min_indices_r[i] <= 0;
            for(j = 0; j <= STAGE; j = j + 1) begin
                stage_R_matrix_r[i][j] <= 0;
            end
            z_value_r[i] <= 0;
            for(j=0; j < K-1; j = j + 1) begin
                intermediate_results_r[i][j] <= 0;
                intermediate_indices_r[i][j] <= 0;
            end
        end
        for(j=0; j < K_next; j = j + 1) begin
            Rii_r[j] <= 0;
        end
        for(i=0; i < K_next; i = i + 1) begin
            for(j=0; j <= K_next; j = j + 1) begin
                next_PEDs_r[i][j] <= 0;
                next_histories_r[i][j] <= 0;
                for(k = 0; k <= STAGE; k = k + 1) begin
                    next_path_indices_r[i][j][k] <= 0;
                end
            end
        end
    end else begin
        // update all pipeline registers
        for(i=0; i < K_next; i = i + 1) begin
            for(j=0; j < K; j = j + 1) begin
                stage_PEDs_r[i][j] <= stage_PEDs_w[i][j];
                stage_histories_r[i][j] <= stage_histories_w[i][j];
                for(k = 0; k < STAGE; k = k + 1) begin
                    stage_path_indices_r[i][j][k] <= stage_path_indices_w[i][j][k];
                end
                for(k = 0; k < 4; k = k + 1) begin
                    SE_orders_r[i][j][k] <= SE_orders_w[i][j][k];
                end
            end
            min_indices_r[i] <= min_indices_w[i];
            for(j = 0; j <= STAGE; j = j + 1) begin
                stage_R_matrix_r[i][j] <= stage_R_matrix_w[i][j];
            end
            z_value_r[i] <= z_value_w[i];
            for(j=0; j < K-1; j = j + 1) begin
                intermediate_results_r[i][j] <= intermediate_results_w[i][j];
                intermediate_indices_r[i][j] <= intermediate_indices_w[i][j];
            end
        end
        for(j=0; j < K_next; j = j + 1) begin
            Rii_r[j] <= Rii_w[j];
        end
        for(i=0; i < K_next; i = i + 1) begin
            for(j=0; j <= K_next; j = j + 1) begin
                next_PEDs_r[i][j] <= next_PEDs_w[i][j];
                next_histories_r[i][j] <= next_histories_w[i][j];
                for(k = 0; k <= STAGE; k = k + 1) begin
                    next_path_indices_r[i][j][k] <= next_path_indices_w[i][j][k];
                end
            end
        end
    end
end

endmodule


function automatic [2:0] invertornot (
    input sel,
    input [2:0] SE_order
);

begin
    invertornot = sel ? ~SE_order + 1'b1 : SE_order;
end

endfunction

module SE_list #(
    parameter WORD_LENGTH = 16,
    parameter WORD_LENGTH_R = 16
) (
    input signed [WORD_LENGTH-1:0] history,
    input signed [WORD_LENGTH_R-1:0] rii,
    output reg signed [2:0] SE_order [0:3]
);
// since we are using 16-QAM with RVD, the length of SE order is 4 for each input node
// the candidate set is {s1, s2, s3, s4} = { -3, -1, 1, 3 }
// the branch metrics are computed as ei(si) = H(si+1) - r_ii*si
// use cut based enumeration:
// Compare H with 3*r_ii, 1*r_ii, -1*r_ii, -3*r_ii to determine the SE order
// dicision boundaries are +2*r_ii, 0, -2*r_ii


wire signed [WORD_LENGTH-1:0] compare1 = rii << 1; // 2*r_ii
wire signed [WORD_LENGTH-1:0] compare2 = rii;  // r_ii
wire signed [WORD_LENGTH-1:0] region1;
wire signed [WORD_LENGTH-1:0] region2;
wire sign0 = history[WORD_LENGTH-1] ^ rii[WORD_LENGTH_R-1];
wire sign1 = region1[WORD_LENGTH-1] ^ rii[WORD_LENGTH_R-1];
wire sign2 = region2[WORD_LENGTH-1] ^ rii[WORD_LENGTH_R-1];
reg [2:0] SE_order_temp [0:3];
integer i;

add_sub  #(
    .WORD_LENGTH(WORD_LENGTH)
)
add_sub_inst (
    .A (history),
    .B (compare1),
    .sel (sign0),
    .Y (region1)
);

add_sub  #(
    .WORD_LENGTH(WORD_LENGTH)
)
add_sub_inst2 (
    .A (region1),
    .B (compare2),
    .sel (sign1),
    .Y (region2)
);

// if H >= 3*r_ii:
// sign0 = 0, sign1 = 0, sign2 = 0 -> SE_order = {3, 1, -1, -3}
// if H >= 2*r_ii and H < 3*r_ii:
// sign0 = 0, sign1 = 0, sign2 = 1 -> SE_order = {3, 1, -1, -3}
// if r_ii <= H < 2*r_ii:
// sign0 = 0, sign1 = 1, sign2 = 0 -> SE_order = {1, 3, -1, -3}
// if 0 <= H < r_ii:
// sign0 = 0, sign1 = 1, sign2 = 1 -> SE_order = {1, -1, 3, -3}
// if -r_ii <= H < 0:
// sign0 = 1, sign1 = 0, sign2 = 0 -> SE_order = {-1, 1, 3, -3}
// if -2*r_ii <= H < -r_ii:
// sign0 = 1, sign1 = 0, sign2 = 1 -> SE_order = {-1, -3, 1, 3}
// if -3*r_ii <= H < -2*r_ii:
// sign0 = 1, sign1 = 1, sign2 = 0 -> SE_order = {-3, -1, 1, 3}
// if H < -3*r_ii:
// sign0 = 1, sign1 = 1, sign2 = 1 -> SE_order = {-3, -1, 1, 3}

always @(*) begin
    case({sign0, sign1, sign2})
        3'b000: begin
            SE_order = {3'd3, 3'd1, -3'd1, -3'd3};
        end
        3'b001: begin
            SE_order = {3'd3, 3'd1, -3'd1, -3'd3};
        end
        3'b010: begin
            SE_order = {3'd1, 3'd3, -3'd1, -3'd3};
        end
        3'b011: begin
            SE_order = {3'd1, -3'd1, 3'd3, -3'd3};
        end
        3'b100: begin
            SE_order = {-3'd1, 3'd1, -3'd3, 3'd3};
        end
        3'b101: begin
            SE_order = {-3'd1, -3'd3, 3'd1, 3'd3};
        end
        3'b110: begin
            SE_order = {-3'd3, -3'd1, 3'd1, 3'd3};
        end
        3'b111: begin
            SE_order = {-3'd3, -3'd1, 3'd1, 3'd3};
        end
    endcase
    // for (i = 0; i < 4; i = i + 1) begin
    //     SE_order[i] = invertornot(rii[WORD_LENGTH_R-1], SE_order_temp[i]);
    // end
end
endmodule

module add_sub #(
    parameter WORD_LENGTH = 16
) (
    input signed [WORD_LENGTH-1:0] A,
    input signed [WORD_LENGTH-1:0] B,
    input sel, // 0 for addition, 1 for subtraction
    output signed [WORD_LENGTH-1:0] Y
);
assign Y = sel ? (A + B) : (A - B);
endmodule


module MCU #(
    parameter WORD_LENGTH = 16,
    parameter WORD_LENGTH_R = 16
) (
    input signed [WORD_LENGTH-1:0] PED,
    input signed [WORD_LENGTH-1:0] history,
    input signed [WORD_LENGTH_R-1:0] rii,
    input signed [2:0] si,
    output reg signed [WORD_LENGTH-1:0] new_PED
);

// PED_new = PED_old + abs(history - rii*si)
// s_i can only take values from {-3, -1, 1, 3} for 16-QAM with RVD

always @(*) begin
    case(si)
        3'b011: begin
            if(history > rii*3) begin
                new_PED = PED + history - rii*3;
            end else begin
                new_PED = PED + rii*3 - history;
            end
        end
        3'b001: begin
            if(history > rii) begin
                new_PED = PED + history - rii;
            end else begin
                new_PED = PED + rii - history;
            end
        end
        3'b111: begin
            if(history > -rii) begin
                new_PED = PED + history + rii;
            end else begin
                new_PED = PED - rii - history;
            end
        end
        3'b101: begin
            if(history > -rii*3) begin
                new_PED = PED + history + rii*3;
            end else begin
                new_PED = PED - rii*3 - history;
            end
        end
        default: begin
            new_PED = 2**(WORD_LENGTH-1)-1; // if all SE list exhausted, set PED to max value
        end
    endcase
end
endmodule

module comparator_tree #(
    parameter WORD_LENGTH = 16,
    parameter K_in = 16,
    parameter LEVELS = $clog2(K_in),
    parameter INDEX_LENGTH = $clog2(K_in)
) (
    input signed [WORD_LENGTH-1:0] PEDs_in [0:K_in-1],
    output signed [WORD_LENGTH-1:0] intermediate_results [0:K_in-2],
    output [INDEX_LENGTH-1:0] intermediate_index [0:K_in-2],
    output signed [WORD_LENGTH-1:0] o_min_PED,
    output  [INDEX_LENGTH-1:0] o_min_index
);

wire [INDEX_LENGTH-1:0] min_index [0:LEVELS][0:K_in-1];
wire signed [WORD_LENGTH-1:0] min_results [0:LEVELS][0:K_in-1];

assign o_min_PED = min_results[LEVELS][0];
assign o_min_index = min_index[LEVELS][0];

genvar g, h;
generate
    for(g=0; g < K_in; g = g + 1) begin : index_gen
        assign min_index[0][g] = g;
        assign min_results[0][g] = PEDs_in[g];
    end
    for(g=0; g < LEVELS; g = g + 1) begin : level_gen
        for(h=0; h < (K_in/(2**(g+1))); h = h + 1) begin : compare_gen
            compare2 #(
                .WORD_LENGTH(WORD_LENGTH),
                .INDEX_LENGTH(INDEX_LENGTH)
            ) compare2_inst (
                .A (min_results[g][2*h]),
                .B (min_results[g][2*h+1]),
                .index_a (min_index[g][2*h]),
                .index_b (min_index[g][2*h+1]),
                .min (min_results[g+1][h]),
                .min_index (min_index[g+1][h]),
                .max (intermediate_results[(K_in-K_in/(2**g))+h]),
                .max_index (intermediate_index[(K_in-K_in/(2**g))+h])
            );
        end    
    end
endgenerate
endmodule

module reduced_comparator_tree #(
    parameter WORD_LENGTH = 16,
    parameter K_in = 16,
    parameter LEVELS = $clog2(K_in),
    parameter INDEX_LENGTH = $clog2(K_in)
) (
    input signed [WORD_LENGTH-1:0] new_PEDs_in,
    input [INDEX_LENGTH-1:0] new_index_in,
    input signed [WORD_LENGTH-1:0] intermediate_results_in [0:K_in-2],
    input [INDEX_LENGTH-1:0] intermediate_index_in [0:K_in-2],

    output reg signed [WORD_LENGTH-1:0] new_intermediate_results_out [0:K_in-2],
    output reg [INDEX_LENGTH-1:0] new_intermediate_index_out [0:K_in-2],
    output  [WORD_LENGTH-1:0] o_min_PED,
    output  [INDEX_LENGTH-1:0] o_min_index
);

logic signed [WORD_LENGTH-1:0] updated_intermediate_results [0:LEVELS-1];
logic [INDEX_LENGTH-1:0] updated_intermediate_indices [0:LEVELS-1];

logic signed [WORD_LENGTH-1:0] min_compare [0:LEVELS-1];
logic [INDEX_LENGTH-1:0] min_index [0:LEVELS-1];

assign o_min_PED = min_compare[LEVELS-1];
assign o_min_index = min_index[LEVELS-1];

logic [INDEX_LENGTH-1:0] compare_indices [0:LEVELS-1];

genvar g;
generate
    compare2 #(
        .WORD_LENGTH(WORD_LENGTH), 
        .INDEX_LENGTH(INDEX_LENGTH)

    ) compare2_inst (
        .A (new_PEDs_in),
        .B (intermediate_results_in[new_index_in[INDEX_LENGTH-1:1]]), // divide new_index_in by 2
        .index_a (new_index_in),
        .index_b (intermediate_index_in[new_index_in[INDEX_LENGTH-1:1]]),
        .min (min_compare[0]),
        .min_index (min_index[0]),
        .max (updated_intermediate_results[0]),
        .max_index (updated_intermediate_indices[0])
    );
    for(g=1; g < LEVELS; g = g + 1) begin : compare_gen
        assign compare_indices[g] = new_index_in >> (g+1);
        compare2 #(
            .WORD_LENGTH(WORD_LENGTH),
            .INDEX_LENGTH(INDEX_LENGTH)
        ) compare2_inst (
            .A (min_compare[g-1]),
            .B (intermediate_results_in[K_in - K_in/(2**g) + compare_indices[g]]),
            .index_a (min_index[g-1]),
            .index_b (intermediate_index_in[K_in - K_in/(2**g) + compare_indices[g]]),
            .min (min_compare[g]),
            .min_index (min_index[g]),
            .max (updated_intermediate_results[g]),
            .max_index (updated_intermediate_indices[g])
        );
    end
endgenerate

integer i;
logic [INDEX_LENGTH-1:0] temp_indices [0:LEVELS-1];
always @(*) begin
    for(i=0; i < K_in-2; i = i + 1) begin
        new_intermediate_results_out[i] = intermediate_results_in[i];
        new_intermediate_index_out[i] = intermediate_index_in[i];
    end
    // update the intermediate results and indices based on updated_intermediate_results and updated_intermediate_indices
    for(i=0; i < LEVELS; i = i + 1) begin
        temp_indices[i] = new_index_in >> (i+1);
        new_intermediate_results_out[K_in - K_in/(2**i) + temp_indices[i]] = updated_intermediate_results[i];
        new_intermediate_index_out[K_in - K_in/(2**i) + temp_indices[i]] = updated_intermediate_indices[i];
    end
end

endmodule

module compare2 #(
    parameter WORD_LENGTH = 16,
    parameter INDEX_LENGTH = 4
)(
    input signed [WORD_LENGTH-1:0] A,
    input signed [WORD_LENGTH-1:0] B,
    input [INDEX_LENGTH-1:0] index_a,
    input [INDEX_LENGTH-1:0] index_b,
    output signed [WORD_LENGTH-1:0] min,
    output [INDEX_LENGTH-1:0] min_index,
    output signed [WORD_LENGTH-1:0] max,
    output [INDEX_LENGTH-1:0] max_index
);
assign {min, min_index} = (A < B) ? {A, index_a} : {B, index_b};
assign {max, max_index} = (A < B) ? {B, index_b} : {A, index_a};
endmodule


module HCU #(
    parameter WORD_LENGTH = 16,
    parameter WORD_LENGTH_R = 16,
    parameter WORD_LENGTH_Z = 18,
    parameter STAGE = 1
) (
    input signed [WORD_LENGTH_Z-1:0] z,
    input signed [2:0] path_history [0:STAGE],
    input signed [WORD_LENGTH_R-1:0] Rij [0:STAGE],
    output reg signed [WORD_LENGTH-1:0] history
);
integer i;

logic signed [WORD_LENGTH-1:0] intermediate_sum [0:STAGE+1];
// calculate SUM_j (r_ij*sj)
always @(*) begin
    intermediate_sum[0] = 0;
    for(i = 0; i < STAGE+1; i = i+1) begin
        case (path_history[i])
            3'b011: begin
                intermediate_sum[i+1] = $signed(intermediate_sum[i]) + $signed(Rij[i])*3;
            end
            3'b001: begin
                intermediate_sum[i+1] = $signed(intermediate_sum[i]) + $signed(Rij[i]);
            end
            3'b101: begin
                intermediate_sum[i+1] = $signed(intermediate_sum[i]) - $signed(Rij[i])*3;
            end
            3'b111: begin
                intermediate_sum[i+1] = $signed(intermediate_sum[i]) - $signed(Rij[i]);
            end
            default: begin
                intermediate_sum[i+1] = $signed(intermediate_sum[i]);
            end
        endcase
    end
end

assign history = $signed(z) - $signed(intermediate_sum[STAGE+1]);
endmodule    