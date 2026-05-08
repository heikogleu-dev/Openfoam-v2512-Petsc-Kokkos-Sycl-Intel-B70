# System OpenMPI is not SYCL-GPU-aware — set `-use_gpu_aware_mpi 0`

## Summary

PETSc built with `--with-sycl` defaults to assuming the MPI runtime can
handle SYCL device pointers in `MPI_Send`/`MPI_Recv`. Ubuntu 26.04's
system OpenMPI 5.x has no SYCL adapter; first MPI exchange aborts with
PETSc errorcode 76. Disable GPU-aware MPI globally
(`PETSC_OPTIONS="-use_gpu_aware_mpi 0"` or `~/.petscrc`). PETSc falls back
to a host-buffer staging round-trip — small overhead, behavior is
correct.

## Symptom

```
$ mpirun -np 2 ./ex2 -m 200 -n 200 -mat_type aijkokkos -vec_type kokkos \
                    -ksp_type cg -pc_type none
[0]PETSC ERROR: --------------------- Error Message --------------------
[0]PETSC ERROR: PETSc is configured with sycl support, but your MPI is
                not aware of sycl GPU devices. For better performance,
                please use a sycl GPU-aware MPI.
[0]PETSC ERROR: If you do not care, add option -use_gpu_aware_mpi 0.
[0]PETSC ERROR: To not check for this initially, set the environmental
                variable PETSC_HAVE_GPU_AWARE_MPI to 0.
[0]PETSC ERROR: #1 PetscDeviceCheckForGpuAwareMpi() at .../impls/sycl/...
[0]PETSC ERROR: ----------------------------------------------------
MPI_ABORT was invoked on rank 0 ... with errorcode 76.
```

## Fix (pick one)

```bash
# 1) Explicit per-run flag
mpirun -np 2 ./ex2 ... -use_gpu_aware_mpi 0

# 2) Env var (covers all PETSc apps, incl. PETSc4FOAM)
export PETSC_OPTIONS="-use_gpu_aware_mpi 0"

# 3) ~/.petscrc — persistent, machine-local
echo "-use_gpu_aware_mpi 0" >> ~/.petscrc
```

`~/.petscrc` is read by every `PetscInitialize`, including PETSc4FOAM
launches from `simpleFoam` / `pimpleFoam`.

## Why it happens

`PetscDeviceCheckForGpuAwareMpi()` does a probe of MPI's CUDA/HIP/SYCL
attribute set. OpenMPI 5.x in Ubuntu 26.04 advertises CUDA awareness only
when built `--with-cuda`; it has no SYCL adapter at all. There is no
upstream OpenMPI patch for SYCL pointers as of this writing.

## Performance penalty

For our verification problem (poisson 200×200 on B70):

| Configuration                        | KSPSolve time |
|--------------------------------------|---------------|
| `-use_gpu_aware_mpi 0`, ranks=1      | 0.197 s       |
| `-use_gpu_aware_mpi 0`, ranks=2      | 0.241 s       |
| GPU-aware MPI                        | n/a (would need MPICH+ZE backend) |

For a single-GPU node like ours the flag is effectively free: only intra-rank
halo exchanges hit the host buffer, and there is only one rank using the GPU.

## Impact

- All GPU runs work after adding the flag.
- PETSc4FOAM coupling needs the same flag in its solver dictionary
  (`solvers { p { ... petsc_options "-use_gpu_aware_mpi 0"; } }`).
- Switch to MPICH + Level-Zero for true GPU-aware multi-GPU later.

## Status / Resolution

Worked around at the option level. Production runs add the flag via
`~/.petscrc`.

## Related

- `05_oneapi_intel_mpi_path_priority.md` — why we use system OpenMPI
- `14_ex3k_igc_compiler_error_battlemage.md` — separate runtime issue
