# `make check` ex3k triggers IGC ICE on Battlemage — backend bug, ignore for ILU

## Summary

PETSc's `make check` runs `ex3k` with `-mat_type aijkokkos -pc_type ilu`,
which calls `MatILUFactorNumeric_SeqAIJKokkos_ILU0()` and invokes
KokkosSparse experimental `spiluk`. JIT-compiling that kernel for
Battlemage fires off an IGC (Intel Graphics Compiler) Internal Compiler
Error. Rank 0 also SEGVs and rank 1 reports "Termination request sent."
This is a backend defect, not a build problem. ex19 and ex19+HYPRE — our
actual sanity targets — pass.

## Symptom

```
$ make check
[...]
Running check examples to verify correctness
[...]
6,13c6,13
< Norm of error 0.000119835
< Norm of error 9.0046e-05
< Norm of error 4.5187e-05
< Norm of error 2.2664e-05
[...]
> Possible problem with ex3k_kokkos, diffs above
[0]PETSC ERROR: Caught signal number 11 SEGV: Segmentation Violation
[1] IGC: Internal Compiler Error: Termination request sent to the program
[1]PETSC ERROR: KSP_DIVERGED_PC_FAILED, 1, ...
```

Stack trace (excerpt):

```
#1 zeKernelCreate -> IGC build kernel
#2 KokkosSparse::Experimental::spiluk_numeric_impl<...>
#3 MatILUFactorNumeric_SeqAIJKokkos_ILU0
#4 PCSetUp_ILU
#5 KSPSolve
```

## Verified-passing checks

```
$ mpirun -np 1 ./ex19 -da_refine 3 -pc_type mg -mat_type aijkokkos -vec_type kokkos \
                     -use_gpu_aware_mpi 0
lid velocity = 0.0625, prandtl # = 1, grashof # = 1
Number of SNES iterations = 2
$ echo $?
0

$ mpirun -np 1 ./ex19 -da_refine 3 -pc_type hypre -pc_hypre_type boomeramg \
                     -mat_type aijkokkos -vec_type kokkos -use_gpu_aware_mpi 0
Number of SNES iterations = 2
```

Plus the canonical ex2 + Hypre run from finding 11.

## Workaround for production

Drop `-pc_type ilu` for any Kokkos matrix. Use:

| Replacement              | Notes |
|--------------------------|-------|
| `-pc_type hypre -pc_hypre_type boomeramg` | works, well-tested |
| `-pc_type gamg`          | works, CPU-resident setup |
| `-pc_type none` (testing)| works |
| `-pc_type ilu` on `aij` (CPU) | works but defeats the point |

Update `~/.petscrc` in CFD case dictionaries:

```
-pc_type hypre
-pc_hypre_type boomeramg
-pc_hypre_boomeramg_relax_type_all l1scaled-jacobi
```

## Why it happens

Triple stack: Kokkos experimental `spiluk` emits SYCL kernels with deep
nested loops + atomic accumulators; IGC for bmg_g31 mishandles the loop
unrolling pass and aborts the back-end compile. Reported on Intel's
issue tracker for compute-runtime; no fix in `intel-graphics-compiler`
as of 2026-05.

## Impact

- `make check` reports a non-zero diff but otherwise the PETSc build is
  good.
- Production PETSc4FOAM coupling for OpenFOAM CFD does not use ILU on
  GPU matrices (BoomerAMG is preferred anyway).
- ex3k can be skipped via `make check OMIT_TESTS="ex3k_kokkos"`.

## Reproduction

```
$ cd $PETSC_DIR/src/ksp/ksp/tutorials && make ex3k
$ ./ex3k -mat_type aijkokkos -pc_type ilu -ksp_monitor 2>&1 | grep -E 'IGC|SEGV'
```

## Status / Resolution

Backend bug to live with. Production runs avoid the code path.
Re-test after every `intel-opencl-icd` / `intel-level-zero-gpu` upgrade.

## Related

- `06_legacy_ocloc_no_battlemage_aot_jit_fallback.md` — JIT path exposed here
- `11_hypre_master_required.md` — the AMG alternative we actually use
- `13_use_gpu_aware_mpi_off.md` — runtime flag also required for ex19
