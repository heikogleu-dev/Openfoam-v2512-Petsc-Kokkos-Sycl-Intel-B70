# Hardware Diagnostic Run — 2026-05-10

Three standalone SpMV/CG tests, all on the same Intel Arc Pro B70
(BMG-G31), all consuming the same 1M × 1M Poisson 5-point stencil
matrix (~5M nnz). Tests built and run outside the OpenFOAM stack to
isolate hardware/runtime behavior from wrapper-layer effects.

| File | Stack | Test | ms / iter | BW |
|---|---|---|---|---|
| `test1_onemkl.log.gz` | oneMKL Sparse | full CG loop | 0.741 | 161 GB/s |
| `test3a_petsc.log.gz` | PETSc aijkokkos (β5h2 Release) | pure SpMV | 0.287 | 418 GB/s |
| `test3b_ginkgo.log.gz` | Ginkgo dpcpp (/opt/ginkgo) | pure SpMV | 0.089 | 1340 GB/s\* |

\* Cache-resident `x` (8 MB fits in B70's 12 MB L2). Reported BW is
arithmetic; physical peak is 608 GB/s.

See findings 23-26 for interpretation. Reproducer source under
`/home/heiko/diag/` on the Tavea-Station workstation (not in this repo
— diagnostic scratch space).
