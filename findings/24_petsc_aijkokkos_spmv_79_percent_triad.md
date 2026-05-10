# PETSc aijkokkos SpMV Reaches 79 % of Triad-Peak on B70

## Summary

Standalone SpMV microbenchmark of PETSc 3.25.1 with `MATAIJKOKKOS` on
the β5h2 Release build, B70 hardware, oneAPI 2025.3.3. 1000 `MatMult`
calls after 10 warm-up iterations on a 1M × 1M Poisson 5-point stencil
matrix.

```
Per-iter:    0.287 ms
Avg perf:    34.84 GFLOPS
Effective BW: 418 GB/s   (79 % of Triad-measured 531 GB/s)
```

## Why This Matters

This number is the honest answer to "does PETSc's `aijkokkos` MatMult
actually use the GPU effectively on Battlemage in May 2026". The answer
is: **yes, well, but not optimally.**

- 79 % of Triad-peak is a strong result for a cross-architecture
  abstraction layer (KokkosKernels CSR-SpMV → SYCL → Level Zero → BMG)
- It is below what hand-tuned native kernels achieve (Ginkgo's dpcpp
  CSR-SpMV reaches saturated VRAM-BW with cache effects, see finding 25)
- It is enough to make `aijkokkos`-backed Krylov methods a real GPU
  workload — the bottleneck is not SpMV throughput

## Implication for Foundation and Eta Paths

The Foundation pressure path (CG + Jacobi) and Eta path (Chebyshev +
Jacobi, finding 21) are dominated by SpMV + Vec ops. Both are SpMV-bound
and benefit from the 418 GB/s number. For these paths:

- 1M-cell Poisson `KSPSolve`: 1000 iter × 0.287 ms ≈ 290 ms
- 34M-cell Poisson SpMV: ≈ 10 ms / iter (extrapolated linearly)
- Eta on 34M: 500-1000 iter × ~10 ms = 5-10 s per p-solve, plus host
  vec ops

These numbers match the scaling estimate in finding 21.

## Setup

```cpp
PetscCall(MatCreate(PETSC_COMM_WORLD, &A));
PetscCall(MatSetType(A, MATAIJKOKKOS));
PetscCall(MatSetSizes(A, n, n, n, n));
// ... assemble 1M-row Poisson 5-pt stencil, ~5M nnz ...
PetscCall(MatAssemblyBegin/End(A, MAT_FINAL_ASSEMBLY));

PetscCall(MatCreateVecs(A, &x, &y));
PetscCall(VecSet(x, 1.0));

// Warmup: 10x MatMult
// Bench: 1000x MatMult, time

ENV: PETSC_OPTIONS="-vec_type kokkos -mat_type aijkokkos -use_gpu_aware_mpi 0"
     ONEAPI_DEVICE_SELECTOR=level_zero:0
```

Build linked against β5h2 Release `libpetsc.so.3.25.1` — the same build
that crashes on `pc_type gamg` (finding 19). The fact that pure SpMV
runs at near-peak performance while GAMG construction `SEGV`s in
`PCSetUp` proves the bug is NOT in the runtime SpMV path.

## Evidence

`logs/diag-2026-05-10/test3a_petsc.log.gz`

## Status / Resolution

**Validated.** PETSc `aijkokkos` SpMV on B70 with oneAPI 2025.3 is
production-quality. Krylov solvers and any preconditioner that uses
`MatMult` heavily (Jacobi, Chebyshev) inherit this throughput.

## Related

- [19](19_beta5h2_build_success_amg_wall_confirmed.md) — same build that crashes on GAMG
- [21](21_eta_chebyshev_jacobi_non_amg_gpu_path.md) — Eta scaling estimate uses this number
- [23](23_b70_hardware_functional_amg_wall_is_software.md) — context
- [25](25_ginkgo_3x_faster_microbench.md) — Ginkgo comparison
