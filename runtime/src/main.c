// main.c — runtime entry point (starter).
//
// For now this just self-tests the CPU kernels: it quantizes a random fp32
// matrix + vector to int8, runs the int8 reference matvec, dequantizes, and
// checks the result against the fp32 matvec. This is the same flow the FPGA
// path will use (quantize on the host -> int8 matvec in fabric -> dequantize).
//
// TODO (Phase 1): pull in llama2.c's model loading, tokenizer, and forward pass,
// and route matmul() through a backend switch (CPU vs FPGA).
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "matvec.h"

#define ROWS 64
#define COLS 256

static float rand_uniform(void) { return (float)rand() / (float)RAND_MAX * 2.0f - 1.0f; }

int main(void) {
    static float  W_f32[ROWS * COLS], x_f32[COLS], y_f32[ROWS], y_deq[ROWS];
    static int8_t W_q[ROWS * COLS], x_q[COLS];
    static int32_t y_q[ROWS];

    srand(42);  // fixed seed: reproducible output
    for (int i = 0; i < ROWS * COLS; i++) W_f32[i] = rand_uniform();
    for (int i = 0; i < COLS; i++) x_f32[i] = rand_uniform();

    // fp32 reference
    matvec_f32(y_f32, W_f32, x_f32, ROWS, COLS);

    // int8 path: quantize both operands, integer matvec, then rescale.
    // (s_w * q_w) · (s_x * q_x) = s_w * s_x * (q_w · q_x), so one multiply by
    // s_w*s_x after the integer dot product recovers the real-valued result.
    float scale_w = quantize_symmetric_int8(W_q, W_f32, ROWS * COLS);
    float scale_x = quantize_symmetric_int8(x_q, x_f32, COLS);
    matvec_int8_ref(y_q, W_q, x_q, ROWS, COLS);
    dequantize_int32(y_deq, y_q, scale_w * scale_x, ROWS);

    // Compare. int8 quantization adds error, so we report relative RMS error
    // instead of expecting an exact match.
    double err_sq = 0.0, ref_sq = 0.0;
    for (int r = 0; r < ROWS; r++) {
        double d = (double)y_deq[r] - (double)y_f32[r];
        err_sq += d * d;
        ref_sq += (double)y_f32[r] * (double)y_f32[r];
    }
    double rel_rms = sqrt(err_sq / ref_sq);

    printf("matvec self-test: %dx%d, int8 vs fp32 relative RMS error = %.4f%%\n", ROWS, COLS,
           rel_rms * 100.0);
    if (rel_rms > 0.05) {  // generous bound for per-tensor int8 on random data
        fprintf(stderr, "FAIL: error too large\n");
        return 1;
    }
    printf("PASS\n");
    return 0;
}
