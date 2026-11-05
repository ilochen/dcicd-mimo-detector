// Six-level L1 K-best detector for a QR-preprocessed 3x3 complex channel.
// Valid channel beats (flag=0) write six signed R coefficients, MSB first.
// On the fourth beat only the first three coefficients are meaningful.
// Valid observation beats (flag=1) carry z[0:5] in the same MSB-first order.
module mimo_detector #(
    parameter INT_LENGTH_Z = 6,
    parameter FRAC_LENGTH_Z = 10,
    parameter INT_LENGTH_R = 4,
    parameter FRAC_LENGTH_R = 12,
    parameter WORD_LENGTH_IN = 16
) (
    input logic clk,
    input logic rst,
    input logic flagChannelorData,
    input logic [6*WORD_LENGTH_IN-1:0] InData,
    input logic i_valid,
    output logic o_valid,
    output logic [11:0] OutData
);
    if (INT_LENGTH_R + FRAC_LENGTH_R != WORD_LENGTH_IN ||
        INT_LENGTH_Z + FRAC_LENGTH_Z != WORD_LENGTH_IN ||
        INT_LENGTH_R < 1 || INT_LENGTH_Z < 1 || FRAC_LENGTH_R < 0 || FRAC_LENGTH_Z < 0) begin : invalid_format
        initial $error("Each signed Q format must match WORD_LENGTH_IN");
    end

    localparam int KEEP [0:5] = '{4, 16, 8, 8, 2, 1};
    localparam int FRAC = FRAC_LENGTH_R > FRAC_LENGTH_Z ? FRAC_LENGTH_R : FRAC_LENGTH_Z;
    localparam int R_SHIFT = FRAC - FRAC_LENGTH_R;
    localparam int Z_SHIFT = FRAC - FRAC_LENGTH_Z;
    // Each residual includes at most 6 products by +/-3, plus one z.
    // The full six-row metric uses <= 6 z terms and 21 such products.
    localparam int COST_BITS = WORD_LENGTH_IN + (R_SHIFT > Z_SHIFT ? R_SHIFT : Z_SHIFT) + 7;

    typedef logic [20:0][WORD_LENGTH_IN-1:0] matrix_t;
    typedef logic [5:0][WORD_LENGTH_IN-1:0] observation_t;
    matrix_t pending_r, active_r;
    matrix_t matrix_with_beat;
    logic [1:0] beat_index;
    logic have_channel;
    logic [6:0] valid;
    matrix_t r_pipe [0:5];
    observation_t z_pipe [0:5];

    // Merge one valid beat, including the current beat on the commit edge.
    always_comb begin
        matrix_with_beat = pending_r;
        for (int lane = 0; lane < 6; lane++) begin
            if (int'(beat_index)*6 + lane < 21)
                matrix_with_beat[int'(beat_index)*6 + lane] =
                    InData[(6-lane)*WORD_LENGTH_IN-1 -: WORD_LENGTH_IN];
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            beat_index <= 0;
            have_channel <= 0;
        end else if (i_valid && !flagChannelorData) begin
            pending_r <= matrix_with_beat;
            beat_index <= beat_index + 2'd1;
            if (beat_index == 3) begin
                active_r <= matrix_with_beat;
                have_channel <= 1;
            end
        end
    end

    // Snapshot the active R alongside z. Changing the channel never changes
    // the metric of an earlier observation in flight. Bubbles occupy a slot.
    wire accept = i_valid && flagChannelorData && have_channel;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) valid <= '0;
        else valid <= {valid[5:0], accept};
    end
    always_ff @(posedge clk) begin
        if (accept) begin
            r_pipe[0] <= active_r;
            for (int lane = 0; lane < 6; lane++)
                z_pipe[0][lane] <= InData[(6-lane)*WORD_LENGTH_IN-1 -: WORD_LENGTH_IN];
        end
        for (int d = 1; d < 6; d++) begin
            if (valid[d-1]) begin
                r_pipe[d] <= r_pipe[d-1];
                z_pipe[d] <= z_pipe[d-1];
            end
        end
    end

    for (genvar d = 0; d < 6; d++) begin : depth
        localparam int PARENTS = d == 0 ? 1 : KEEP[d-1];
        logic [PARENTS-1:0][COST_BITS-1:0] parent_cost;
        logic [PARENTS-1:0][11:0] parent_path;
        logic [KEEP[d]-1:0][COST_BITS-1:0] kept_cost;
        logic [KEEP[d]-1:0][11:0] kept_path;
        if (d == 0) begin : root_path
            assign parent_cost = '0;
            assign parent_path = '0;
        end else begin : survivor_paths
            assign parent_cost = depth[d-1].kept_cost;
            assign parent_path = depth[d-1].kept_path;
        end
        kbest_row #(
            .AXIS(5-d), .PARENTS(PARENTS), .KEEP(KEEP[d]),
            .IN_BITS(WORD_LENGTH_IN), .COST_BITS(COST_BITS),
            .R_SHIFT(R_SHIFT), .Z_SHIFT(Z_SHIFT)
        ) search (
            .clk(clk), .enable(valid[d]), .r(r_pipe[d]), .z(z_pipe[d]),
            .parent_cost(parent_cost), .parent_path(parent_path),
            .kept_cost(kept_cost), .kept_path(kept_path)
        );
    end

    // Path fields encode ranks 0..3 for the ordered alphabet [+3,+1,-1,-3].
    function automatic logic [1:0] gray_bits(input logic [1:0] rank);
        case (rank)
            0: return 2'b01;
            1: return 2'b00;
            2: return 2'b10;
            default: return 2'b11;
        endcase
    endfunction

    for (genvar tx=0; tx<3; tx++) begin : pack_symbol
        assign OutData[11-4*tx -: 4] = {
            gray_bits(depth[5].kept_path[0][2*tx +: 2]),
            gray_bits(depth[5].kept_path[0][2*(tx+3) +: 2])
        };
    end
    assign o_valid = valid[6];
