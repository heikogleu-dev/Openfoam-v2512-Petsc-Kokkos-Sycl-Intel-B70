# oneAPI `setvars.sh` puts Intel-MPI ahead of system OpenMPI — repair PATH

## Summary

Sourcing `/opt/intel/oneapi/setvars.sh` prepends Intel-MPI's `bin/` to the
shell PATH. ESI OpenFOAM v2512 was built with `FOAM_MPI=sys-openmpi` against
`/usr/bin/mpicc` (system OpenMPI 5.x). PETSc must use the **same** MPI for
later coupling with PETSc4FOAM. Repair PATH after sourcing oneAPI, then pass
explicit MPI wrappers to PETSc and force the wrappers to call `icx`/`icpx`
underneath via `OMPI_CC` / `OMPI_CXX`.

## Symptom

After `source /opt/intel/oneapi/setvars.sh` the wrong `mpicc` resolves
first:

```
$ which mpicc
/opt/intel/oneapi/mpi/2025.3/bin/mpicc

$ mpicc -show
icx -ilp64 -lmpi  -L/opt/intel/oneapi/mpi/2025.3/lib  ...
```

A PETSc configure that picks this up will link against `libmpi` from
Intel-MPI and segfault when loaded next to OpenFOAM-built `libPstream.so`.

## Fix

```bash
source /opt/intel/oneapi/2025.3/oneapi-vars.sh
# Repair PATH: system bins first
export PATH=/usr/bin:/usr/local/bin:$PATH

# Tell OpenMPI's wrappers to call Intel compilers under the hood:
export OMPI_CC=icx
export OMPI_CXX=icpx
export OMPI_FC=ifx

# Sanity:
mpicc -show | head -1     # expect: icx ... -L/usr/lib/x86_64-linux-gnu/openmpi/lib ...
mpicxx -show | head -1
```

PETSc configure flags (excerpt):

```bash
./configure \
    --with-cc=/usr/bin/mpicc \
    --with-cxx=/usr/bin/mpicxx \
    --with-fc=/usr/bin/mpif90 \
    --with-mpiexec=/usr/bin/mpiexec \
    --with-sycl --with-sycl-arch=intel_gpu_bmg_g31 \
    ...
```

## Why it happens

oneAPI's `setvars.sh` is opinionated: it assumes Intel-MPI is the desired
runtime. There is no `--mpi=none` switch. Either skip the MPI module
(`source setvars.sh --include-intel-llvm` style is not supported in 2025.3)
or prepend the system PATH afterwards.

## Impact

| Tool       | Resolves to                                           |
|------------|-------------------------------------------------------|
| `mpicc`    | `/usr/bin/mpicc`  (OpenMPI wrapper, calls `icx`)      |
| `mpicxx`   | `/usr/bin/mpicxx` (OpenMPI wrapper, calls `icpx`)     |
| `icx`      | `/opt/intel/oneapi/2025.3/bin/icx`                    |
| `sycl-ls`  | `/opt/intel/oneapi/2025.3/bin/sycl-ls`                |

PETSc and OpenFOAM share `libmpi.so.40` from `/usr/lib/x86_64-linux-gnu/`.
Coupling via PETSc4FOAM works.

## Status / Resolution

Worked around in `setup/02_env_petsc.sh`; no upstream change.

## Related

- `04_set_u_bashrc_184_unbound.md` — predecessor in the env-load chain
- `10_oneapi_2026_dpct_2025_3_mismatch.md` — why we use 2025.3 specifically
- `13_use_gpu_aware_mpi_off.md` — runtime consequence of the OpenMPI choice
