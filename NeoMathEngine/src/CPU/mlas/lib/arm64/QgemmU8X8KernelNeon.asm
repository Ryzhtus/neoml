/*++

Copyright (c) Microsoft Corporation. All rights reserved.

Licensed under the MIT License.

Module Name:

    QgemmU8X8KernelNeon.asm

Abstract:

    This module implements the kernels for the quantized integer matrix/matrix
    multiply operation (QGEMM).

--*/

#include "kxarm64.h"

//
// Stack frame layout for the U8X8 kernel.
//

#define GemmU8X8KernelFrame_ColumnSumBuffer         0
#define GemmU8X8KernelFrame_ZeroPointB              8
#define GemmU8X8KernelFrame_ZeroMode                16

//
// Define instruction aliases not implemented by ARMASM64.
//

        MACRO
        uxtl $DestReg, $SrcReg

        ushll   $DestReg.,$SrcReg.,#0

        MEND

        TEXTAREA

/*++

Routine Description:

    This routine is an inner kernel to compute matrix multiplication for a
    set of rows.

Arguments:

    A (x0) - Supplies the address of matrix A. The matrix data has been packed
        using MlasGemmU8X8CopyPackANeon.

    B (x1) - Supplies the address of matrix B. The matrix data has been packed
        using MlasGemmU8X8CopyPackBNeon.

    C (x2) - Supplies the address of matrix C.

    PackedCountK (x3) - Supplies the number of packed columns from matrix A and
        the number of packed rows from matrix B to iterate over.

    CountM (x4) - Supplies the maximum number of rows that can be processed for
        matrix A and matrix C. The actual number of rows handled for this
        invocation depends on the kernel implementation.

    CountN (x5) - Supplies the number of columns from matrix B and matrix C to
        iterate over.

    ldc (x6) - Supplies the first dimension of matrix C.

    RowSumBuffer (x7) - Supplies the sum of each row from matrix A multiplied by
        the zero point offset of matrix B. These values are accumulated into every
        row of matrix C.

    ColumnSumBuffer - Supplies the sum of each column from matrix B multiplied
        by the zero point offset of matrix A. These values are accumulated into
        every column of matrix C.

    ZeroMode - Supplies true if the output matrix must be zero initialized, else
        false if the output matrix is accumulated into.

Return Value:

    Returns the number of rows handled.

--*/

        LEAF_ENTRY MlasGemmU8X8KernelNeon

        ldr     x8,[sp,#GemmU8X8KernelFrame_ColumnSumBuffer]
        ldr     x9,[sp,#GemmU8X8KernelFrame_ZeroPointB]
        ldrb    w13,[sp,#GemmU8X8KernelFrame_ZeroMode]
        mov     x14,x0
        ld1     {v27.4s},[x7]
        mov     x15,x3
        dup     v24.4s,v27.s[0]             // broadcast row fixups
        cmp     x4,#1                       // CountM == 1?
        beq     ProcessNextColumnLoopM1
        dup     v25.4s,v27.s[1]
        cmp     x4,#4                       // CountM < 4?
        blo     ProcessNextColumnLoopM2
        dup     v26.4s,v27.s[2]
        dup     v27.4s,v27.s[3]

//
// Process 4 rows of the matrices.
//

ProcessNextColumnLoopM4
        ld1     {v0.8b},[x1],#8             // load packed B0
        mov     x0,x14                      // reload matrix A
        ld1     {v2.4s},[x8],#16            // load ColumnSumBuffer0
        mov     x3,x15                      // reload PackedCountK
        ld1     {v3.4s},[x8],#16            // load ColumnSumBuffer1
        uxtl    v0.8h,v0.8b
        cbz     x9,SkipScaleByZeroPointBM4
        ld1     {v28.4s},[x9],#16           // load ZeroPointB0
        ld1     {v29.4s},[x9],#16           // load ZeroPointB1
        mul     v16.4s,v24.4s,v28.4s
        mul     v17.4s,v24.4s,v29.4s
        mul     v18.4s,v25.4s,v28.4s
        mul     v19.4s,v25.4s,v29.4s
        mul     v20.4s,v26.4s,v28.4s
        mul     v21.4s,v26.4s,v29.4s
        mul     v22.4s,v27.4s,v28.4s
        mul     v23.4s,v27.4s,v29.4s
        ld1     {v4.8b},[x0],#8             // load first packed A0
        add     v16.4s,v2.4s,v16.4s
        add     v17.4s,v3.4s,v17.4s
        add     v18.4s,v2.4s,v18.4s
        add     v19.4s,v3.4s,v19.4s
        ld1     {v5.8b},[x0],#8             // load first packed A1
        add     v20.4s,v2.4s,v20.4s
        add     v21.4s,v3.4s,v21.4s
        add     v22.4s,v2.4s,v22.4s
        add     v23.4s,v3.4s,v23.4s
        b       ComputeBlockLoopM4

SkipScaleByZeroPointBM4
        ld1     {v4.8b},[x0],#8             // load first packed A0
        add     v16.4s,v2.4s,v24.4s
        add     v17.4s,v3.4s,v24.4s
        add     v18.4s,v2.4s,v25.4s
        add     v19.4s,v3.4s,v25.4s
        ld1     {v5.8b},[x0],#8             // load first packed A1
        add     v20.4s,v2.4s,v26.4s
        add     v21.4s,v3.4s,v26.4s
        add     v22.4s,v2.4s,v27.4s
        add     v23.4s,v3.4s,v27.4s

ComputeBlockLoopM4
        uxtl    v2.8h,v4.8b
        uxtl    v3.8h,v5.8b
        ld1     {v1.8b},[x1],#8             // load packed B1
        umlal   v16.4s,v0.4h,v2.h[0]
        umlal2  v17.4s,v0.8h,v2.h[0]
        umlal   v18.4s,v0.4h,v2.h[4]
        umlal2  v19.4s,v0.8h,v2.h[4]
        uxtl    v1.8h,v1.8b
        umlal   v20.4s,v0.4h,v3.h[0]
        umlal2  v21.4s,v0.8h,v3.h[0]
        umlal   v22.4s,v0.4h,v3.h[4]
        umlal2  v23.4s,v0.8h,v3.h[4]
        ld1     {v0.8b},[x1],#8             // load packed B2
        umlal   v16.4s,v1.4h,v2.h[1]
        umlal2  v17.4s,v1.8h,v2.h[1]
        umlal   v18.4s,v1.4h,v2.h[5]
        umlal2  v19.4s,v1.8h,v2.h[5]
        uxtl    v0.8h,v0.8b
        umlal   v20.4s,v1.4h,v3.h[1]
        umlal2  v21.4s,v1.8h,v3.h[1]
        umlal   v22.4s,v1.4h,v3.h[5]
        umlal2  v23.4s,v1.8h,v3.h[5]
        ld1     {v1.8b},[x1],#8             // load packed B3
        sub     x3,x3,#1
        cbz     x3,ComputeBlockLoopFinishM4
        umlal   v16.4s,v0.4h,v2.h[2]
        umlal2  v17.4s,v0.8h,v2.h[2]
        umlal   v18.4s,v0.4h,v2.h[6]
        umlal2  v19.4s,v0.8h,v2.h[6]
        uxtl    v1.8h,v1.8b
        ld1     {v4.8b},[x0],#8             // load next packed A0
        umlal   v20.4s,v0.4h,v3.h[2]
        umlal2  v21.4s,v0.8h,v3.h[2]
        umlal   v22.4s,v0.4h,v3.h[6]
        umlal2  v23.4s,v0.8h,v3.h[6]
        ld1     {v0.8b},[x1],#8             // load packed B0
        umlal   v16.4s,v1.4h,v2.h[3]
        umlal2  v17.4s,v1.8h,v2.h[3]
        umlal   v18.4s,v1.4h,v2.h[7]
        umlal2  v19.4s,v1.8h,v2.h[7]
        uxtl    v0.8h,v0.8b
        ld1     {v5.8b},[x0],#8             // load next packed A1
        umlal   v20.4s,v1.4h,v3.h[3]
        umlal2  v21.4s,v1.8h,v3.h[3]
        umlal   v22.4s,v1.4h,v3.h[7]
        umlal2  v23.4s,v1.8h,v3.h[7]
        b       ComputeBlockLoopM4

ComputeBlockLoopFinishM4
        umlal   v16.4s,v0.4h,v2.h[2]        // finish computing tail vectors
        umlal2  v17.4s,v0.8h,v2.h[2]
        add     x10,x2,x6,lsl #2            // compute output row 2
        umlal   v18.4s,v0.4h,v2.h[6]
        umlal2  v19.4s,v0.8h,v2.h[6]
        uxtl    v1.8h,v1.8b
        umlal   v20.4s,v0.4h,v3.h[2]
        umlal2  v21.4s,v0.8h,v3.h[2]
        umlal   v22.4s,v0.4h,v3.h[6]
        umlal2  v23.4s,v0.8h,v3.h[6]
        add     x11,x10,x6,lsl #2           // compute output row 3
        umlal   v16.4s,v1.4h,v2.h[3]
        umlal2  v17.4s,v1.8h,v2.h[3]
        umlal   v18.4s,v1.4h,v2.h[7]
        umlal2  v19.4s,v1.8h,v2.h[7]
        umlal   v20.4s,v1.4h,v3.h[3]
        umlal2  v21.4s,v1.8h,v3.h[3]
        add     x12,x11,x6,lsl #2           // compute output row 4
        umlal   v22.4s,v1.4h,v3.h[7]
        umlal2  v23.4s,v1.8h,v3.h[7]
        subs    x5,x5,#8                    // adjust CountN remaining
        blo     StoreOutputPartialM4
        cbnz    x13,SkipAccumulateOutputM4
        ldp     q0,q1,[x2]
        ldp     q2,q3,[x10]
        add     v16.4s,v16.4s,v0.4s
        add     v17.4s,v17.4s,v1.4s
        ldp     q4,q5,[x11]
        add     v18.4s,v18.4s,v2.4s
        add     v19.4s,v19.4s,v3.4s
        ldp     q6,q7,[x12]
        add     v20.4s,v20.4s,v4.4s
        add     v21.4s,v21.4s,v5.4s
        add     v22.4s,v22.4s,v6.4s
        add     v23.4s,v23.4s,v7.4s

SkipAccumulateOutputM4
        stp     q16,q17,[x2],#32
        stp     q18,q19,[x10]
        stp     q20,q21,[x11]
        stp     q22,q23,[x12]
        cbnz    x5,ProcessNextColumnLoopM4

ExitKernelM4
        mov     x0,#4                       // return number of rows handled
        ret

//
// Store the partial 1 to 7 columns either overwriting the output matrix or
// accumulating into the existing contents of the output matrix.
//

StoreOutputPartialM4
        cbz     x13,StoreOutputPartialAddModeM4

StoreOutputPartialZeroModeM4
        tbz     x5,#2,StoreOutputPartial2ZeroModeM4
        st1     {v16.4s},[x2],#16
        mov     v16.16b,v17.16b             // shift remaining elements down
        st1     {v18.4s},[x10],#16
        mov     v18.16b,v19.16b
        st1     {v20.4s},[x11],#16
        mov     v20.16b,v21.16b
        st1     {v22.4s},[x12],#16
        mov     v22.16b,v23.16b

StoreOutputPartial2ZeroModeM4
        tbz     x5,#1,StoreOutputPartial1ZeroModeM4
        st1     {v16.2s},[x2],#8
        dup     v16.4s,v16.s[2]             // shift remaining elements down
        st1     {v18.2s},[x10],#8
        dup     v18.4s,v18.s[2]
        st1     {v20.2s},[x11],#8
        dup     v20.4s,v20.s[2]
        st1     {v22.2s},[x12],#8
        dup     v22.4s,v22.s[2]

StoreOutputPartial1ZeroModeM4
        tbz     x5,#0,ExitKernelM4
        st1     {v16.s}[0],[x2]
        st1     {v18.s}[0],[x10]
        st1     {v20.s}[0],[x11]
        st1     {v22.s}[0],[x12]
        b       ExitKernelM4

StoreOutputPartialAddModeM4
        tbz     x5,#2,StoreOutputPartial2AddModeM4
        ld1     {v0.4s},[x2]
        ld1     {v1.4s},[x10]
        ld1     {v2.4s},[x11]
        ld1     {v3.4s},[x12]
        add     v16.4s,v16.4s,v0.4s
        add     v18.4s,v18.4s,v1.4s
        st1     {v16.4s},[x2],#16
        mov     v16.16b,v17.16b             // shift remaining elements down
        st1     {v18.4s},[x10],#16
        mov     v18.16b,v19.16b
        add     v20.4s,v20.4s,v2.4s
        add     v22.4s,v22.4s,v3.4s
        st1     {v20.4s},[x11],#16
        mov     v20.16b,v21.16b
        st1     {v22.4s},[x12],#16
        mov     v22.16b,v23.16b

StoreOutputPartial2AddModeM4
        tbz     x5,#1,StoreOutputPartial1AddModeM4
        ld1     {v0.2s},[x2]
        ld1     {v1.2s},[x10]
        ld1     {v2.2s},[x11]
        ld1     {v3.2s},[x12]
        add     v16.4s,v16.4s,v0.4s
        add     v18.4s,v18.4s,v1.4s
        st1     {v16.2s},[x2],#8
        dup     v16.4s,v16.s[2]             // shift remaining elements down
        st1     {v18.2s},[x10],#8
        dup     v18.4s,v18.s[2]
        add     v20.4s,v20.4s,v2.4s
        add     v22.4s,v22.4s,v3.4s
        st1     {v20.2s},[x11],#8
        dup     v20.4s,v20.s[2]
        st1     {v22.2s},[x12],#8
        dup     v22.4s,v22.s[2]

StoreOutputPartial1AddModeM4
        tbz     x5,#0,ExitKernelM4
        ld1     {v0.s}[0],[x2]
        ld1     {v1.s}[0],[x10]
        add     v16.4s,v16.4s,v0.4s
        ld1     {v2.s}[0],[x11]
        add     v18.4s,v18.4s,v1.4s
        ld1     {v3.s}[0],[x12]
        add     v20.4s,v20.4s,v2.4s
        st1     {v16.s}[0],[x2]
        st1     {v18.s}[0],[x10]
        add     v22.4s,v22.4s,v3.4s
        st1     {v20.s}[0],[x11]
        st1     {v22.s}[0],[x12]
        b       ExitKernelM4

//
// Process 2 rows of the matrices.
//

ProcessNextColumnLoopM2
        ld1     {v0.8b},[x1],#8             // load packed B0
        mov     x0,x14                      // reload matrix A
        ld1     {v2.4s},[x8],#16            // load ColumnSumBuffer0
        mov     x3,x15                      // reload PackedCountK
        ld1     {v3.4s},[x8],#16            // load ColumnSumBuffer1
        uxtl    v0.8h,v0.8b
        cbz     x9,SkipScaleByZeroPointBM2
        ld1     {v28.4s},[x9],#16           // load ZeroPointB0
        ld1     {v29.4s},[x9],#16           // load ZeroPointB1
        mul     v16.4s,v24.4s,v28.4s
        mul     v17.4s,v24.4s,v29.4s
        mul     v18.4s,v25.4s,v28.4s
        mul     v19.4s,v25.4s,v29.4s
        ld1     {v4.8b},[x0],#8             // load first packed A0
        add     v16.4s,v2.4s,v16.4s
        add     v17.4s,v3.4s,v17.4s
        add     v18.4s,v2.4s,v18.4s
        add     v19.4s,v3.4s,v19.4s
        b       ComputeBlockLoopM2

SkipScaleByZeroPointBM2
        ld1     {v4.8b},[x0],#8             // load first packed A0
        add     v16.4s,v2.4s,v24.4s
        add     v17.4s,v3.4s,v24.4s
        add     v18.4s,v2.4s,v25.4s
        add     v19.4s,v3.4s,v25.4s

ComputeBlockLoopM2
        uxtl    v2.8h,v4.8b
        ld1     {v1.8b},[x1],#8             // load packed B1
        umlal   v16.4s,v0.4h,v2.h[0]
        umlal2  v17.4s,v0.8h,v2.h[0]
        umlal   v18.4s,v0.4h,v2.h[4]
        umlal2  v19.4s,v0.8h,v2.h[4]
        uxtl    v1.8h,v1.8b
        ld1     {v0.8b},[x1],#8             // load packed B2
        umlal   v16.4s,v1.4h,v2.h[1]
        umlal2  v17.4s,v1.8h,v2.h[1]
        umlal   v18.4s,v1.4h,v2.h[5]
        umlal2  v19.4s,v1.8h,v2.h[5]
        uxtl    v0.8h,v0.8b
        ld1     {v1.8b},[x1],#8             // load packed B3
        sub     x3,x3,#1
        cbz     x3,ComputeBlockLoopFinishM2
        umlal   v16.4s,v0.4h,v2.h[2]
        umlal2  v17.4s,v0.8h,v2.h[2]
        umlal   v18.4s,v0.4h,v2.h[6]
        umlal2  v19.4s,v0.8h,v2.h[6]
        uxtl    v1.8h,v1.8b
        ld1     {v4.8b},[x0],#8             // load next packed A0
        ld1     {v0.8b},[x1],#8             // load packed B0
        umlal   v16.4s,v1.4h,v2.h[3]
        umlal2  v17.4s,v1.8h,v2.h[3]
        umlal   v18.4s,v1.4h,v2.h[7]
        umlal2  v19.4s,v1.8h,v2.h[7]
        uxtl    v0.8h,v0.8b
        b       ComputeBlockLoopM2

ComputeBlockLoopFinishM2
        umlal   v16.4s,v0.4h,v2.h[2]        // finish computing tail vectors
        umlal2  v17.4s,v0.8h,v2.h[2]
        add     x10,x2,x6,lsl #2            // compute output row 2
        umlal   v18.4s,v0.4h,v2.h[6]
        umlal2  v19.4s,v0.8h,v2.h[6]
        uxtl    v1.8h,v1.8b
        umlal   v16.4s,v1.4h,v2.h[3]
        umlal2  v17.4s,v1.8h,v2.h[3]
        umlal   v18.4s,v1.4h,v2.h[7]
        umlal2  v19.4s,v1.8h,v2.h[7]
        subs    x5,x5,#8                    // adjust CountN remaining
        blo     StoreOutputPartialM2
        cbnz    x13,SkipAccumulateOutputM2
        ldp     q0,q1,[x2]
        ldp     q2,q3,[x10]
        add     v16.4s,v16.4s,v0.4s
        add     v17.4s,v17.4s,v1.4s
        add     v18.4s,v18.4s,v2.4s
        add     v19.4s,v19.4s,v3.4s

SkipAccumulateOutputM2
        stp     q16,q17,[x2],#32
        stp     q18,q19,[x10]
        cbnz    x5,ProcessNextColumnLoopM2

ExitKernelM2
        mov     x0,#2                       // return number of rows handled
        ret

//
// Store the partial 1 to 7 columns either overwriting the output matrix or
// accumulating into the existing contents of the output matrix.
//

StoreOutputPartialM2
        cbz     x13,StoreOutputPartialAddModeM2

StoreOutputPartialZeroModeM2
        tbz     x5,#2,StoreOutputPartial2ZeroModeM2
        st1     {v16.4s},[x2],#16
        mov     v16.16b,v17.16b             // shift remaining elements down
        st1     {v18.4s},[x10],#16
        mov     v18.16b,v19.16b

StoreOutputPartial2ZeroModeM2
        tbz     x5,#1,StoreOutputPartial1ZeroModeM2
        st1     {v16.2s},[x2],#8
        dup     v16.4s,v16.s[2]             // shift remaining elements down
        st1     {v18.2s},[x10],#8
        dup     v18.4s,v18.s[2]

StoreOutputPartial1ZeroModeM2
        tbz     x5,#0,ExitKernelM2
        st1     {v16.s}[0],[x2]
        st1     {v18.s}[0],[x10]
        b       ExitKernelM2

StoreOutputPartialAddModeM2
        tbz     x5,#2,StoreOutputPartial2AddModeM2
        ld1     {v0.4s},[x2]
        ld1     {v1.4s},[x10]
        add     v16.4s,v16.4s,v0.4s
        add     v18.4s,v18.4s,v1.4s
        st1     {v16.4s},[x2],#16
        mov     v16.16b,v17.16b             // shift remaining elements down
        st1     {v18.4s},[x10],#16
        mov     v18.16b,v19.16b

StoreOutputPartial2AddModeM2
        tbz     x5,#1,StoreOutputPartial1AddModeM2
        ld1     {v0.2s},[x2]
        ld1     {v1.2s},[x10]
        add     v16.4s,v16.4s,v0.4s
        add     v18.4s,v18.4s,v1.4s
        st1     {v16.2s},[x2],#8
        dup     v16.4s,v16.s[2]             // shift remaining elements down
        st1     {v18.2s},[x10],#8
        dup     v18.4s,v18.s[2]

StoreOutputPartial1AddModeM2
        tbz     x5,#0,ExitKernelM2
        ld1     {v0.s}[0],[x2]
        ld1     {v1.s}[0],[x10]
        add     v16.4s,v16.4s,v0.4s
        add     v18.4s,v18.4s,v1.4s
        st1     {v16.s}[0],[x2]
        st1     {v18.s}[0],[x10]
        b       ExitKernelM2

//
// Process 1 row of the matrices.
//

ProcessNextColumnLoopM1
        ld1     {v0.8b},[x1],#8             // load packed B0
        mov     x0,x14                      // reload matrix A
        ld1     {v2.4s},[x8],#16            // load ColumnSumBuffer0
        mov     x3,x15                      // reload PackedCountK
        ld1     {v3.4s},[x8],#16            // load ColumnSumBuffer1
        uxtl    v0.8h,v0.8b
        cbz     x9,SkipScaleByZeroPointBM1
        ld1     {v28.4s},[x9],#16           // load ZeroPointB0
        ld1     {v29.4s},[x9],#16           // load ZeroPointB1
        mul     v16.4s,v24.4s,v28.4s
        mul     v17.4s,v24.4s,v29.4s
        ldr     s4,[x0],#4                  // load first packed A0
        add     v16.4s,v2.4s,v16.4s
        add     v17.4s,v3.4s,v17.4s
        b       ComputeBlockLoopM1

SkipScaleByZeroPointBM1
        ldr     s4,[x0],#4                  // load first packed A0
        add     v16.4s,v2.4s,v24.4s
        add     v17.4s,v3.4s,v24.4s

ComputeBlockLoopM1
        uxtl    v2.8h,v4.8b
        ld1     {v1.8b},[x1],#8             // load packed B1
        umlal   v16.4s,v0.4h,v2.h[0]
        umlal2  v17.4s,v0.8h,v2.h[0]
        uxtl    v1.8h,v1.8b
        ld1     {v0.8b},[x1],#8             // load packed B2
        umlal   v16.4s,v1.4h,v2.h[1]
        umlal2  v17.4s,v1.8h,v2.h[1]
        uxtl    v0.8h,v0.8b
        ld1     {v1.8b},[x1],#8             // load packed B3
        sub     x3,x3,#1
        cbz     x3,ComputeBlockLoopFinishM1
        umlal   v16.4s,v0.4h,v2.h[2]
        umlal2  v17.4s,v0.8h,v2.h[2]
        uxtl    v1.8h,v1.8b
        ldr     s4,[x0],#4                  // load first packed A0
        ld1     {v0.8b},[x1],#8             // load packed B0
        umlal   v16.4s,v1.4h,v2.h[3]
        umlal2  v17.4s,v1.8h,v2.h[3]
        uxtl    v0.8h,v0.8b
        b       ComputeBlockLoopM1

ComputeBlockLoopFinishM1
        umlal   v16.4s,v0.4h,v2.h[2]        // finish computing tail vectors
        umlal2  v17.4s,v0.8h,v2.h[2]
        uxtl    v1.8h,v1.8b
        umlal   v16.4s,v1.4h,v2.h[3]
        umlal2  v17.4s,v1.8h,v2.h[3]
        subs    x5,x5,#8                    // adjust CountN remaining
        blo     StoreOutputPartialM1
        cbnz    x13,SkipAccumulateOutputM1
        ldp     q0,q1,[x2]
        add     v16.4s,v16.4s,v0.4s
        add     v17.4s,v17.4s,v1.4s

SkipAccumulateOutputM1
        stp     q16,q17,[x2],#32
        cbnz    x5,ProcessNextColumnLoopM1

ExitKernelM1
        mov     x0,#1                       // return number of rows handled
        ret

//
// Store the partial 1 to 7 columns either overwriting the output matrix or
// accumulating into the existing contents of the output matrix.
//

StoreOutputPartialM1
        cbz     x13,StoreOutputPartialAddModeM1

StoreOutputPartialZeroModeM1
        tbz     x5,#2,StoreOutputPartial2ZeroModeM1
        st1     {v16.4s},[x2],#16
        mov     v16.16b,v17.16b             // shift remaining elements down

StoreOutputPartial2ZeroModeM1
        tbz     x5,#1,StoreOutputPartial1ZeroModeM1
        st1     {v16.2s},[x2],#8
        dup     v16.4s,v16.s[2]             // shift remaining elements down

StoreOutputPartial1ZeroModeM1
        tbz     x5,#0,ExitKernelM1
        st1     {v16.s}[0],[x2]
        b       ExitKernelM1

StoreOutputPartialAddModeM1
        tbz     x5,#2,StoreOutputPartial2AddModeM1
        ld1     {v0.4s},[x2]
        add     v16.4s,v16.4s,v0.4s
        st1     {v16.4s},[x2],#16
        mov     v16.16b,v17.16b             // shift remaining elements down

StoreOutputPartial2AddModeM1
        tbz     x5,#1,StoreOutputPartial1AddModeM1
        ld1     {v0.2s},[x2]
        add     v16.4s,v16.4s,v0.4s
        st1     {v16.2s},[x2],#8
        dup     v16.4s,v16.s[2]             // shift remaining elements down

StoreOutputPartial1AddModeM1
        tbz     x5,#0,ExitKernelM1
        ld1     {v0.s}[0],[x2]
        add     v16.4s,v16.4s,v0.4s
        st1     {v16.s}[0],[x2]
        b       ExitKernelM1

        LEAF_END MlasGemmU8X8KernelNeon

        END
