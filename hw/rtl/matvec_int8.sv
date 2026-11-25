// =============================================================================
// matvec_int8.sv — starter int8 matrix-vector engine:  y = W · x
//
// STATUS: starter / learning code. Simulation-only so far; not yet synthesized,
// timing-closed, or wired to AXI. Expect this to change a lot.
//
// What it does
// ------------
//   * The activation vector x (int8) is loaded once into an on-chip RAM through a
//     simple write port. At batch 1, x is reused by *every* row of W, so it's
//     worth keeping on-chip.
//   * Weights W (int8) stream in row-major order, LANES bytes per beat, over a
//     valid/ready handshake. Each weight is used exactly once per token, so they
//     are never stored — they flow straight from DDR (later: AXI DMA) into the MACs.
//   * For each beat: LANES parallel int8×int8 multiplies, summed (an adder tree),
//     then added into a 32-bit accumulator. After the last beat of a row, the
//     accumulated int32 dot product is emitted on the y stream.
//
// Pipeline (one beat per cycle when not stalled)
//   S1: accept weight beat, register it; read x[col] from activation RAM
//       (block RAM reads are *synchronous*: data appears one clock later,
//        which lines up with the registered weight beat)
//   S2: LANES multiplies + adder tree -> registered partial dot product
//   S3: accumulate; on the last beat of the row, latch result into y_data
//
// Known simplification: after the last beat of a row is accepted, w_ready drops
// until that row's result has been taken. That costs a few bubble cycles per row.
// Fine for a starter; fixable later with a small output FIFO.
// =============================================================================
module matvec_int8 #(
    parameter int LANES       = 8,     // int8 elements per weight beat (= DSPs used, roughly)
    parameter int ELEM_W      = 8,     // bits per weight / activation element
    parameter int ACC_W       = 32,    // accumulator width (int8*int8 sums need ~16 + log2(cols) bits)
    parameter int MAX_COL_WORDS = 512  // activation RAM depth, in LANES-wide words (512*8 = 4096 cols)
) (
    input  logic                         clk,
    input  logic                         rst_n,          // active-low synchronous reset

    // ---- Configuration (hold stable while a matvec is running) ----
    // Number of LANES-wide words per row, i.e. cols / LANES. Must be >= 1.
    input  logic [$clog2(MAX_COL_WORDS):0] cfg_col_words,

    // ---- Activation load port (write x into on-chip RAM before streaming W) ----
    input  logic                              act_wr_en,
    input  logic [$clog2(MAX_COL_WORDS)-1:0]  act_wr_addr,
    input  logic [LANES*ELEM_W-1:0]           act_wr_data,

    // ---- Weight input stream (row-major, LANES elements per beat) ----
    input  logic                         w_valid,
    output logic                         w_ready,
    input  logic [LANES*ELEM_W-1:0]      w_data,

    // ---- Result output stream (one int32 per row) ----
    output logic                         y_valid,
    input  logic                         y_ready,
    output logic signed [ACC_W-1:0]      y_data
);

    localparam int ADDR_W    = $clog2(MAX_COL_WORDS);
    localparam int PRODUCT_W = 2 * ELEM_W;                    // int8*int8 -> 16 bits
    localparam int DOT_W     = PRODUCT_W + $clog2(LANES) + 1; // sum of LANES products, no overflow

    // -------------------------------------------------------------------------
    // Activation RAM: one write port, one read port ("simple dual-port").
    // Writing in one always_ff and reading in another with a registered output
    // is the coding pattern Vivado recognizes and maps onto block RAM.
    // -------------------------------------------------------------------------
    logic [LANES*ELEM_W-1:0] act_mem [MAX_COL_WORDS];
    logic [LANES*ELEM_W-1:0] act_rd_data;

    always_ff @(posedge clk) begin : act_ram_write
        if (act_wr_en)
            act_mem[act_wr_addr] <= act_wr_data;
    end

    // -------------------------------------------------------------------------
    // Input handshake + column counter
    // -------------------------------------------------------------------------
    logic             w_fire;          // a weight beat is transferred this cycle
    logic [ADDR_W:0]  col_idx;         // which LANES-wide word of the row we're on
    logic             is_first_beat;   // col_idx == 0
    logic             is_last_beat;    // col_idx == cfg_col_words - 1
    logic             row_draining;    // last beat accepted; waiting for y to be taken

    assign w_ready       = !row_draining;
    assign w_fire        = w_valid && w_ready;
    assign is_first_beat = (col_idx == '0);
    assign is_last_beat  = (col_idx == cfg_col_words - 1'b1);

    always_ff @(posedge clk) begin : column_counter
        if (!rst_n)
            col_idx <= '0;
        else if (w_fire)
            col_idx <= is_last_beat ? '0 : col_idx + 1'b1;
    end

    // -------------------------------------------------------------------------
    // S1: register the weight beat; read the matching activation word.
    // -------------------------------------------------------------------------
    logic [LANES*ELEM_W-1:0] s1_weights;
    logic                    s1_valid, s1_first, s1_last;

    always_ff @(posedge clk) begin : act_ram_read
        if (w_fire)
            act_rd_data <= act_mem[col_idx[ADDR_W-1:0]];
    end

    always_ff @(posedge clk) begin : stage1_regs
        if (!rst_n) begin
            s1_valid <= 1'b0;
        end else begin
            s1_valid <= w_fire;
        end
        if (w_fire) begin
            s1_weights <= w_data;
            s1_first   <= is_first_beat;
            s1_last    <= is_last_beat;
        end
    end

    // -------------------------------------------------------------------------
    // S2: LANES signed multiplies + adder tree.
    // Each int8×int8 multiply should map onto one DSP48E2 slice (27×18 multiplier).
    // -------------------------------------------------------------------------
    logic signed [DOT_W-1:0] dot_comb;
    logic signed [DOT_W-1:0] s2_dot;
    logic                    s2_valid, s2_first, s2_last;

    always_comb begin : lane_multiply_and_sum
        dot_comb = '0;
        for (int lane = 0; lane < LANES; lane++) begin
            logic signed [ELEM_W-1:0] w_elem, x_elem;
            w_elem = s1_weights [lane*ELEM_W +: ELEM_W];
            x_elem = act_rd_data[lane*ELEM_W +: ELEM_W];
            dot_comb = dot_comb + DOT_W'(w_elem * x_elem);
        end
    end

    always_ff @(posedge clk) begin : stage2_regs
        if (!rst_n) begin
            s2_valid <= 1'b0;
        end else begin
            s2_valid <= s1_valid;
        end
        if (s1_valid) begin
            s2_dot   <= dot_comb;
            s2_first <= s1_first;
            s2_last  <= s1_last;
        end
    end

    // -------------------------------------------------------------------------
    // S3: accumulate across the row. The first beat *loads* the accumulator
    // (instead of clearing it in a separate cycle), so rows can go back-to-back.
    // -------------------------------------------------------------------------
    logic signed [ACC_W-1:0] acc;
    logic signed [ACC_W-1:0] acc_next;

    assign acc_next = s2_first ? ACC_W'(s2_dot) : acc + ACC_W'(s2_dot);

    always_ff @(posedge clk) begin : accumulator
        if (!rst_n)
            acc <= '0;
        else if (s2_valid)
            acc <= acc_next;
    end

    // -------------------------------------------------------------------------
    // Output register + draining flag.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin : output_stream
        if (!rst_n) begin
            y_valid <= 1'b0;
            y_data  <= '0;
        end else if (s2_valid && s2_last) begin
            y_valid <= 1'b1;
            y_data  <= acc_next;
        end else if (y_valid && y_ready) begin
            y_valid <= 1'b0;
        end
    end

    always_ff @(posedge clk) begin : drain_control
        if (!rst_n)
            row_draining <= 1'b0;
        else if (w_fire && is_last_beat)
            row_draining <= 1'b1;
        else if (y_valid && y_ready)
            row_draining <= 1'b0;
    end

endmodule
