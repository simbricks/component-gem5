#!/bin/bash
# MIT License

# Copyright (c) 2026 SimBricks

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -euo pipefail

# gem5 embeds the host CPython; point PYTHON_CONFIG at the host prefix.
export PYTHON_CONFIG="${PREFIX}/bin/python3-config"

# gem5's SConstruct decides GCC vs. Clang by grepping `$CXX --version` for the
# literal substring "g++". Conda sets CC/CXX to the `-cc`/`-c++`-named aliases,
# whose --version prints "... (conda-forge gcc N) ..." without "g++", so gem5
# rejects the compiler. Use the
# `-gcc`/`-g++`-named aliases (exported by the conda compiler activation as
# $GCC/$GXX) so the probe recognises GCC.
export CC="${GCC:-$CC}"
export CXX="${GXX:-$CXX}"

# gem5's SCons invokes `ar`/`ranlib`/etc. by their bare names (it forwards $AR to
# the subprocess env but does not map it to SCons's $AR construction variable the
# way it maps CC/CXX). Conda's binutils already provide bare-named tools under the
# target-triple bin dir; it just isn't on PATH by default, so add it.
export PATH="${BUILD_PREFIX}/${HOST}/bin:${PATH}"

# gem5's vendored ext/libelf runs a `native-elf-format` helper that invokes bare
# `cc` (then readelf) to detect the host ELF format and generate its arch config.
# Conda ships only the ${HOST}-prefixed compiler (no bare `cc`), so without this
# the probe fails, LIBELF_ARCH ends up empty, libelf can't build, and the whole
# libgem5/gem5.fast link chain silently never gets produced. Expose bare-named
# compiler symlinks pointing at the conda compiler.
_ccbin="${SRC_DIR}/_ccbin"
mkdir -p "${_ccbin}"
ln -sf "${CC}" "${_ccbin}/cc"
ln -sf "${CC}" "${_ccbin}/gcc"
ln -sf "${CXX}" "${_ccbin}/c++"
ln -sf "${CXX}" "${_ccbin}/g++"
export PATH="${_ccbin}:${PATH}"

# Drop any build tree copied in from the local worktree so we build cleanly
# against the conda toolchain.
rm -rf gem5/build

# Reuse the Makefile so build+install logic lives in one place. Host deps
# (simbricks-lib headers/lib, python, zlib) are in $PREFIX during the build.
make gem5-install \
  PREFIX="${PREFIX}" \
  GEM5_ISA="X86" \
  GEM5_VARIANT="fast" \
  GEM5_JOBS="${CPU_COUNT}" \
  SIMBRICKS_INC_DIR="${PREFIX}/include" \
  SIMBRICKS_LIB_DIR="${PREFIX}/lib"
