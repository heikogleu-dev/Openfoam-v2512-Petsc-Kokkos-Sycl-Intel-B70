# PETSc `--download-kokkos-kernels=...tar.gz` only honors `file://` URLs

## Summary

PETSc 3.25.1's package downloader silently falls back to `git clone` if the
argument to `--download-kokkos-kernels=` is a bare filesystem path. With a
plain path it ignores our patched tarball and clones master, undoing the
component patch from finding 08. Prefixing the path with `file://` flips
the dispatcher into static-archive mode and our patches survive.

## Symptom

```
$ ./configure --download-kokkos-kernels=/home/heiko/src/kokkos-kernels-5.1.0-planI.tar.gz
[...]
=============================================================================
            Trying to download for KOKKOS-KERNELS
=============================================================================

$ ls $PETSC_ARCH/externalpackages/
git.kokkos-kernels    <-- WRONG, ignored our tarball
```

Build then fails with the original finding-07 error because the cmake
patch was never applied.

## Fix

Use the `file://` scheme:

```bash
./configure \
    --download-kokkos-kernels=file:///home/heiko/src/kokkos-kernels-5.1.0-planI.tar.gz \
    --download-kokkos=file:///home/heiko/src/kokkos-4.6.02.tar.gz \
    ...
```

Now PETSc treats the argument as a static archive:

```
$ ls $PETSC_ARCH/externalpackages/
kokkos-kernels-5.1.0/   <-- top-dir matches tarball, patches present
```

Sanity check the patch is intact:

```
$ grep -n 'Plan-I' $PETSC_ARCH/externalpackages/kokkos-kernels-5.1.0/cmake/kokkoskernels_components.cmake
123:# set(KokkosKernels_ENABLE_COMPONENT_BATCHED ON CACHE BOOL "" FORCE) # Plan-I
```

## Why it happens

`config/BuildSystem/config/packages/Package.py` selects the download
strategy by URL scheme. With no scheme, the "git" fallback wins because
KokkosKernels has a default git URL set in the same package definition.
`file://` is the only scheme that maps to "treat as a local archive."
Documented behavior, but the bare path silently misroutes — no warning.

## Tarball layout requirement

The top-level directory name inside the tarball must match what PETSc's
package definition expects (`kokkos-kernels-<version>`). We repackage:

```bash
cd $WORK
tar xzf kokkos-kernels-5.1.0.tar.gz
patch -p1 -d kokkos-kernels-5.1.0 < $REPO/patches/plan-i.patch
tar czf kokkos-kernels-5.1.0-planI.tar.gz kokkos-kernels-5.1.0
```

## Impact

| Argument form                                    | Result |
|--------------------------------------------------|--------|
| `--download-kokkos-kernels=/abs/path/x.tar.gz`   | git clone (silent) |
| `--download-kokkos-kernels=file:///abs/path/x.tar.gz` | local extraction |
| `--download-kokkos-kernels=https://.../x.tar.gz` | http fetch + extraction |
| `--download-kokkos-kernels=git://...`            | git clone |

## Status / Resolution

Worked around in `setup/03_petsc_configure.sh`. Could be reported upstream
as a UX bug.

## Related

- `08_kk_components_force_batched_via_sparse.md` — what the tarball patches
- `11_hypre_master_required.md` — analogous handling for `--download-hypre-commit`
