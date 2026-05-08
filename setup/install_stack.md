# Installation Stack — Reproducing the Build End-to-End

> All commands assume Ubuntu 26.04 LTS (resolute), kernel 7.0.0+, GCC 15.2,
> and an Intel Arc Pro B70 Pro on a PCIe 5.0 ×16 slot. See
> [hardware.md](../hardware.md) and [bios_settings.md](bios_settings.md)
> for prerequisites.

The build is split into two stages:

1. **Stufe 1** — ESI OpenFOAM v2512 alongside Foundation 13
2. **Stufe 2** — PETSc + Kokkos + KokkosKernels + Hypre + SYCL with the
   Plan I patches applied

End-to-end ≈ 60–90 min on 24 cores after Plan I is in place.

---

## Stufe 0 — Pre-flight Verifications

```bash
# Verify GPU enumerated by SYCL
sycl-ls | grep 0xe223                   # expect: B70 Pro line via level_zero
ls /dev/dri/                            # expect: card0/1, renderD128/129

# Disk space (Stufe 1 ≈ 5 GB, Stufe 2 ≈ 25 GB build, ≈ 4 GB final install)
df -BG /opt                             # expect: ≥ 50 GB free

# Foundation 13 isolation check
[[ -d /opt/openfoam13 ]] && echo "v13 present — will not be modified"

# sudo / pkexec strategy: this system has no TTY-sudo; pkexec works via
# GUI auth. All privileged steps below pass through ONE pkexec call so
# Heiko gets a single auth dialog.
which pkexec
```

---

## Stufe 1 — ESI OpenFOAM v2512

The ESI repo `develop.openfoam.com/Development/openfoam` was privatised
(HTTP 302 → /users/sign_in) — see [findings/03](../findings/03_esi_repo_login_required_tarball_fallback.md).
We use the public tarball mirror.

### 1a) System packages (one pkexec auth)

```bash
pkexec bash -c '
set -e
mkdir -p /opt/openfoam-v2512
chown $SUDO_USER:$SUDO_USER /opt/openfoam-v2512
DEBIAN_FRONTEND=noninteractive apt update
DEBIAN_FRONTEND=noninteractive apt install -y \
  bison libboost-system-dev libboost-thread-dev libfftw3-dev \
  libscotch-dev libptscotch-dev libcgal-dev libmetis-dev \
  libscotchparmetis-dev
'
```

Note the swap `libparmetis-dev` → `libscotchparmetis-dev`
([findings/01](../findings/01_libparmetis_replaced_libscotchparmetis_u26.md));
required only on Ubuntu 26.04+.

### 1b) Run the build script

```bash
bash --noprofile --norc /path/to/repo/scripts/stufe1-esi-v2512-tarball.sh \
  > /tmp/stufe1-master.log 2>&1
echo "rc=$?"
```

The script downloads `OpenFOAM-v2512.tgz` and `ThirdParty-v2512.tar.gz`
from `dl.openfoam.com`, extracts, builds. After the ThirdParty step it
patches `etc/config.sh/scotch` to use system Scotch (since bundled
`scotch_6.1.0` does not compile under GCC 15 — see
[findings/02](../findings/02_scotch_6_1_0_gcc15_strict_prototype.md)) and
rebuilds only the two decompose libs.

End state:
- `/opt/openfoam-v2512/OpenFOAM-v2512/` (source + built libs)
- `/opt/openfoam-v2512/ThirdParty-v2512/`
- `etc/config.sh/scotch` modified: `SCOTCH_VERSION=scotch-system`
- Sanity: `icoFoam cavity` (serial) and parallel-4 (`scotch` decompose)
  both end with `End` and `reconstructPar` OK

### 1c) Sourcing convention

```bash
# In a bash --noprofile --norc shell, do NOT use set -u (see findings/04)
set -o pipefail
source /opt/openfoam-v2512/OpenFOAM-v2512/etc/bashrc \
  WM_COMPILER=Gcc WM_LABEL_SIZE=32 WM_PRECISION_OPTION=DP WM_COMPILE_OPTION=Opt
echo "$WM_PROJECT_DIR"   # /opt/openfoam-v2512/OpenFOAM-v2512
```

---

## Stufe 2 — PETSc + Kokkos + Hypre + SYCL (Plan I)

### 2a) oneAPI 2025.3.3 install (mandatory, NOT 2026)

