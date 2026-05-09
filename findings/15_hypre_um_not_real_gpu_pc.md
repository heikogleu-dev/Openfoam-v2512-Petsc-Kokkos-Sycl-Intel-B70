# Hypre `--enable-unified-memory` Builds Allocate-on-USM but COMPUTE on CPU

## Summary

A Hypre build with **only** `--enable-unified-memory` (no `--with-cuda`,
`--with-hip`, or `--with-sycl`) does **not** execute BoomerAMG on the
GPU. Allocations land in unified memory (so PETSc and Hypre can share
buffer pointers without explicit copies), but the compute runs on the
CPU.

This invalidates the implicit "GPU PC" claim in earlier Stufe-2 + Stufe-3
documentation here. The build pipeline works; the GPU compute path
through Hypre BoomerAMG does not.

## Evidence (from `-log_view` on the cavity-petsc-sanity case)

```
Event Stage 2: foam_p_pc       (BoomerAMG setup phase)
  Time%:    63.9      ← 64% of wall clock spent in PCSetUp
  MatConvert    2 1.0    ← matrix converted away from aijkokkos
  PCSetUp       2 1.0
  GPU Mflop/s:  n/a    everywhere

Event Stage 3: foam_p_ksp      (CG iterations)
  KSPSolve      2 1.0   1.4287e-02  Mflop/s:    14    GPU Mflop/s: n/a
  PCApply      22 1.0    n/a   ← Hypre apply: zero PETSc-tracked flops

CpuToGpu Count: 0   GpuToCpu Count: 0
```

`MatConvert` in `foam_p_pc` stage = Hypre's PETSc-adapter copies the
matrix from `aijkokkos` (Kokkos-storage) into Hypre's native `ParCSRMatrix`
which **lives in CPU memory** for compute even when allocated as UM.

## Why this happens

Hypre 2.31+ supports three GPU backends:
- `--with-cuda` (NVIDIA)
- `--with-hip` (AMD)
- `--with-sycl` (Intel — experimental as of mid-2026)

The `--enable-unified-memory` flag is **orthogonal**. It controls whether
Hypre uses UM allocations for the matrix/vector buffers (so the same
pointer is valid on host and device). It does **not** select a GPU compute
backend.

Without one of `--with-{cuda,hip,sycl}`, BoomerAMG's `BoomerAMGSetup` and
`BoomerAMGApply` call host C kernels regardless of where the data resides.

## Fix paths (none yet implemented in this repo)

| Path | Effort | Risk |
|---|---|---|
| Rebuild Hypre with `--with-sycl=$SYCL_DIR --enable-unified-memory` | substantial — needs MKL + oneAPI tested on Battlemage | Hypre SYCL is "experimental"; previously hit `dpct::constant_iterator` mismatches under 2025.3 (see [findings/11](11_hypre_master_required.md)) |
| Switch PETSc PC to `gamg` (PETSc-native AMG with Kokkos backend) | trivial in fvSolution | GAMG with Kokkos backend on SYCL is also early-stage, may hit different bugs |
| Use a different AMG stack via PETSc — e.g. AMGX (CUDA only — not for Battlemage) | n/a | not applicable to Intel GPU |
| Accept Hypre-on-CPU + PETSc Vec on GPU and live with mixed-mode | none | this is what we have today; no end-to-end GPU acceleration |

## Impact on earlier reports in this repo

- README.md "Stufe 2 — GO" was build-completion + ex2-converges, **not**
  a GPU-PC verification. The original "GPU 17× slower than CPU at 40k
  unknowns — expected SYCL JIT overhead" explanation was wrong:
  Hypre BoomerAMG was on CPU in both runs; the slowdown came from
  SYCL-runtime initialization + Kokkos vector ops + matrix-conversion
  overhead, **not** GPU JIT.
- benchmarks/ex2_200x200_results.md "Backend confirmed YES" claim is
  misleading — Kokkos-storage was active for the matrix, but Hypre's
  PC ran on CPU.
- conclusions.md "Hypre BoomerAMG with `--enable-unified-memory` works
  as a PC for a `aijkokkos` matrix" is technically true (it ran without
  crash) but does not imply GPU compute.

The repo will be updated to reflect this honest assessment.

## Reproduction

Run any case with `mat_type aijkokkos` + `pc_type hypre` + `pc_hypre_type boomeramg`,
add `-log_view`, look for:
- `MatConvert` count > 0 in the `foam_p_pc` (or equivalent) stage
- `GPU Mflop/s: n/a` in `KSPSolve` event
- `CpuToGpu Count: 0`

Any of these alone is suspicious; all three together = Hypre PC is on
CPU.

## Status / Resolution

**Not fixed.** The bug is upstream-Hypre's design (`--enable-unified-memory`
is not GPU compute) plus our own oversight. To get true GPU BoomerAMG on
B70 we need a Hypre rebuild with `--with-sycl`. Filed as Plan-I-Phase-2
follow-up.

## Related

- [11](11_hypre_master_required.md) — Hypre master required for DPL/DPCT compatibility
- [16](16_petsc4foam_vec_type_prefix_ignored.md) — `-eqn_p_vec_type` ignored
- [17](17_aijkokkos_no_real_sycl_compute_when_pc_is_hypre.md) — full evidence chain
