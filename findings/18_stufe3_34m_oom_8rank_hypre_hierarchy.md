# Stufe-3: 34M-cell × np=8 → 90 GB DRAM Explosion at Hypre BoomerAMG Setup

## Summary

When porting the 34-million-cell MR2 automotive testcase to PETSc + Hypre
BoomerAMG via petsc4Foam (the Stufe-3 target), the system OOM-killed the
solver during `PCSetUp` of the first p-equation. RAM usage spiked to
≈90 GB before `simpleFoam` was killed; VRAM usage was modest (≈1.5 GB
on the failed OpenCL-backend attempt; not measured in the level_zero
attempt).

## Symptom

```
Time = 1
DILUPBiCGStab:  Solving for Ux, Initial residual = 1, ...
DILUPBiCGStab:  Solving for Uy, Initial residual = 1, ...
DILUPBiCGStab:  Solving for Uz, Initial residual = 1, ...
ExecutionTime = 29.15 s   ← U/k/ω solves OK on CPU

Initializing PETSc... success
ExecutionTime = 29.19 s
                          ← PCSetUp begins
                          ← RAM rises 6 GB → 90 GB
                          ← OOM-killer triggers (visible in dmesg)
                          ← simpleFoam killed; VSCode collateral
```

## Diagnosis (revised after [findings/15](15_hypre_um_not_real_gpu_pc.md))

The original interpretation was "Hypre USM allocations × 8 ranks
multiplies VRAM-style usage into DRAM". The corrected understanding,
per finding 15, is more direct:

**Hypre BoomerAMG runs entirely on CPU** in our build (no `--with-sycl`).
Each MPI rank therefore holds a complete CPU-side BoomerAMG hierarchy
for its ~4M-cell sub-domain:
- Strength-of-connection matrix
- Coarsening-level matrices (10-20 levels typical)
- Restriction / interpolation operators
- Smoother data
- Auxiliary scratch buffers

For a 4M-cell sub-domain × ~10 levels × ParCSRMatrix overhead, ~10 GB
of RAM is plausible. **× 8 ranks = ≈80 GB**. Add OpenFOAM's mesh, fields,
and PETSc's matrix copy → 90 GB observed.

The `--enable-unified-memory` flag is a red herring here: it changes
*where* the buffer lives (UM-allocator instead of malloc) but the
compute is unchanged on CPU. UM allocations are also slightly more
expensive than plain malloc (driver-managed virtual address space).

## What this means

This is **expected** behavior for plain CPU-Hypre at 34M-cell × 8-rank
scale. The sister-repo's [Foundation v13 + OGL/Ginkgo path](https://github.com/heikogleu-dev/Openfoam13---GPU-Offloading-Intel-B70-Pro)
runs the same case in 35.7 s/step using the well-tuned CPU GAMG, which
trades hierarchy size for setup speed and uses far less RAM than
BoomerAMG's full-coarsening default.

For Plan-I to scale to 34M cells, one of:
1. Run **np=1** or **np=2** so total CPU-Hypre memory fits in 96 GB DRAM
2. Use a leaner BoomerAMG configuration (motorBike-tutorial-style:
   `max_levels "25"`, `agg_nl "1"`, `P_max "1"`, `truncfactor "0.3"`)
3. Switch to PETSc native `gamg` (more like the sister-repo's CPU GAMG)
4. Rebuild Hypre with `--with-sycl` so the hierarchy lives in VRAM
   (32 GB hard cap on B70; might still OOM at 34M)

We have not yet tried any of these in production. The cavity-sanity
test (400 cells, np=1) ran in 6 GB RAM — far below the wall.

## Symptom: which-config-failed-where map

| Run | np | Cells/rank | RAM observed | Outcome |
|---|---|---|---|---|
| Cavity icoFoam | 1 | 400 | 6 GB | rc=0, converged |
| Stufe-2 ex2 200×200 | 1 | 40 000 | not tracked, low | rc=0, converged |
| Stufe-3 simpleFoam (this case) | **8** | **~4 250 000** | **90 GB → OOM** | killed |

With ~100× more cells per rank than ex2, plus 8× rank multiplication, the
total memory footprint is ~3 orders of magnitude above the validated
small-case configurations.

## Reproduction

Don't, unless you have ≥128 GB RAM or have tuned Hypre. The `controlDict`
in `Testcase-petsc4Foam-ESI/system/` plus `fvSolution` with the
quoted-numerics PETSc-options dict + libs `petscFoam` is sufficient to
reproduce on any 34M-cell decomposed-into-8 case.

## Status / Resolution

**Open.** Plan-I-Phase-2 next steps:
1. Rerun with `np=1` to confirm the per-rank memory hypothesis
2. Apply the motorBike BoomerAMG tuning to reduce hierarchy size
3. Investigate Hypre `--with-sycl` rebuild (longer-term)

These are tracked in this repo's [conclusions.md](../conclusions.md)
roadmap.

## Related

- [15](15_hypre_um_not_real_gpu_pc.md) — root reason BoomerAMG is on CPU
- [17](17_aijkokkos_no_real_sycl_compute_when_pc_is_hypre.md) — full
  evidence chain
- Sister repo's [bottleneck_analysis.md](https://github.com/heikogleu-dev/Openfoam13---GPU-Offloading-Intel-B70-Pro/blob/main/profiling/bottleneck_analysis.md)
  for the 34M-case characterization on the Ginkgo path
