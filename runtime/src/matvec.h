// matvec.h — CPU matrix-vector kernels.
//
// These serve two purposes:
//   1. A working CPU fallback, so the runtime can run before the FPGA engine exists.
//   2. A *golden reference* for the RTL: matvec_int8_ref() uses exactly the same
//      math as hw/rtl/matvec_int8.sv (int8 × int8, int32 accumulate, row-major W).
//      Later, FPGA results get compared against it bit-for-bit.
#ifndef KVLLM_MATVEC_H
#define KVLLM_MATVEC_H

#include <stdint.h>

// y[rows] = W[rows][cols] · x[cols], all fp32. Same as llama2.c's matmul().
void matvec_f32(float *y, const float *W, const float *x, int rows, int cols);

// y[rows] = W[rows][cols] · x[cols] with int8 inputs and int32 accumulation.
// Matches the hardware engine's arithmetic exactly (no scaling / dequant here).
void matvec_int8_ref(int32_t *y, const int8_t *W, const int8_t *x, int rows, int cols);

// Symmetric per-tensor quantization helpers (a starting point; per-group
// scales, like llama2.c's runq.c, come later).
float quantize_symmetric_int8(int8_t *out, const float *in, int n);  // returns scale
void  dequantize_int32(float *out, const int32_t *in, float scale, int n);

#endif
