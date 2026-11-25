// matvec.c — CPU matrix-vector kernels. See matvec.h.
#include "matvec.h"

#include <math.h>

void matvec_f32(float *y, const float *W, const float *x, int rows, int cols) {
    for (int r = 0; r < rows; r++) {
        const float *w_row = W + (long)r * cols;
        float sum = 0.0f;
        for (int c = 0; c < cols; c++) sum += w_row[c] * x[c];
        y[r] = sum;
    }
}

void matvec_int8_ref(int32_t *y, const int8_t *W, const int8_t *x, int rows, int cols) {
    for (int r = 0; r < rows; r++) {
        const int8_t *w_row = W + (long)r * cols;
        int32_t acc = 0;  // matches the 32-bit accumulator in the RTL
        for (int c = 0; c < cols; c++) acc += (int32_t)w_row[c] * (int32_t)x[c];
        y[r] = acc;
    }
}

float quantize_symmetric_int8(int8_t *out, const float *in, int n) {
    float max_abs = 0.0f;
    for (int i = 0; i < n; i++) {
        float a = fabsf(in[i]);
        if (a > max_abs) max_abs = a;
    }
    // Map [-max_abs, +max_abs] onto [-127, +127]. (We skip -128 so the range is
    // symmetric and negation can never overflow.)
    float scale = (max_abs > 0.0f) ? max_abs / 127.0f : 1.0f;
    for (int i = 0; i < n; i++) {
        float q = roundf(in[i] / scale);
        if (q > 127.0f) q = 127.0f;
        if (q < -127.0f) q = -127.0f;
        out[i] = (int8_t)q;
    }
    return scale;
}

void dequantize_int32(float *out, const int32_t *in, float scale, int n) {
    for (int i = 0; i < n; i++) out[i] = (float)in[i] * scale;
}