```bash
mkdir -p /opt/openfoam-v2512/tarballs && cd /opt/openfoam-v2512/tarballs

wget -O intel-oneapi-base-toolkit-2025.3.2.21_offline.sh \
  https://registrationcenter-download.intel.com/akdlm/IRC_NAS/99f4837a-25b7-425d-a897-60af022676ea/intel-oneapi-base-toolkit-2025.3.2.21_offline.sh

# 2.65 GB, ~5–15 min depending on bandwidth

pkexec sh ./intel-oneapi-base-toolkit-2025.3.2.21_offline.sh \
  -a --silent --eula accept --cli \
  --install-dir /opt/intel/oneapi/2025.3
# warning "Ubuntu 26.04 untested" is benign; install completes "successfully"
```

End state:
- `/opt/intel/oneapi/2025.3/setvars.sh` exists
- `/opt/intel/oneapi/2025.3/compiler/2025.3/bin/icpx` reports version
  `2025.3.3 (2025.3.3.20260319)`
- Internal DPCT (`dpcpp-ct/2025.3/`) matches icpx 2025.3 — no version
  mismatch (cf. [findings/10](../findings/10_oneapi_2026_dpct_2025_3_mismatch.md))

### 2b) Two extra apt packages

```bash
pkexec apt install -y opencl-headers ocl-icd-opencl-dev
# level-zero-dev is NOT needed: libze-dev (1.28.2-2) already installed
# xpu-smi is NOT in U26.04 repos: we use intel_gpu_top instead
```

### 2c) Pre-patch the KokkosKernels tarball

```bash
cd /opt/openfoam-v2512/tarballs
wget https://github.com/kokkos/kokkos-kernels/archive/refs/tags/5.1.0.tar.gz
tar xzf 5.1.0.tar.gz
sed -i 's|^  set(KokkosKernels_ENABLE_COMPONENT_BATCHED ON CACHE BOOL "" FORCE)$|  # Plan I disabled (was: \0)|' \
  kokkos-kernels-5.1.0/cmake/kokkoskernels_components.cmake
grep -c "Plan I" kokkos-kernels-5.1.0/cmake/kokkoskernels_components.cmake   # expect 3
tar czf kokkos-kernels-5.1.0-plan-i.tar.gz kokkos-kernels-5.1.0
```

Why this works: PETSc accepts `--download-kokkos-kernels=file:///path/to/...tar.gz`
and extracts the local archive instead of git-cloning the upstream repo,
so our patches survive (cf. [findings/09](../findings/09_petsc_local_tarball_file_url.md)).

### 2d) Run the Stufe 2 build script

```bash
bash --noprofile --norc /path/to/repo/scripts/stufe2-petsc.sh \
  > /tmp/stufe2-master.log 2>&1
```

The script:
1. Sources ESI v2512 bashrc
2. Sources `/opt/intel/oneapi/2025.3/setvars.sh --force`
3. Re-prepends `/usr/bin` to PATH (so `mpicc` resolves to System-OpenMPI,
   not Intel-MPI; cf. [findings/05](../findings/05_oneapi_intel_mpi_path_priority.md))
4. Exports `OMPI_CC=icx OMPI_CXX=icpx` (so OpenMPI wrappers use the
   Intel compilers under `-fsycl` builds)
5. Downloads PETSc 3.25.1 tarball, extracts
6. Applies the [aijkok patch](../patches/plan-i.patch) (idempotent — skipped
   if already applied)
7. Runs PETSc `configure` with the Plan I option set:
   ```
   --with-cc=/usr/bin/mpicc --with-cxx=/usr/bin/mpicxx --with-fc=0
   --with-debugging=0
   --SYCLFLAGS='-fsycl' --with-sycl --with-syclc=icpx
   --with-blaslapack-dir=$MKLROOT
   --download-kokkos
   --download-kokkos-kernels=file:///opt/openfoam-v2512/tarballs/kokkos-kernels-5.1.0-plan-i.tar.gz
   --download-hypre --download-hypre-commit=origin/master
   --download-hypre-configure-arguments='--enable-unified-memory'
   --download-umpire --download-caliper
   ```
8. Builds PETSc (`make all`)
9. Runs `make check` — only ex19 + ex19+HYPRE matter; ex3k IGC ICE is
   tolerated ([findings/14](../findings/14_ex3k_igc_compiler_error_battlemage.md))
10. Builds + runs ex2 200×200 sanity (CPU baseline + GPU run)
11. Prints Phase-7 Bericht with Configure/Build durations and convergence

