# Benchmarks

| File | Stage | Status |
|---|---|---|
| [`ex2_200x200_results.md`](ex2_200x200_results.md) | Stufe 2 — Phase 6 build sanity | ✅ Passed |
| `mr2_sw20_34M_results.md` (planned) | Stufe 3 — automotive aerodynamics, 34M cells, simpleFoam k-ω SST | ⏳ Pending petsc4Foam adapter integration |

## Stufe 2 — Build-correctness benchmark only

The Stufe 2 sanity benchmark is intentionally tiny (200 × 200 = 40 000
unknowns). At that size the GPU is ≈17× **slower** than CPU because
SYCL JIT-compile + host↔device transfer dominate. **This is expected and
documented**, not a performance failure.

The purpose of the Stufe 2 benchmark is to verify that:
- The Kokkos+SYCL backend is wired through end-to-end
- `aijkokkos` is a registered MatType
- Hypre BoomerAMG with `--enable-unified-memory` accepts a `aijkokkos` matrix
- The solver converges to the same numerical answer as the CPU baseline

All four hold. See [ex2_200x200_results.md](ex2_200x200_results.md) for
the full numbers.

## Stufe 3 — Performance benchmark (pending)

The Stufe-3 testcase is the same MR2 SW20 vehicle CFD case used in the
[sister repo](https://github.com/heikogleu-dev/Openfoam13---GPU-Offloading-Intel-B70-Pro):
34 M cells, simpleFoam k-ω SST, steady-state s/step from `Time = 8, 9, 10`
mean. The [sister repo's `benchmarks/results.md`](https://github.com/heikogleu-dev/Openfoam13---GPU-Offloading-Intel-B70-Pro/blob/main/benchmarks/results.md)
is the apples-to-apples reference:

| Configuration | s/step | Status |
|---|---|---|
| CPU GAMG, 16 cores (P+E) | **35.7** | sister repo, baseline |
| GPU OGL Ginkgo BJ, np=16 | 50–53 | sister repo, slower |
| **GPU PETSc Kokkos+SYCL+Hypre BoomerAMG (np=?)** | **TBD** | **THIS REPO, Stufe 3** |

The Stufe 3 question: does PETSc Hypre BoomerAMG (a strong preconditioner,
unlike Ginkgo's BJ-only on Battlemage SYCL) close the 1.5× gap to CPU GAMG?

The sister repo predicts:
> **Working SYCL Multigrid (or any strong preconditioner): −20 to −30 s/step**
> (5–10× fewer iterations).
> All three [GPU-aware MPI + SYCL Multigrid + SYCL Graph] combined could
> plausibly reach <10 s/step = ~3.5× faster than CPU GAMG (35.7 s/step).

Stufe 3 will measure exactly this. Results land here when ready.

## Cross-references

- Sister repo: [Openfoam13---GPU-Offloading-Intel-B70-Pro/benchmarks](https://github.com/heikogleu-dev/Openfoam13---GPU-Offloading-Intel-B70-Pro/tree/main/benchmarks) —
  the Ginkgo path, same hardware, same CFD case
- [conclusions.md](../conclusions.md#performance-not-yet-a-win) —
  why Stufe 2's 17× slowdown is expected and not a defect
- [hardware.md](../hardware.md) — measured FP64 / VRAM / kernel-launch
  characteristics of the underlying B70 silicon
