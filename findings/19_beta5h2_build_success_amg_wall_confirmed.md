# β5h2 Build Successful — AMG Wall Confirmed Across All Five GAMG Configurations

## Summary

The β5h2 stack builds and links cleanly on Intel Arc Pro B70 (BMG-G31)
with PETSc 3.25.1 + Kokkos 5.1.0 + KokkosKernels develop (commit `6620b0a`,
8 May 2026) + Hypre master + oneAPI 2025.3.3 + Aurora-style optimization
flags (without `-g`) + `Kokkos_ARCH_INTEL_GEN=ON` (which activates the
`KOKKOS_ARCH_INTEL_GPU` macro under JIT, no AOT device-id required).

The Foundation pressure-equation path (CG + Jacobi + `aijkokkos` +
`vec_type kokkos`) runs end-to-end with `GPU %F=100` on `MatMult`,
`KSPSolve`, `VecAXPY`, `VecTDot`, `VecNorm`, `VecAYPX`, `VecPointwiseMult`.

**However**, every GAMG configuration we tried crashes immediately with
`SEGV signal 11` in `PCSetUp` before reaching the first `KSPSolve`.

## Build Verification

```
Configure:           rc=0,  8 min
Build:               rc=0
make check:          ex19=3 pass, ex19_HYPRE=1 pass
GPU sanity (ex2):    pass, Backend confirmed
libpetsc.so.3.25.1:  32 MB
PETSC_USE_DEBUG:     not defined  (Release build)
KOKKOS_ARCH_INTEL_GEN: defined
KOKKOS_ARCH_INTEL_GPU: defined  (via INTEL_GEN macro chain)
KK Plan-I markers:   3
KK ext_intel_free_memory specialization: present
```

## The AMG Wall — Five Configurations Tested

All on the same β5h2 Release build, same cavity case (40 000 unknowns,
`icoFoam`, np=1, `mat_type aijkokkos`):

| Variant | GAMG Configuration | Result |
|---|---|---|
| baseline | `pc_type gamg, pc_gamg_type agg, threshold 0.02` | SEGV 11, 1 s |
| Alpha | + `pc_gamg_aggressive_square_graph false` (MIS-2 instead of squared SPGEMM) | SEGV 11, 1 s |
| Beta | + `pc_gamg_aggressive_coarsening 0` (no squaring at all) | SEGV 11, 1 s |
| Gamma | Alpha + Beta combined | SEGV 11, 1 s |
| Delta | Alpha + `-matmatmult_backend cpu -matptap_backend cpu` (route SPGEMM to CPU) | SEGV 11, 1 s |
| Epsilon | KAUST/Zampini ESI-style full GPU-CFD config (`agg_nsmooths`, `coarse_eq_limit`, `reuse_interpolation`, chebyshev/jacobi smoothers) | SEGV 11, 1 s |

All crashes happen at the same point: between `Initializing PETSc...
success` and the first KSP iteration. No `log_view` is produced (the
abort kills the process before `PetscFinalize`). Crash signature is
identical across all five — same SEGV in the same place.

## Diagnosis

Since every configurable GAMG sub-path yields the same crash, the bug
must sit in **shared low-level code that all five configurations
traverse**. Likely candidates: `MatProductSymbolic_SeqAIJKokkos`,
`MatConvert_SeqAIJ_SeqAIJKokkos`, or the early phase of
`PCGAMGCreateGraph_AGG` before the algorithm selection branches.

Even the `-matmatmult_backend cpu` / `-matptap_backend cpu` workaround
fails — meaning the crash happens *before* PETSc reaches the
MatProduct dispatch logic. The aijkokkos object itself is dying
during the GAMG graph construction, not during a sparse-matrix
multiplication.

## What This Means

- The Foundation path (CG + cheap PC) is production-ready on this stack
- The GAMG family on `aijkokkos` is **blocked at the source level** on
  B70 with this PETSc/Kokkos combination
- Configuration-level workarounds are exhausted

See finding 20 for the debug-build behavior (which heals the crash but
becomes too slow for 34M-cell production), and finding 21 for the
viable non-AMG GPU-PC path that emerged from this investigation.

## Reproduction

```bash
# Build state: β5h2 Release as documented in scripts/stufe2-petsc.sh

cd CFD-Cases/cavity-petsc-sanity
# Use any of the five fvSolution-{alpha,beta,gamma,delta,epsilon} variants
# from configs/validated/

export PETSC_OPTIONS="-use_gpu_aware_mpi 0 -log_view -vec_type kokkos"
export ONEAPI_DEVICE_SELECTOR=level_zero:0
icoFoam   # SEGV 11 within 1 s
```

## Status / Resolution

**Open.** Workaround at the GAMG configuration level exhausted.
Source-level fix needed in PETSc-Kokkos GAMG initialization code.
Filed as finding 22 (pioneer status) for upstream awareness.

## Related

- [20](20_debug_build_heals_crash_but_too_slow.md) — debug build behavior
- [21](21_eta_chebyshev_jacobi_non_amg_gpu_path.md) — viable non-AMG path
- [22](22_pioneer_status_aijkokkos_gamg_sycl_not_productive.md) — upstream context
- [17](17_aijkokkos_no_real_sycl_compute_when_pc_is_hypre.md) — earlier Hypre path
