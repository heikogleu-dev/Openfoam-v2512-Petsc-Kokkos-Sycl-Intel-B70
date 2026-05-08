# Honest Conclusions

## Does the Plan-I Stack Work?

**Yes — with explicit caveats.**

A clean PETSc 3.25.1 + Kokkos + KokkosKernels (BATCHED off) + Hypre
(develop) + SYCL build links and runs on Intel Arc Pro B70 Pro under
oneAPI 2025.3.3, after applying the Plan I patches in
[`patches/plan-i.patch`](patches/plan-i.patch). Sanity check ex2 200×200
with `aijkokkos + Hypre BoomerAMG + l1scaled-jacobi` converges; backend
(Kokkos/SYCL) is confirmed in `-log_view`. See
[benchmarks/ex2_200x200_results.md](benchmarks/ex2_200x200_results.md)
for the run trace.

## What Actually Required Patching (not just configuration)

| Layer | Patch | Why we cannot just "configure around it" |
|---|---|---|
| KokkosKernels `cmake/kokkoskernels_components.cmake` | comment out 3 `set(KK_ENABLE_BATCHED ON CACHE BOOL "" FORCE)` lines | SPARSE, GRAPH, ALL_COMPONENTS each FORCE-enable BATCHED unconditionally; CMake `-DKK_ENABLE_BATCHED=OFF` is silently overridden |
| PETSc `src/mat/impls/aij/seq/kokkos/aijkok.kokkos.cxx` | comment 2 `KokkosBatched_*Decl.hpp` includes; replace `MatInvertVariableBlockDiagonal_SeqAIJKokkos` body with `SETERRQ` | aijkok would otherwise fail to compile when KokkosKernels has BATCHED-off |

These two together are Plan I. Everything else is configuration / version
selection / runtime flags.

## What's Lost vs Plan-A

We sacrificed the following to get a working build on B70 + oneAPI 2025.3:

- **VPB-Jacobi (Variable Point-Block Jacobi) PC for `MATSEQAIJKOKKOS`** —
  runtime `PETSC_ERR_SUP` if requested. Almost no production use of this
  PC, particularly not for Hypre-based solves. Not a meaningful loss.
- **AOT compile for B70** (`-fsycl-targets=intel_gpu_bmg_g31`) — skipped
  because system `ocloc 24.35` doesn't know Battlemage. We use SPIR-V/JIT
  compilation via `libze-intel-gpu1 26.05` runtime. First-call per kernel
  pays a JIT cost; subsequent calls are cached. See
  [findings/06](findings/06_legacy_ocloc_no_battlemage_aot_jit_fallback.md).
- **PETSc `ex3k` make-check** — passes only IGC ICE; we tolerate it
  because our path (`pc_type hypre`) doesn't hit `KokkosSparse spiluk`.
  Documented in [findings/14](findings/14_ex3k_igc_compiler_error_battlemage.md).
- **GPU-aware MPI** — System-OpenMPI isn't SYCL-GPU-aware; we set
  `-use_gpu_aware_mpi 0` at runtime. For the small ex2 sanity run there's
  no measurable cost. For multi-rank Stufe-3 runs on the 34M-cell mesh,
  expect a host-buffer round-trip per halo exchange, similar to the
  forced `forceHostBuffer=true` in the sister repo's Ginkgo path.

## Why oneAPI 2025.3.3 and not 2026

Intel deprecated DPCT (Data-Parallel C++ Compatibility Tool) for the 2026
release; no DPCT 2026 ships. But `dpl/2022.10/include/oneapi/dpl/...` headers
in oneAPI 2026 still reference DPCT API symbols. icpx 2026's stricter SYCL
spec also removed `sycl::ext::oneapi::experimental::get_tangle_group` and
`get_fixed_size_group`, which DPCT 2025.3 still uses. Hypre release
includes these via DPL → fails to compile on 2026.

oneAPI 2025.3.3 (filename `intel-oneapi-base-toolkit-2025.3.2.21_offline.sh`,
internal version 2025.3.3 build 20260319) ships icpx + DPCT + DPL as one
internally-consistent set. It is also the version PMZFX validated for B70
in [their benchmarks repo](https://github.com/PMZFX/intel-arc-pro-b70-benchmarks).
We install 2025.3 in parallel to 2026 (`/opt/intel/oneapi/2025.3/`) and
prefer it via PATH ordering.

See [findings/10](findings/10_oneapi_2026_dpct_2025_3_mismatch.md).

## Performance: Not Yet a Win

Phase-6 sanity (40k unknowns, 200×200 grid):

| Run | Iter | KSPSolve | Time/Iter |
|---|---|---|---|
| CPU baseline | 5 | 11.6 ms | 2.32 ms |
| GPU Kokkos+SYCL+Hypre+UM | 10 | 196.6 ms | 19.7 ms |

GPU is **17× slower** at this scale. Expected: SYCL JIT-compile cost
dominates (5–10 s startup) plus host↔device transfer for 40k unknowns
costs more than the compute itself.

The Stufe-3 testcase (34M cells, ~8500× larger) should reverse this,
matching what literature predicts for AMG-on-GPU scaling. **We don't claim
a CFD performance win until Stufe 3 measures it.**

The sister repo with Foundation OF 13 + Ginkgo on the same hardware
demonstrated **CPU GAMG remains the production winner today**. Whether
PETSc+Hypre+Kokkos+SYCL changes that for the 34M case is the central
question of Stufe 3.

## Roadmap

| Stufe | Status | Goal |
|---|---|---|
| 1 — ESI v2512 build | ✅ GO | OpenFOAM-v2512 alongside Foundation 13, no cross-contamination |
| 2 — PETSc+Kokkos+SYCL+Hypre stack | ✅ GO | Build + ex2 sanity; backend confirmed |
| 3 — petsc4Foam adapter + 34M-cell case | ⏳ | Replace OpenFOAM's GAMG with PETSc Hypre BoomerAMG |
| 4 — performance measurement | ⏳ | Honest CPU-vs-GPU s/step for the 34M case |
| 5 — upstream patch submission | ⏳ | KokkosKernels `BatchedDblBufGemm` reference→pointer; PETSc aijkok `#ifdef`-guard for BATCHED |

## Related: Sister Repo Findings

The [sister repo](https://github.com/heikogleu-dev/Openfoam13---GPU-Offloading-Intel-B70-Pro)
documents the *Ginkgo* path (Foundation OpenFOAM 13 + OGL + Ginkgo). It
concludes:

> **Hardware excellent (FP64 96 %, kernel latency CUDA-par); software
> stack not ready (GPU 66 % idle, no working strong preconditioner in
> Ginkgo 1.10/1.11 SYCL).**

This repo's *PETSc + Hypre BoomerAMG* path attacks that exact gap — Hypre
BoomerAMG **is** a strong preconditioner that targets SYCL via Kokkos USM.
Whether it actually wins at scale is the Stufe-3 question.

## Recommendation (May 2026)

For production CFD on B70 today: **continue using CPU GAMG.** Use this
stack as a research/development platform for evaluating PETSc-Hypre-Kokkos
on Battlemage; revisit production status after Stufe 3.

The 32 GB ECC VRAM remains best deployed for LLM inference and ParaView
visualization in the meantime, as documented in the sister repo.

---

*If you find different results — better, worse, or just different — please
[open an issue](https://github.com/heikogleu-dev/Openfoam-v2512-Petsc-Kokkos-Sycl-Intel-B70/issues).*
