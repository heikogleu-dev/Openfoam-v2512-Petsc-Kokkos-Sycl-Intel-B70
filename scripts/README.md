# Build Scripts

Reproducible build entry points. Both run in `bash --noprofile --norc`
(no inherited Foundation OF13 environment) and use `set -o pipefail`
without `-u` (see [findings/04](../findings/04_set_u_bashrc_184_unbound.md)).

| File | Purpose | Runtime | Idempotent |
|---|---|---|---|
| [`stufe1-esi-v2512-tarball.sh`](stufe1-esi-v2512-tarball.sh) | Stufe 1: build ESI OpenFOAM v2512 from `dl.openfoam.com` tarballs | 30–45 min | yes (skips re-download / re-extract) |
| [`stufe2-petsc.sh`](stufe2-petsc.sh) | Stufe 2: PETSc 3.25.1 + Kokkos + KokkosKernels (BATCHED-off) + Hypre develop + SYCL on B70 | 30–60 min | yes (cleans `$PETSC_ARCH` build state but keeps tarball cache) |

Both scripts assume the prerequisites in [`setup/install_stack.md`](../setup/install_stack.md)
are met:
- `/opt/openfoam-v2512/` exists and is writable by the user
- Stufe 1 packages (`bison`, `libboost-system-dev`, …, `libscotchparmetis-dev`)
  are installed
- Stufe 2 packages (`opencl-headers`, `ocl-icd-opencl-dev`) are installed
- oneAPI 2025.3.3 lives at `/opt/intel/oneapi/2025.3/`
- Pre-patched KokkosKernels tarball is at
  `/opt/openfoam-v2512/tarballs/kokkos-kernels-5.1.0-plan-i.tar.gz`

## Why bash --noprofile --norc

The system has Foundation OpenFOAM 13 sourced in the user's login profile
(`/opt/openfoam13/etc/bashrc`). Building ESI v2512 in a shell that already
has v13 environment variables produces silent ABI mismatches. Always
launch the scripts in a fresh shell:

```bash
bash --noprofile --norc /home/heiko/petsc4foam-repo/scripts/stufe2-petsc.sh \
  > /tmp/stufe2-master.log 2>&1
```

## License

Both scripts are own work, GPL-3.0-or-later (see [LICENSE](../LICENSE)).
They invoke (do not redistribute) third-party tooling — see [NOTICE.md](../NOTICE.md).
