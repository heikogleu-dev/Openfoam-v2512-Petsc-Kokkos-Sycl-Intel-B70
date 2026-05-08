# Bundled Scotch 6.1.0 fails to compile under GCC 15 — switch to system Scotch

## Summary

ESI OpenFOAM v2512's `ThirdParty-v2512` ships `scotch_6.1.0`, which has
K&R-style empty function-pointer prototypes (`int (*func)()`). GCC 15 promotes
the long-standing `-Wstrict-prototypes` to a hard error in C23 mode.
Switching ESI's config to `scotch-system` and using Ubuntu's
`libscotch-dev 7.x` fixes the build; only the two decomposition shim libs
need to be rebuilt.

## Symptom

```
$ ./Allwmake -j 2>&1 | tee log.scotch
[...]
arch.c:170:9: error: too many arguments to function 'archFree';
              expected 0, have 1
  170 |       archFree (&archdat);
      |       ^~~~~~~~  ~~~~~~~~
arch.c:71:14: note: declared here
   71 | static int (*archFree) ();
      |              ^~~~~~~~
make[2]: *** [Makefile:243: arch.o] Error 1
```

Affected files in `scotch_6.1.0/src/libscotch/`: `arch.c`, `arch_build.c`,
`mapping.c`, `library_arch_*.c` — all touched by the same idiom.

## Fix

Switch ESI's `etc/config.sh/scotch` to system mode:

```bash
# $WM_PROJECT_DIR/etc/config.sh/scotch
SCOTCH_VERSION=scotch-system
SCOTCH_ARCH_PATH=
```

Rebuild only the two decomposition wrappers — Foundation core stays
untouched:

```bash
wmake src/parallel/decompose/scotchDecomp
wmake src/parallel/decompose/ptscotchDecomp
```

Verify linkage:

```
$ ldd $FOAM_LIBBIN/libscotchDecomp.so | grep scotch
    libscotch.so.7 => /usr/lib/x86_64-linux-gnu/libscotch.so.7
    libscotcherr.so.7 => /usr/lib/x86_64-linux-gnu/libscotcherr.so.7
```

## Why it happens

Ubuntu 26.04 ships GCC 15.x with `-std=gnu23` as the C default. C23 removes
the implicit-int / unspecified-args legacy. Scotch 6.1.0 (released 2021)
predates this and uses `int (*archFree) ();` to mean "any signature";
under C23 that means "no arguments." Scotch upstream fixed this in 7.x.

## Impact

| Item                       | Status |
|----------------------------|--------|
| ThirdParty Scotch build    | skipped (intentionally) |
| `scotchDecomp` lib         | OK against system Scotch 7.x |
| `ptscotchDecomp` lib       | OK against system PT-Scotch 7.x |
| Foundation v13 in `/opt`   | not touched |

## Reproduction

```bash
cd $WM_THIRD_PARTY_DIR
./makeSCOTCH 2>&1 | grep 'error:' | head -5
```

## Status / Resolution

Fixed by configuration swap (no source patch). Use system Scotch 7.x.

## Related

- `01_libparmetis_replaced_libscotchparmetis_u26.md` — same Scotch stack on apt
- `04_set_u_bashrc_184_unbound.md` — environment issue while sourcing the
  rebuilt ESI tree
