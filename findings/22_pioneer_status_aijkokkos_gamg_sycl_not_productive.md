# Pioneer Status: aijkokkos + GAMG + SYCL Is Not Productive on BMG-G31 in May 2026

## Summary

After 13 build iterations (Plan A through Plan I), one Plan I++ patch,
β5/β5b/β5c/β5h/β5h2 reconfigurations, an F1 debug rebuild, the
F-PRE workaround series, and the 5e non-AMG validation, the picture
becomes clear:

**As of May 2026, six months after Battlemage BMG-G31 launched, the
combination `aijkokkos` + `pc_type gamg` + SYCL backend on real Intel
discrete GPU hardware is not productive.** The combination builds and
links, but execution crashes at the source level in shared
PETSc-Kokkos GAMG initialization code (finding 19), and the only build
that bypasses the crash (debug-build, finding 20) does so at 3× cost
plus routes the actual SPGEMM work to CPU.

We are very likely the first independent group to stress-test this
combination on production-grade Intel discrete GPU hardware.

## Why We're Probably the First

PETSc CI coverage for SYCL:

```
.gitlab-ci.yml  configuration  linux-sycl-double:
  Image:    Ubuntu 22.04
  oneAPI:   2022.0.2
  Hardware: Ivybridge CPU only (no GPU)
  Tests:    vec/kokkos basic ops, mat/kokkos basic ops
  Coverage: NOT GAMG, NOT SPGEMM, NOT real GPU
```

Aurora at Argonne National Lab has Intel PVC hardware (the Aurora
supercomputer) — but Aurora is internal ANL, behind their job
scheduler, with custom toolchain pinned to oneAPI 2023.10.15.002. The
Aurora team validates Kokkos/PETSc on PVC, but that validation does
not transfer to Battlemage (different device-id `0xe223` vs PVC
`12.60.7`, different driver paths).

Mark Adams (PETSc maintainer) reported in `petsc-dev` October 2023
that Stephan Kramer encountered a similar `MatProductSymbolic_SeqAIJKokkos`
crash with GAMG on a different hardware and noted "I'm suspecting a
bug in `MatEliminateZeros()`". That thread did not reach a publicly
documented resolution for GAMG + aijkokkos + SYCL.

Public GitHub issue search (May 2026):

- petsc/petsc, kokkos/kokkos, kokkos/kokkos-kernels — no open issue
  matching `aijkokkos GAMG SEGV Battlemage` or `BMG_G31`
- Sister repos for Battlemage CFD (Hal9000AIML, PMZFX) work on
  Foundation OpenFOAM 13 with Ginkgo or pure CPU paths, not on
  PETSc-Kokkos-SYCL

The PETSc 3.25.1 default Kokkos commit is `5.1.0` (released Q1 2025,
about one quarter post-Battlemage launch). KokkosKernels 5.1.0 has
no Battlemage-specific paths. KokkosKernels develop (May 2026) added
exactly one B70-relevant change (`Use Intel SYCL extension to query
device free memory`, commit `6620b0a`) — useful for our build, but
does not address the SPGEMM / GAMG construction issue.

## What "Pioneer Status" Means Here

This repo documents the first end-to-end attempt to run PETSc-Kokkos
on Intel Arc Pro B70 (BMG-G31) for production CFD via petsc4Foam.
The build pipeline works. The Foundation pressure-equation path
works. The non-AMG GPU preconditioner path (finding 21, Eta) works.

The AMG path does not work, and at the source level the crash sits
deeper than configuration can reach (finding 19). Until either:

1. PETSc upstream fixes the memory-safety bug in
   `MatProductSymbolic_SeqAIJKokkos` / `PCGAMGCreateGraph_AGG` (or
   wherever the actual fault sits — debug build heals it), AND
2. KokkosKernels gains a real on-device SPGEMM path for Battlemage
   that doesn't fall back to CPU,

the GAMG-on-aijkokkos path on BMG-G31 will not be productively faster
than the CPU baseline.

## Estimate for Resolution

Based on the cadence of Battlemage support patches in upstream Kokkos
develop and PETSc release cycles, plus the fact that PETSc CI does
not currently exercise GAMG on real Intel GPU, we estimate:

- **6 months minimum** before a Kokkos release with hardened B70 SYCL
- **9–12 months** before PETSc CI gains real Intel-GPU coverage for
  GAMG+aijkokkos paths
- **6–18 months** before a fix lands that actually moves SPGEMM onto
  the device for BMG-G31

In the interim:
- **For benchmarking studies on B70**: Eta (chebyshev+jacobi) is the
  honest GPU PC path
- **For production CFD on B70**: stay on Foundation OpenFOAM 13 + CPU
  GAMG + GPU-acceleration via different libraries (Ginkgo, OGL, etc.)
  as the sister repo demonstrates

## Why Document This Anyway

The build pipeline is the value here. Plan I + β5h2 represent a
reproducible recipe for getting PETSc 3.25.1 + Kokkos + KokkosKernels
+ Hypre + SYCL onto Battlemage. Everything *up to* the AMG layer
works. The next person tackling this hardware/software combination
should not re-derive Plans A through Plan I; they should start where
β5h2 leaves off and address the AMG-path source-level question
directly.

## What Still Has Value in This Repo

| Asset | Value |
|---|---|
| `scripts/stufe2-petsc.sh` | Reproducible β5h2 build, ≈52 min from scratch |
| `findings/01-22` | Full debugging trail; 22 distinct issues identified and either resolved or documented as upstream-blocked |
| `configs/validated/` | Working fvSolution dictionaries for cavity sanity (Foundation, Eta) |
| `kokkos-kernels-develop-plan-i.tar.gz` | KK develop with the 3 Plan-I BATCHED patches; ext_intel_free_memory is upstream and works |
| Repo as a whole | First independent end-to-end documentation of PETSc-Kokkos-SYCL on Battlemage |

## Open Questions for Upstream

1. PETSc petsc-dev list: file a reproducer for the `MatProductSymbolic_SeqAIJKokkos`
   SEGV with simple cavity case + B70 hardware specs
2. KokkosKernels: ask whether SPGEMM has any Battlemage validation or
   a known-broken status
3. petsc4Foam (ESI): the `-vec_type` prefix gap (finding 16) is small
   and could be fixed quickly upstream

## Status / Resolution

**Pioneer status documented.** Re-evaluate when one of:

- Kokkos 5.2.0+ with explicit BMG-G31 arch flag
- KokkosKernels stable with BMG-validated SPGEMM
- PETSc CI integrating real Intel-GPU GAMG coverage
- An upstream fix to the Release SEGV identified in finding 19

is publicly available. ETA: 6–18 months from May 2026.

## Related

- All 21 prior findings — every one is part of this conclusion
- Sister repo: `heikogleu-dev/Openfoam13---GPU-Offloading-Intel-B70-Pro` — alternative GPU path