endmodule

// Rank all four children of each surviving parent in one hardware stage.
// Static loop bounds elaborate into a bitonic compare/exchange network.
module kbest_row #(
    parameter int AXIS = 5, PARENTS = 1, KEEP = 4,
    parameter int IN_BITS = 16, COST_BITS = 25, R_SHIFT = 0, Z_SHIFT = 2
) (
    input logic clk, enable,
    input logic [20:0][IN_BITS-1:0] r,
    input logic [5:0][IN_BITS-1:0] z,
    input logic [PARENTS-1:0][COST_BITS-1:0] parent_cost,
    input logic [PARENTS-1:0][11:0] parent_path,
    output logic [KEEP-1:0][COST_BITS-1:0] kept_cost,
    output logic [KEEP-1:0][11:0] kept_path
);
    localparam int ROW_START = AXIS*(13-AXIS)/2;
    localparam int COUNT = PARENTS*4; // power of two at every layer
    localparam int ORDER_BITS = $clog2(COUNT);
    typedef logic signed [COST_BITS-1:0] accum_t;
    typedef struct packed {
        logic [COST_BITS-1:0] cost;
        logic [ORDER_BITS-1:0] order_id;
        logic [11:0] path;
    } candidate_t;

    function automatic accum_t term(input logic [IN_BITS-1:0] raw_r,
                                    input logic [1:0] symbol);
        accum_t a;
        a = accum_t'($signed(raw_r)) <<< R_SHIFT;
        case (symbol)
            0: return a + (a <<< 1);
            1: return a;
            2: return -a;
            default: return -(a + (a <<< 1));
        endcase
    endfunction

    candidate_t ranked [0:COUNT-1];
    always_comb begin
        candidate_t tmp;
        int other;
        tmp = '0;
        other = 0;
        for (int p = 0; p < PARENTS; p++) begin
            accum_t history;
            history = accum_t'($signed(z[AXIS])) <<< Z_SHIFT;
            for (int j = AXIS+1; j < 6; j++)
                history -= term(r[ROW_START+j-AXIS], parent_path[p][2*j +: 2]);
            for (int sym = 0; sym < 4; sym++) begin
                accum_t diff;
                diff = history - term(r[ROW_START], 2'(sym));
                ranked[4*p+sym].cost = parent_cost[p] + $unsigned(diff < 0 ? -diff : diff);
                ranked[4*p+sym].order_id = ORDER_BITS'(4*p+sym);
                ranked[4*p+sym].path = parent_path[p];
                ranked[4*p+sym].path[2*AXIS +: 2] = 2'(sym);
            end
        end
        // Unsigned packed comparison uses cost first, then parent/symbol order.
        for (int span = 2; span <= COUNT; span *= 2) begin
            for (int stride = span/2; stride > 0; stride /= 2) begin
                for (int i = 0; i < COUNT; i++) begin
                    other = i ^ stride;
                    if (other > i && (((i & span) == 0 && ranked[i] > ranked[other]) ||
                                      ((i & span) != 0 && ranked[i] < ranked[other]))) begin
                        tmp = ranked[i];
                        ranked[i] = ranked[other];
                        ranked[other] = tmp;
                    end
                end
            end
        end
    end

    for (genvar k = 0; k < KEEP; k++) begin : capture_winner
        always_ff @(posedge clk) begin
            if (enable) begin
                kept_cost[k] <= ranked[k].cost;
                kept_path[k] <= ranked[k].path;
            end
        end
    end
endmodule
