// =============================================================================
// tb_matvec_int8.sv — self-checking testbench for matvec_int8
//
// Run:  cd hw/tb && make          (needs Verilator >= 5.0 for --timing)
//
// What it checks
//   * Random int8 W (ROWS × COLS) and x (COLS), including extreme values (-128/127).
//   * Expected y is computed in the testbench with plain integer math (the
//     "golden model") and compared against every DUT result.
//   * Random stalls on BOTH sides: w_valid randomly drops (upstream DMA hiccup)
//     and y_ready randomly drops (downstream not ready). Handshake bugs usually
//     only show up under backpressure, so we always test with it.
// =============================================================================
`timescale 1ns/1ps

module tb_matvec_int8;

    // ---- Test configuration ----
    localparam int LANES         = 8;
    localparam int ELEM_W        = 8;
    localparam int ACC_W         = 32;
    localparam int MAX_COL_WORDS = 64;
    localparam int ROWS          = 16;
    localparam int COL_WORDS     = 6;               // cols / LANES
    localparam int COLS          = COL_WORDS * LANES;
    localparam real CLK_PERIOD_NS = 10.0;           // 100 MHz, just for waveforms

    // ---- DUT signals ----
    logic clk = 1'b0;
    logic rst_n;
    logic [$clog2(MAX_COL_WORDS):0]     cfg_col_words;
    logic                               act_wr_en;
    logic [$clog2(MAX_COL_WORDS)-1:0]   act_wr_addr;
    logic [LANES*ELEM_W-1:0]            act_wr_data;
    logic                               w_valid, w_ready;
    logic [LANES*ELEM_W-1:0]            w_data;
    logic                               y_valid, y_ready;
    logic signed [ACC_W-1:0]            y_data;

    always #(CLK_PERIOD_NS/2) clk = ~clk;

    matvec_int8 #(
        .LANES(LANES), .ELEM_W(ELEM_W), .ACC_W(ACC_W), .MAX_COL_WORDS(MAX_COL_WORDS)
    ) dut (.*);

    // ---- Test data + golden model ----
    logic signed [7:0]  W [ROWS][COLS];
    logic signed [7:0]  x [COLS];
    int                 y_expected [ROWS];

    function automatic logic signed [7:0] rand_int8(int r, int c);
        // Sprinkle in the extremes so overflow / sign-extension bugs surface.
        if (r == 0 && c == 0) return 8'sh80;   // -128
        if (r == 0 && c == 1) return 8'sh7F;   //  127
        return 8'($urandom_range(0, 255));
    endfunction

    task automatic build_test_vectors();
        for (int c = 0; c < COLS; c++) x[c] = rand_int8(1, c + 2);
        for (int r = 0; r < ROWS; r++) begin
            y_expected[r] = 0;
            for (int c = 0; c < COLS; c++) begin
                W[r][c] = rand_int8(r, c);
                y_expected[r] += int'(W[r][c]) * int'(x[c]);
            end
        end
    endtask

    // ---- Driver: load activations, then stream weights with random gaps ----
    task automatic load_activations();
        for (int word = 0; word < COL_WORDS; word++) begin
            @(posedge clk);
            act_wr_en   <= 1'b1;
            act_wr_addr <= word[$clog2(MAX_COL_WORDS)-1:0];
            for (int lane = 0; lane < LANES; lane++)
                act_wr_data[lane*ELEM_W +: ELEM_W] <= x[word*LANES + lane];
        end
        @(posedge clk);
        act_wr_en <= 1'b0;
    endtask

    task automatic stream_weights();
        for (int r = 0; r < ROWS; r++) begin
            for (int word = 0; word < COL_WORDS; word++) begin
                // Random idle cycles before presenting this beat.
                while ($urandom_range(0, 3) == 0) begin
                    w_valid <= 1'b0;
                    @(posedge clk);
                end
                w_valid <= 1'b1;
                for (int lane = 0; lane < LANES; lane++)
                    w_data[lane*ELEM_W +: ELEM_W] <= W[r][word*LANES + lane];
                // Hold the beat until the DUT accepts it (valid/ready rule:
                // once valid is high, data must stay stable until ready).
                do @(posedge clk); while (!w_ready);
            end
        end
        w_valid <= 1'b0;
    endtask

    // ---- Monitor: randomly backpressure y and check each result ----
    int results_seen = 0;
    int errors       = 0;

    always @(posedge clk) begin
        if (rst_n) begin
            y_ready <= ($urandom_range(0, 2) != 0);   // ready ~2/3 of the time
            if (y_valid && y_ready) begin
                if (y_data !== y_expected[results_seen]) begin
                    $display("FAIL row %0d: got %0d, expected %0d",
                             results_seen, y_data, y_expected[results_seen]);
                    errors++;
                end
                results_seen++;
            end
        end
    end

    // ---- Main sequence ----
    initial begin
        if ($test$plusargs("trace")) begin
            $dumpfile("tb_matvec_int8.vcd");
            $dumpvars(0, tb_matvec_int8);
        end

        rst_n         = 1'b0;
        act_wr_en     = 1'b0;
        act_wr_addr   = '0;
        act_wr_data   = '0;
        w_valid       = 1'b0;
        w_data        = '0;
        y_ready       = 1'b0;
        cfg_col_words = COL_WORDS;

        build_test_vectors();
        repeat (4) @(posedge clk);
        rst_n <= 1'b1;

        load_activations();
        stream_weights();

        // Wait for all results (with a timeout so a hang fails loudly).
        fork
            wait (results_seen == ROWS);
            begin
                repeat (10_000) @(posedge clk);
                $fatal(1, "TIMEOUT: only %0d of %0d results seen", results_seen, ROWS);
            end
        join_any
        disable fork;

        if (errors == 0) $display("PASS: %0d rows x %0d cols matched golden model", ROWS, COLS);
        else             $fatal(1, "FAILED with %0d mismatches", errors);
        $finish;
    end

endmodule
