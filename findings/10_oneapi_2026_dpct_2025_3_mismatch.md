# oneAPI 2026.0 ships no DPCT — DPL still imports it; install 2025.3 in parallel

## Summary

Initial Plan-I attempt with the freshly-released oneAPI 2026.0.0 (icpx
build `2026.0.0.20260331`) failed because Intel deprecated DPCT for the
2026 train but the bundled DPL 2022.10 still references DPCT API. Worse,
icpx 2026's SYCL headers removed `sycl::ext::oneapi::experimental::get_tangle_group`
and `get_fixed_size_group` which DPCT 2025.3 still uses — so a Hypre release
build that pulls the older DPCT also fails. Solution: install oneAPI 2025.3
in parallel, source 2025.3 by preference.

## Symptom 1 — oneAPI 2026 missing DPCT module

```
$ ls /opt/intel/oneapi/dpct
ls: cannot access '/opt/intel/oneapi/dpct': No such file or directory
$ ls /opt/intel/oneapi/2026.0/dpcpp-ct 2>/dev/null
(empty)
```

## Symptom 2 — DPL 2022.10 references missing SYCL API

```
/opt/intel/oneapi/2026.0/dpl/2022.10/include/oneapi/dpl/pstl/hetero/dpcpp/parallel_backend_sycl.h:412:
    error: no member named 'get_tangle_group' in namespace 'sycl::ext::oneapi::experimental'
/opt/intel/oneapi/2026.0/dpl/2022.10/include/.../parallel_backend_sycl_radix_sort.h:88:
    error: no member named 'get_fixed_size_group' in namespace 'sycl::ext::oneapi::experimental'
```

## Symptom 3 — Hypre release build fails through DPL

```
hypre/src/sycl/_hypre_sycl_complex.cpp:24: in instantiation of 'oneapi::dpl::experimental::ranges::...'
   from /opt/intel/oneapi/2026.0/dpl/2022.10/include/...
```

## Fix

Install oneAPI 2025.3.2 offline installer (writes itself in as 2025.3.3
internally — Intel's quirk):

```bash
sudo bash intel-oneapi-base-toolkit-2025.3.2.21_offline.sh \
     --silent --eula accept --components all --install-dir /opt/intel/oneapi
```

Both versions coexist under `/opt/intel/oneapi/` (2025.3 and 2026.0
sub-trees). Source the older one explicitly:

```bash
source /opt/intel/oneapi/2025.3/oneapi-vars.sh    # NOT setvars.sh
icpx --version
# Intel(R) oneAPI DPC++/C++ Compiler 2025.3.3 (2025.3.3.20260319)
```

Verify DPCT is present in 2025.3:

```
$ ls /opt/intel/oneapi/2025.3/dpcpp-ct/2025.3/include/dpct
dpct.hpp  device.hpp  memory.hpp  ...
```

## Why it happens

Intel split DPCT off the toolkit at oneAPI 2026 (announced Q1 2026, see
release notes). DPL 2022.10 was packaged for both trains but its SYCL
backend uses pre-2026 experimental APIs. Mixing the 2026 compiler with
the 2026 DPL is internally consistent only for projects that don't touch
those code paths; Hypre and PETSc + KokkosKernels do.

## Impact

| Stack                           | Status |
|---------------------------------|--------|
| oneAPI 2026.0 + Hypre release   | FAIL (DPL/SYCL API mismatch) |
| oneAPI 2026.0 + Hypre master    | FAIL (DPCT absent)            |
| oneAPI 2025.3.3 + Hypre release | FAIL (different reason, see 11)|
| oneAPI 2025.3.3 + Hypre master  | OK   <-- our final stack       |

## Status / Resolution

Worked around. Long-term: wait for Hypre release to catch up to oneAPI 2026
DPL or for Intel to ship a 2026-DPCT replacement.

## Related

- `11_hypre_master_required.md` — the second half of the toolchain match-up
- `05_oneapi_intel_mpi_path_priority.md` — how we source 2025.3 cleanly
