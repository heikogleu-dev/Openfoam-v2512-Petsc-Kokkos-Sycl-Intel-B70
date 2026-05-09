# Debug Build Heals the GAMG Crash — But Setup Is CPU-Only and Too Slow for Production

## Summary

Rebuilding PETSc with `--with-debugging=1` (the F1 variant) makes the
GAMG path that crashes on Release run cleanly to completion. This is
strong evidence that the Release-build SEGV is a memory-safety bug
(uninitialized variable, use-after-free, or aliasing assumption) that
debug-build defensive zeroing/checks happen to mask.

But the debug build is also `~3×` slower for the actual KSP work, and
critically: the GAMG **setup operations** route to CPU even on the debug
build (`GPU %F = 0` for `MatMatMultSym`, `MatPtAPSymbolic`,
`MatPtAPNumeric`), making it impractical at 34M-cell scale.

## What Worked on Debug Build

Cavity case (40 000 unknowns), `icoFoam`, np=1, `pc_type gamg`,
`pc_gamg_type agg`:

```
Time = 0.005
PETSc-cg:  Solving for p, Initial residual = 1, Final residual = 1.6e-07, No Iterations 9
PETSc-cg:  Solving for p, Initial residual = 0.5236, Final residual = 6.2e-07, No Iterations 8
End

PCSetUp_GAMG          GPU %F = 100
PCApply               GPU %F = 100  (81% of stage time)
KSPSolve              GPU %F = 100
MatMult (KSP)         GPU %F = 100
CpuToGpu/GpuToCpu     2 / 4 (sparse, normal GAMG-setup transfers)
Total time            8.32 s
```

Compare against Foundation Jacobi on the same Debug build: 105+101 iter,
0.51 s — so GAMG converges in ~12× fewer iterations but costs ~16× more
in wall time due to setup. On cavity that is acceptable; on 34M cells
the picture changes.

## What Did Not Work — 34M-Cell MR2 on Debug Build

We started a single-rank `simpleFoam` run on the 34M-cell automotive
case with the debug build. After 16 minutes:

- Log progress: stalled at `Initializing PETSc... success`
- simpleFoam process: 100 % CPU, single-threaded, `Rl` state
- RSS: 49 GB
- GPU: 155 W power draw at 0 % engine busy (level-zero P0 state but no
  compute kernels dispatched)
- No KSPSolve had started

The debug build was burning CPU cycles in single-threaded GAMG setup
(graph construction, MIS aggregation) on the host. The fact that the
GPU was powered up but idle is the visible symptom of `aijkokkos` having
allocated USM matrices on device while the setup routines remain on
host. We aborted at 19 minutes wall clock with no progress beyond
PETSc init.

## Why GAMG Setup Is CPU-Side Even on Debug

On the cavity log_view, even with all `KSPSolve` events at GPU %F=100,
the GAMG construction events show GPU %F=0:

```
Event              GPU %F
MatMatMultSym      0      ← symbolic SPGEMM stage
MatMatMultNum      0      ← numeric SPGEMM stage
MatPtAPSymbolic    0      ← Galerkin operator symbolic
MatPtAPNumeric     0      ← Galerkin operator numeric
PCSetUp_GAMG+      100    ← but the umbrella event reports 100%
```

PETSc's GAMG calls `MatMatMult` and `MatPtAP` to build the multigrid
hierarchy. These dispatch to KokkosKernels SPGEMM, but on B70 with the
β5h2 build, the dispatch lands on a CPU code path (visible in the
Symbolic/Numeric event counters). The umbrella `PCSetUp_GAMG+` event
reports 100% because most of the *time* is in vector ops that PETSc
attributes to GPU; the actual SPGEMM work is on CPU.

This is the same gap that finding 17 documented for Hypre BoomerAMG —
just in a different code path.

## Diagnosis

The Release-build SEGV is a memory-safety bug in the PETSc-Kokkos GAMG
construction path. The debug build's defensive memory handling
(`PetscMalloc` zeroing, bounds checks) prevents the crash from
manifesting, but the underlying code routes large-matrix SPGEMM to CPU
on Battlemage in either build.

For 34M cells single-threaded CPU GAMG setup is impractical:
- the symbolic phase alone could take 30–60 min
- the numeric phase another 30–60 min
- amortized over 5 outer SIMPLE iterations is 5+ hours

Compared to Foundation v13's `GAMG` baseline at 43.3 s/step for the same
case, debug-build PETSc-Kokkos GAMG would be 50–100× slower per outer
iteration.

## Reproduction

```bash
# F1 build: stufe2-petsc.sh with --with-debugging=1
# everything else identical to β5h2

cd CFD-Cases/cavity-petsc-sanity
# Use configs/validated/fvSolution-gamg-agg.dict

icoFoam       # passes, GAMG agg, 9+8 iter, ~8 s
```

## What Would Make This Productive

Either of:

1. **Source-level fix** in PETSc/Kokkos for the Release crash, plus
2. **Real GPU SPGEMM** in KokkosKernels for B70 — the symbolic/numeric
   matrix-product events need to land on device, not CPU

(1) without (2) gets you an answer slowly. (2) without (1) is invisible
because of the crash. Both are needed for a productive 34M GAMG path.

## Status / Resolution

**Documented.** Debug build is suitable for cavity-scale GAMG validation
and code-correctness checks but is not a production path for the MR2
case.

## Related

- [19](19_beta5h2_build_success_amg_wall_confirmed.md) — Release crash signature
- [21](21_eta_chebyshev_jacobi_non_amg_gpu_path.md) — viable non-AMG path on Release
- [22](22_pioneer_status_aijkokkos_gamg_sycl_not_productive.md) — upstream context
- [17](17_aijkokkos_no_real_sycl_compute_when_pc_is_hypre.md) — analogous gap for Hypre
