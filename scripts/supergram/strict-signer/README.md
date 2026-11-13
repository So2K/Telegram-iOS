# Strict signer source preservation

This directory preserves a native-only patch and the inputs needed to restore the applied opt-in signer from the upstream source. It contains no native checkout, object files, executable, provisioning profile, key or password. The application packager and validator remain separate scripts.

Upstream: https://github.com/zhlynn/zsign at commit `e803f870dc686e6161d00d9b22c425b8acdfacee`. `native.patch` changes exactly ten `src/` paths, including the new `strict_signing.h`. `native-manifest.json` records the 72 baseline source/Makefile/license hashes and all 73 patched hashes. The patch preserves existing line endings, including CRLF in `common/json.cpp`.

Keep these four files together in `scripts/supergram/strict-signer/`: `native.patch`, `native-manifest.json`, `build_strict_signer.py`, and this README. Also preserve the existing application wrappers, validator, helper, runtime pin, and regression tests under `scripts/supergram/`; the native source patch does not replace them. Both the private `ipa-signing-work/` tree and historical `output/` evidence are ignored by the application repository and cannot be the only retained copy. Explicitly add the proposed durable files to version control after review; copying them alone does not create a commit.

## Restore and build offline

Provide an already available local upstream Git repository containing the exact pinned commit. The script does not fetch, clone, install dependencies or access signing material. A fresh checkout of this application still needs that pinned upstream source to be made available separately.

Required local tools: Python 3, Git, make, pkg-config, Apple Clang and a macOS SDK, plus pkg-config OpenSSL **3.6.1**. The reviewed reference environment was macOS 15.1 arm64, Apple Clang 16.0.0 (`clang-1600.0.26.6`), macOS SDK 15.2. The script records the actual compiler/SDK/OpenSSL flags. It enforces the reviewed OpenSSL version; it does not claim a hermetic compiler or dylib environment.

Run from the application checkout, replacing both paths with your own local input and a **new**, separate scratch directory:

```sh
python3 scripts/supergram/strict-signer/build_strict_signer.py \
  --upstream-repo /absolute/path/to/local-zsign-git \
  --work-dir /absolute/path/to/new-owned-zsign-build
```

Use `--restore-only` to verify exact patched sources without invoking a compiler. Existing output directories and output inside the input repository or an `ipa-signing-work` path are refused. The script exports only the pinned `src/`, `build/macos/Makefile`, and `LICENSE`, validates their hashes, then applies the patch in an isolated scratch Git root. It never reuses private working-tree objects. Choose a work directory without spaces for the compile route: the inherited Makefile does not quote its expanded object/binary paths. Source-only restoration passes paths as separate arguments and does not use those Makefile recipes.

The original Makefile compiles **34 fresh translation units**: 16 C++, 15 vendored zlib C and 3 vendored MiniZip C. C++ uses `-std=c++11 -O3 -MMD -MP`; C uses `-O3`; `VERSION=preflight-draft`, `SYSTEM_MINIZIP=0`, and separate `OBJDIR`/`BINDIR` are explicit. OpenSSL include/library flags come from `pkg-config`. zlib 1.3.1 and MiniZip 1.1 remain the exact vendored upstream source with their notices. On macOS the strict XML reader dynamically loads `/usr/lib/libxml2.2.dylib`; it needs no CoreFoundation framework link.

The resulting executable stays at `<work-dir>/bin/zsign`. The script only builds it and records `build-evidence.json`; it does not execute the signer, sign an application, package an IPA, deploy a binary or change the runtime pin. The reviewed runtime binary links `/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib` and `libcrypto.3.dylib`, as well as system C++/System libraries. Preserving the source and binary pin alone does not preserve those installed runtime dependencies.

## Regression and deployment boundary

The optional `--source-dir` interface in the existing regression test lets it use the restored source without the ignored working checkout:

```sh
python3 scripts/supergram/tests/zsign_strict_bundle_regression.py \
  --source-dir /absolute/path/to/new-owned-zsign-build/source/src \
  --candidate /absolute/path/to/new-owned-zsign-build/bin/zsign
```

This harness creates owned self-signed PEM/CMS test fixtures and compiles an instrumented signing dispatcher; it does not read existing credentials or sign an application. The review ran 305 actual-source assertions and 23 CLI failure routes against the fresh restored build. The optional test argument preserves the existing default source location when omitted.

The approved deployed opt-in runtime pin remains `f704d3ba0185310884a0fa891fd842810514666e5442debd7f9bfa766e030513`; the legacy signer remains separate. A rebuild can have a different hash even from equal source because compiler, SDK, link UUID, paths and dependencies may differ. The independent full-source review produced `46b305d1de0ef7efac17f4f6fde23c8eb033c01ba8a88a32bafe196f9fae7846` in isolated scratch. That is restoration evidence, not permission to deploy or repin. A new binary requires a separate review, regression verification and explicit runtime pin update. Never overwrite either existing binary automatically.

## License and provenance

Upstream `LICENSE` is MIT, SHA-256 `57a50ade7eafe84091e7f97169e2c555980513e5d425ba8b21c76ce7458f602c`. Restoration retains it byte for byte. The complete upstream notice follows; retain it with restored source and any substantial redistributed portions. Vendored zlib/MiniZip notices remain in the pinned source files.

```text
MIT License

Copyright (c) 2026 zhlynn

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
