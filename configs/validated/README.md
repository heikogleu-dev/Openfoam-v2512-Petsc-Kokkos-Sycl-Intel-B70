# Validated Configurations — β5h2 + F-PRE + 5e

Archive of working build script and exact `fvSolution` dictionaries
used for the cavity sanity test. Reproduces the results documented in
findings 19, 20, 21.

## Build

`stufe2-petsc-beta5h2.sh` — copy of `scripts/stufe2-petsc.sh` at the
β5h2 Release configuration. Configure ≈ 8 min, total wall-clock
≈ 52 min on a 24-core machine. Stack:

- PETSc 3.25.1
- Kokkos 5.1.0 (PETSc default)
- KokkosKernels develop, commit `6620b0a` (Plan-I patches applied via tarball)
- Hypre master (with `--enable-unified-memory`)
- oneAPI 2025.3.3
- `Kokkos_ARCH_INTEL_GEN=ON` (activates `KOKKOS_ARCH_INTEL_GPU` macro under JIT)

`petsc-configure-beta5h2.log.gz` — full PETSc configure trace for
auditability (175k lines compressed).

## Cavity-Sanity `fvSolution` Variants

All on `mat_type aijkokkos`, run with `PETSC_OPTIONS="-use_gpu_aware_mpi 0
-log_view -vec_type kokkos"` and `ONEAPI_DEVICE_SELECTOR=level_zero:0`.

| File | PC strategy | Result on β5h2 Release |
|---|---|---|
| `fvSolution-alpha` | gamg + `aggressive_square_graph false` | CRASH SEGV 11 |
| `fvSolution-beta` | gamg + `aggressive_coarsening 0` | CRASH SEGV 11 |
| `fvSolution-gamma` | gamg + Alpha + Beta combined | CRASH SEGV 11 |
| `fvSolution-delta` | Alpha + run with `-matmatmult_backend cpu -matptap_backend cpu` | CRASH SEGV 11 |
| `fvSolution-epsilon` | KAUST/Zampini ESI-style full GPU-CFD config | CRASH SEGV 11 |
| `fvSolution-zeta` | bjacobi + ilu0 sub | CRASH SEGV 11 |
| **`fvSolution-eta`** | **chebyshev + jacobi** | **PASS, fully on GPU** ← finding 21 |
| `fvSolution-theta` | cg + sor | PASS but PCApply runs CPU-side (164 GpuToCpu/KSPSolve) |

## Recommended Production Path on β5h2 Release

`fvSolution-eta` (chebyshev+jacobi) is the only configuration that:

1. Does not crash
2. Runs end-to-end on B70 with `GPU %F=100`
3. Has zero hidden host-device transfers in the inner KSP loop

It pays for this with high iteration counts (500–1000 for cavity).
See finding 21 for the full trade-off and 34M-cell scaling estimate.
