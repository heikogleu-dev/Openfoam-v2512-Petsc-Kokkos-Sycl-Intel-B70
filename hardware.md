# Hardware Details

> Hardware identical to the [sister repo's `hardware.md`](https://github.com/heikogleu-dev/Openfoam13---GPU-Offloading-Intel-B70-Pro/blob/main/hardware.md).
> Reproduced here for stand-alone reference; consult the sister repo for
> the underlying SYCL micro-benchmarks (FP64 FMA harness, VRAM Triad,
> kernel-launch timing) that produced these numbers.

## GPU: Intel Arc Pro B70 Pro (BMG-G31)

| Spec | Value |
|---|---|
| Architecture | Battlemage (Xe2-HPG) |
| Die | BMG-G31 (full Big Battlemage) |
| Xe Cores | 32 |
| XMX Engines | 256 |
| Boost Clock | 2800 MHz |
| Graphics Clock | 2280 MHz (typical) |
| VRAM | 32 GB GDDR6 ECC |
| Memory Bus | 256-bit |
| Memory Bandwidth | 608 GB/s (spec), 530 GB/s sustained Triad |
| TDP | 230 W (peak); 181 W observed under CFD |
| PCIe | 5.0 ×16 |
| FP64 | 1.43 TFLOPS spec, **1.37 TFLOPS measured (96 %)** |
| FP32 | 22.94 TFLOPS spec |
| Release | March 2026 |
| PCI BDF | `04:00.0` (renderD129) |

## CPU + System

| Component | Spec |
|---|---|
| CPU | Intel Core Ultra 9 285K — 8 P-Cores + 16 E-Cores (24T) |
| RAM | 96 GB DDR5-6800 |
| Mainboard | ASRock Z890I Nova WiFi |
| iGPU | Intel Arc Graphics (Meteor Lake gen, renderD128) |
| OS | Ubuntu 26.04 LTS (resolute), Kernel 7.0.0-15 |
| GCC | 15.2.0 |

The CPU's iGPU also enumerates as a SYCL device alongside B70 (`sycl-ls`
shows both). All Stufe-2 runs target the discrete B70 explicitly via PCI
BDF / renderD129.

## GPU/SYCL Stack (verified working with oneAPI 2025.3.3)

```
$ sycl-ls
[level_zero:gpu][level_zero:0] Intel(R) Graphics [0xe223] 20.2.0 [1.14.37020]   ← B70
[level_zero:gpu][level_zero:1] Intel(R) Graphics 12.70.4 [1.14.37020]            ← iGPU
[opencl:cpu][opencl:0]         Intel(R) Core(TM) Ultra 9 285K [2026.20.3.0.19]
[opencl:gpu][opencl:1]         Intel(R) Graphics [0xe223] OpenCL 3.0 NEO [26.05.037020]
[opencl:gpu][opencl:2]         Intel(R) Graphics OpenCL 3.0 NEO [26.05.037020]
```

| Layer | Version |
|---|---|
| Intel Compute Runtime (NEO) | 26.05.37020.3-1 (`apt-mark hold`) |
| Intel Graphics Compiler (IGC) | 2.32.7 (Intel rolling) |
| `/usr/bin/ocloc` | 24.35.30872.45-1 — **legacy**, no Battlemage AOT support; see [findings/06](findings/06_legacy_ocloc_no_battlemage_aot_jit_fallback.md) |
| `libze1` (Level-Zero loader) | 1.28.2-2 |
| `libze-intel-gpu1` | 26.05.37020.3-1 |
| Intel oneAPI Base Toolkit | 2025.3.3 (build 2025.3.3.20260319) |
| icpx / icx | 2025.3.3 |

## Two Foundations Coexist

The system carries two OpenFOAM installs simultaneously, by design:

```
/opt/openfoam13/                  ← Foundation OpenFOAM 13 (untouched, sister repo)
/opt/openfoam-v2512/              ← ESI OpenFOAM v2512 (this repo, Stufe 1)
└── OpenFOAM-v2512/
    ├── etc/bashrc                ← source this for v2512 work
    └── platforms/linux64GccDPInt32Opt/lib/
└── ThirdParty-v2512/
└── petsc-3.25.1/                 ← PETSc + Kokkos + Hypre (Stufe 2, Plan I)
└── tarballs/                     ← KK-5.1.0-plan-i.tar.gz, oneAPI installer, etc.
```

Foundation v13 and ESI v2512 use the same system OpenMPI (`sys-openmpi`)
but are otherwise isolated — no cross-shadowing of solvers or libraries.

## Iron Rules — TABU

Areas off-limits during Stufe 2 work, re-stated for any reproducer:
- `/opt/openfoam13/` — sister-repo's working dir; no writes, symlinks, or
  bashrc-sourcing during Stufe 2 sessions
- `/home/heiko/CFD-Cases/Testcase-GPU/` — sister-repo's reference testcase
  directory; protected against accidental rewrite

## See Also

- [findings/06](findings/06_legacy_ocloc_no_battlemage_aot_jit_fallback.md) —
  why we drop `-fsycl-targets=intel_gpu_bmg_g31` for AOT and rely on JIT
- [findings/13](findings/13_use_gpu_aware_mpi_off.md) — system-OpenMPI not
  GPU-aware for SYCL, runtime workaround
- Sister repo's [hardware.md](https://github.com/heikogleu-dev/Openfoam13---GPU-Offloading-Intel-B70-Pro/blob/main/hardware.md)
  for full FP64/VRAM/PCIe characterization
