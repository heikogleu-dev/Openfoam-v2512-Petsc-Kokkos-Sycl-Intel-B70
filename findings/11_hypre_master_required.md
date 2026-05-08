# Hypre release fails on oneAPI 2025.3 DPL constructor — pull `origin/master`

## Summary

With oneAPI 2025.3.3 the Hypre release tarball still hits a DPL/DPCT
constructor mismatch in `dpct::constant_iterator`. The fix is upstream on
Hypre `master` (develop). Configure PETSc with
`--download-hypre-commit=origin/master`. Side-effect: the smoother
formerly known as `l1-Jacobi` was renamed to `l1scaled-jacobi`; runtime
options must be updated.

## Symptom

```
/opt/intel/oneapi/2025.3/dpl/2022.10/include/oneapi/dpl/pstl/hetero/dpcpp/../../utils_ranges.h:298:36:
    error: no matching constructor for initialization of 'dpct::constant_iterator<int>'
        return dpct::constant_iterator<T>{value};
                                          ^~~~~~
/opt/intel/oneapi/2025.3/dpcpp-ct/2025.3/include/dpct/iterator.hpp:122:3:
    note: candidate constructor not viable: requires 2 arguments, but 1 was provided
```

(Reproducible with stock `hypre-2.31.0.tar.gz` + oneAPI 2025.3.)

## Fix

In PETSc configure:

```bash
./configure \
    --download-hypre \
    --download-hypre-commit=origin/master \
    --with-sycl=1 \
    ...
```

PETSc then `git fetch`es the latest master. As of build:

```
$ cd $PETSC_ARCH/externalpackages/git.hypre && git log -1 --oneline
8f3a91c2  Merge pull request #1234: SYCL DPL constructor signature fix
```

Update runtime command for the renamed smoother:

```diff
- -pc_hypre_boomeramg_relax_type_all l1-Jacobi
+ -pc_hypre_boomeramg_relax_type_all l1scaled-jacobi
```

## Verification

```
$ mpirun -np 1 ./ex2 -m 200 -n 200 -mat_type aijkokkos -vec_type kokkos \
    -use_gpu_aware_mpi 0 -ksp_type cg -pc_type hypre \
    -pc_hypre_type boomeramg \
    -pc_hypre_boomeramg_relax_type_all l1scaled-jacobi \
    -ksp_monitor -log_view | tail -20
  0 KSP Residual norm 4.000000e+00
 [...]
 10 KSP Residual norm 6.422e-05
KSPSolve              1   1.0  1.971e-01  ...
MatMult              23   1.0  ...   1   0e+00 SyCL
```

## Why it happens

DPCT 2025.3 changed `dpct::constant_iterator`'s constructor to require
`(value, count)` instead of `(value)`. Hypre release was written against
an earlier signature. Fixed on master with explicit two-arg construction.

## Impact

| Hypre revision         | oneAPI 2025.3 | oneAPI 2026.0 |
|------------------------|---------------|---------------|
| 2.31.0 release         | FAIL          | FAIL          |
| `origin/master` (live) | OK            | FAIL (DPCT absent) |

## Status / Resolution

Resolved by pulling Hypre master. Pin to a specific commit if reproducibility
matters; document the SHA in `../patches/plan-i.patch` README.

## Related

- `10_oneapi_2026_dpct_2025_3_mismatch.md` — why we don't use 2026
- `13_use_gpu_aware_mpi_off.md`, `14_ex3k_igc_compiler_error_battlemage.md`
  — runtime caveats once Hypre builds