### 2e) Apply patches if not running the script

If you build PETSc by hand instead of via the script, apply the
[`aijkok.kokkos.cxx` patch from `patches/plan-i.patch`](../patches/plan-i.patch)
**after** PETSc extracts but **before** `make`:

```bash
cd $PETSC_DIR
sed -i 's|^#include <KokkosBatched_LU_Decl\.hpp>$|// Plan I: \0|' \
  src/mat/impls/aij/seq/kokkos/aijkok.kokkos.cxx
sed -i 's|^#include <KokkosBatched_InverseLU_Decl\.hpp>$|// Plan I: \0|' \
  src/mat/impls/aij/seq/kokkos/aijkok.kokkos.cxx
# … plus the function-body replacement (do this with an editor; see
# patches/plan-i.patch for the exact diff)
```

---

## Verification

```bash
cd $PETSC_DIR/src/ksp/ksp/tutorials
mpirun -np 1 ./ex2 -m 200 -n 200 \
  -mat_type aijkokkos -vec_type kokkos \
  -use_gpu_aware_mpi 0 \
  -ksp_type cg -pc_type hypre -pc_hypre_type boomeramg \
  -pc_hypre_boomeramg_relax_type_all l1scaled-jacobi \
  -ksp_monitor -ksp_max_it 200 -log_view
```

Expected `Norm of error 6.40488e-05 iterations 9` (small problem, JIT
overhead dominates — the GPU run will be ≈17× slower than the same
options without `-mat_type aijkokkos`. This is normal at this scale).

`-log_view` should mention `MatMult_SeqAIJKokkos`, `VecKokkos` and a
SYCL-tagged execution space.

`ldd ./ex2 | grep sycl` should resolve `libsycl.so.8` to
`/opt/intel/oneapi/2025.3/compiler/2025.3/lib/`. If it points to the
2026 path, your shell still has the wrong oneAPI sourced.

---

## Common Gotchas

| Symptom | Likely Cause | Fix |
|---|---|---|
| `mpicc -show` invokes Intel-MPI's hydra | oneAPI sourced **after** other PATH set-ups | put `/usr/bin` first; see [findings/05](../findings/05_oneapi_intel_mpi_path_priority.md) |
| `Bad linker flag: -fsycl` | `OMPI_CXX` missing or set to g++ | export `OMPI_CC=icx OMPI_CXX=icpx` before configure |
| `Could not determine device target: bmg_g31` | `-fsycl-targets=intel_gpu_bmg_g31` triggers AOT through legacy `/usr/bin/ocloc` | drop the flag; use JIT |
| `BATCHED: ON` despite `-DKK_ENABLE_BATCHED=OFF` | KokkosKernels CMake force-enables BATCHED via SPARSE | use the pre-patched local tarball ([findings/08](../findings/08_kk_components_force_batched_via_sparse.md)) |
| Hypre fails on `dpct::constant_iterator` ctor | release Hypre + 2025.3 DPL mismatch | `--download-hypre-commit=origin/master` |
| `Unknown option "l1-Jacobi"` for `-pc_hypre_boomeramg_relax_type_all` | Hypre master renamed it | use `l1scaled-jacobi` |
| `MPI is not aware of sycl GPU devices` (rc 76) | runtime safety check | append `-use_gpu_aware_mpi 0` |
| ex2 reports `symbol urDeviceWaitExp not found` | binary linked against oneAPI 2026 libsycl, runtime is 2025.3 | `rm ex2 && make ex2` to rebuild |
| `set -u` exits on the source line of OpenFOAM bashrc | `WM_PROJECT_DIR` is unset and bashrc:184 doesn't guard | drop global `-u`, use `${var:-}` defensively |

---

## Cross-references

- [findings/](../findings/) — 14 root-cause writeups, one per gotcha above
- [patches/plan-i.patch](../patches/plan-i.patch) — exact source-level patches
- [scripts/stufe1-esi-v2512-tarball.sh](../scripts/stufe1-esi-v2512-tarball.sh) — Stufe 1 reference
- [scripts/stufe2-petsc.sh](../scripts/stufe2-petsc.sh) — Stufe 2 reference (Plan I integrated)
- [logs/plan-i-iterations.md](../logs/plan-i-iterations.md) — chronological iteration log
- [benchmarks/ex2_200x200_results.md](../benchmarks/ex2_200x200_results.md) — sanity numbers
