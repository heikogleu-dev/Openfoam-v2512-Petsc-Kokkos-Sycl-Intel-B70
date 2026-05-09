# `aijkokkos` Matrix With Hypre PC Does NOT Run on GPU

## Summary

Combining `mat_type aijkokkos` with `pc_type hypre` + `pc_hypre_type
boomeramg` (the Plan-I default) does not produce GPU compute. PETSc's
Hypre adapter silently `MatConvert`s the Kokkos-storage matrix into
Hypre's native `ParCSRMatrix` for the PCSetUp/PCApply phases, and
without a GPU-target Hypre build, those phases run on the CPU.

This combines findings [15](15_hypre_um_not_real_gpu_pc.md) and
[16](16_petsc4foam_vec_type_prefix_ignored.md) into the full picture for
the Plan-I stack as it exists today.

## What `-log_view` Shows

Direct evidence from a 1-timestep cavity run (`mat_type aijkokkos` set,
`vec_type kokkos` rejected, Hypre-UM build, B70 with `level_zero:0`):

```
PETSc Performance Summary

Stage 0 (Main Stage)         Time%:  30.1
Stage 1 (foam_p_mat)         Time%:   2.5    ← matrix assembly
Stage 2 (foam_p_pc)          Time%:  63.9    ← Hypre BoomerAMG SETUP
Stage 3 (foam_p_ksp)         Time%:   3.5    ← CG iterations

Event-stage details:
foam_p_pc:
  MatConvert      2 1.0    ← matrix copied OUT of aijkokkos format
  PCSetUp         2 1.0    ← Hypre's BoomerAMG setup runs here
  Time%:         63.9      ← but reported with no GPU time

foam_p_ksp:
  KSPSolve        2 1.0  Time(s) 1.4287e-02  Mflop/s 14   GPU Mflop/s n/a
  PCApply        22 1.0    n/a    n/a    0.00e+00  ← zero PETSc-tracked flops
  MatMult        22 1.0    n/a    n/a    8.45e+04  GPU%F 100  GPU Mflop/s n/a

CpuToGpu Count:  0   GpuToCpu Count:  0    ← NO transfers all run
```

Three independent signals say the same thing:
1. `MatConvert` × 2 in `foam_p_pc` — Kokkos-storage matrix gets copied
   to Hypre's CPU format
2. `GPU Mflop/s: n/a` for KSPSolve **and every Vec/Mat event**
3. `CpuToGpu Count: 0` — not a single host→device transfer

The `GPU %F: 100` annotations on `MatMult`, `VecTDot`, `VecNorm`,
`VecAXPY` are PETSc's "this event has a GPU code path" flag, not "this
event ran on GPU". With `Mflop/s GPU: n/a` and 0 transfers, the GPU code
path was simply never executed (likely because the working vectors are
still on host — see [16](16_petsc4foam_vec_type_prefix_ignored.md)).

## What This Means for Earlier Reports in This Repo

| Earlier claim | Actual reality |
|---|---|
| Stufe-2 ex2 200×200: "Backend confirmed YES" | Kokkos-Mat-storage active; Hypre-PC and all compute on CPU |
| "GPU 17× slower than CPU at 40k unknowns — expected SYCL JIT overhead" | Both runs were CPU-Hypre; 17× slowdown was SYCL-runtime + Kokkos-init + MatConvert overhead, **not** GPU JIT |
| Stufe-2 GO recommendation | Build pipeline GO; GPU PC compute **not verified** |
| Stufe-3 cavity sanity GO | icoFoam runs to End rc=0; CG converges; **PC and Vec on CPU** |
| Stufe-3 34M np=8 OOM caused by "Hypre USM × 8 ranks" | Closer interpretation: 8× CPU-side BoomerAMG hierarchies for 4M-cell sub-domains; UM allocations contribute but Hypre's setup itself is CPU memory-hungry at 34M |

## What Has To Change to Get Real GPU PC

| Task | Difficulty | Outcome |
|---|---|---|
| Rebuild Hypre with `--with-sycl=$SYCL_DIR --enable-unified-memory` | hard — Hypre's SYCL backend is experimental, needs MKL randvec patches, may hit similar DPL/DPCT issues to [findings/11](11_hypre_master_required.md) | True device-side BoomerAMG — if Hypre SYCL is functional on Battlemage |
| Switch to PETSc's native AMG (`pc_type gamg`) with `aijkokkos` | trivial fvSolution change | GAMG-on-Kokkos may produce real GPU compute; convergence likely worse than Hypre BoomerAMG |
| Add `-vec_type kokkos` via `PETSC_OPTIONS` env var (workaround for [16](16_petsc4foam_vec_type_prefix_ignored.md)) | trivial | Closes vec-type gap; does NOT fix the Hypre-PC-on-CPU issue |
| Use `MatSetType(MATAIJ)` + `pc_type bjacobi sub_pc_type ilu` (CPU only) | trivial | Honest CPU baseline; no GPU pretense |

## "Did anything actually use the GPU?"

**Indirectly, yes:** the SYCL runtime initialized, Kokkos backend created
its SYCL queue on B70, the `aijkokkos` matrix was allocated in USM. But
**no GPU kernels were dispatched for compute work**. Heiko observed
1.5 GB VRAM allocation on the failed Stufe-3 OpenCL-backend run — that
was Kokkos's matrix buffer, not active compute.

## Status / Resolution

**Documented.** The Plan-I stack as released here builds + links + runs
correctly but achieves only Kokkos-allocated CPU compute. No code in this
repo claims a GPU performance result — but the optimistic framing in the
original READMEs needs correction. PR-1 to update the docs is filed
under this finding's repo commit.

## Related

- [15](15_hypre_um_not_real_gpu_pc.md) — root cause: Hypre UM ≠ GPU compute
- [16](16_petsc4foam_vec_type_prefix_ignored.md) — vec_type can't be prefixed
- [11](11_hypre_master_required.md) — Hypre master needed for DPL/DPCT compat (separate concern)
- [logs/cavity-logview-evidence.log](../logs/cavity-logview-evidence.log) — full `-log_view` output for the cavity case
