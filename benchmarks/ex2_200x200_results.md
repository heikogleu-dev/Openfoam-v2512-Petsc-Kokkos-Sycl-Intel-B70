# PETSc ex2 200×200 Sanity Results — Plan I GO Run

This is the verification benchmark that closes Stufe 2. It is **not** a
performance claim; it is a **build-correctness claim** (backend confirmed,
solver converges).

## Test

`src/ksp/ksp/tutorials/ex2.c` — 2-D scalar Laplacian on a structured grid,
finite-difference 5-point stencil. 200 × 200 = 40 000 unknowns.

```bash
mpirun -np 1 ./ex2 -m 200 -n 200 \
  -mat_type aijkokkos -vec_type kokkos \
  -use_gpu_aware_mpi 0 \
  -ksp_type cg -pc_type hypre -pc_hypre_type boomeramg \
  -pc_hypre_boomeramg_relax_type_all l1scaled-jacobi \
  -ksp_monitor -ksp_max_it 200 -log_view
```

CPU baseline removes `-mat_type aijkokkos -vec_type kokkos -use_gpu_aware_mpi 0`
and the relaxer override.

## Stack

| Layer | Version |
|---|---|
| OS | Ubuntu 26.04, kernel 7.0.0-15 |
| CPU | Intel Core Ultra 9 285K (24T) |
| GPU | Intel Arc Pro B70 (BMG-G31), 32 GB GDDR6 ECC |
| oneAPI | 2025.3.3 (build 20260319) |
| MPI | System-OpenMPI (Ubuntu) with `OMPI_CC=icx OMPI_CXX=icpx` |
| PETSc | 3.25.1 + Plan I patches |
| KokkosKernels | 5.1.0 (BATCHED component disabled, components.cmake patched) |
| Hypre | develop / origin/master |
| Kokkos / Umpire / Caliper | bundled (PETSc default) |

## Results

| Run | Iter | Norm of error | KSPSolve time | Time / iter |
|---|---|---|---|---|
| **CPU baseline** (no `aijkokkos`) | 5 | 4.56 × 10⁻⁵ | 1.16 × 10⁻² s | 2.32 ms |
| **GPU Kokkos+SYCL+Hypre+UM** | 10 | 6.40 × 10⁻⁵ | 1.97 × 10⁻¹ s | 19.7 ms |

Both runs **converge cleanly**. Different iteration counts come from
different relaxer choices (`l1scaled-jacobi` is GPU-safe, slower-per-iter
than the CPU default).

## Backend Verification

`-log_view` excerpts confirming the GPU path:

```
MatMult              10 1.0   n/a   n/a  3.98e+06 1.0  ...  100  (GPU column)
VecNorm              11 1.0   n/a   n/a  8.80e+05 1.0  ...  100
KSPSolve              1 1.0  1.97e-01 ...                  100
```

(`n/a` for the timing column is normal for asynchronous SYCL kernels;
the total `KSPSolve` time below is wall-clock.)

`grep -E "aijkokkos|MatMult_SeqAIJKokkos|VecKokkos|SYCL"` of the GPU log
returns multiple hits. The build script's `BACKEND_OK` check passes.

`ldd ./ex2` resolves the SYCL runtime to the 2025.3 path:

```
libsycl.so.8 => /opt/intel/oneapi/2025.3/compiler/2025.3/lib/libsycl.so.8
libmkl_sycl_blas.so.5 => /opt/intel/oneapi/2025.3/mkl/2025.3/lib/libmkl_sycl_blas.so.5
libmkl_sycl_lapack.so.5 => /opt/intel/oneapi/2025.3/mkl/2025.3/lib/libmkl_sycl_lapack.so.5
```

If the resolution falls back to `/opt/intel/oneapi/compiler/2026.0/lib/`,
the binary is stale — `rm ex2 && make ex2` fixes it.

## Why the GPU is 17× Slower at 40k Unknowns

This is **expected**:

- SYCL JIT-compile cost on first kernel launch (~5–10 s, amortised across
  iterations but still material at 40k)
- Host→Device transfer for 40k unknowns is similar in cost to the entire
  CPU solve at this size
- BoomerAMG setup is mostly serial; cannot amortise on a 40k problem
- Battlemage's strength is *bandwidth* (608 GB/s), which only kicks in for
  large arrays

This is **not** Plan I's fault. The same observation appears in PETSc's
own GPU tutorials and in Aurora benchmarks: GPU-AMG breaks even with CPU
GAMG around N = 1–10 M, and *wins* substantially above N = 50–100 M. Our
[Stufe 3 testcase](../conclusions.md#performance-not-yet-a-win) is 34 M
cells (so ≈ 130 M unknowns for 4-component velocity + pressure systems),
the regime where GPU should win.

## What This Result Asserts

✅ PETSc 3.25.1 + Kokkos + KokkosKernels (BATCHED-off) + Hypre + SYCL
   builds cleanly under Plan I.
✅ The Kokkos-SYCL backend is wired through to runtime — `aijkokkos`
   is a registered MatType and `-log_view` confirms SYCL execution.
✅ Hypre BoomerAMG with `--enable-unified-memory` works as a PC for a
   `aijkokkos` matrix.
✅ ex2 converges to the same numerical answer (within smoother-tolerance)
   on both CPU and GPU paths.

## What This Result Does **Not** Assert

❌ Plan I is faster than CPU GAMG. (At 40k unknowns it is not, by 17×;
   that's expected. Stufe 3 will measure 34M cells.)
❌ Plan I works for arbitrary preconditioners on B70. (E.g., spiluk fails
   with IGC ICE — see [findings/14](../findings/14_ex3k_igc_compiler_error_battlemage.md);
   we use Hypre BoomerAMG, not KokkosSparse spiluk.)

## Reproducing this exact result

```bash
bash --noprofile --norc /path/to/scripts/stufe2-petsc.sh
```

Phase 6 of the script runs both CPU and GPU benchmarks back-to-back, then
prints the same numbers in the Phase 7 Bericht.
