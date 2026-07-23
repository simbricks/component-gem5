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

# Compilers and python interpreter (overridable by conda / the environment).
CXX               ?= c++
PYTHON            ?= python

# Python packages
GEM5_PY_SIM       := gem5_sim_py

# gem5 simulator (compiled from the bundled submodule with SCons).
GEM5_DIR          := gem5
GEM5_ISA          ?= X86
GEM5_VARIANT      ?= fast
GEM5_JOBS         ?= $(shell nproc)
GEM5_BINARY       := $(GEM5_DIR)/build/$(GEM5_ISA)/gem5.$(GEM5_VARIANT)

# gem5's m5 guest utility (built from the submodule with SCons). Unlike the
# simulator, m5 is a *guest* binary that runs inside the simulated system, so it
# is compiled for the guest ABI rather than the host. It is later copied into a
# Linux disk image (e.g. with packer), which is why it gets its own build/install
# targets. m5's build tree lives under util/m5 and its ABI dir names (see
# util/m5/src/abi) differ from the gem5 ISA names, so map ISA -> ABI here.
M5_DIR            := $(GEM5_DIR)/util/m5
M5_ABI_X86        := x86
M5_ABI_ARM        := arm64
M5_ABI_RISCV      := riscv
M5_ABI_SPARC      := sparc
M5_ABI            ?= $(or $(M5_ABI_$(GEM5_ISA)),x86)
M5_BINARY         := $(M5_DIR)/build/$(M5_ABI)/out/m5

# Install prefix for `gem5-install`; conda-build sets this to the package prefix.
PREFIX            ?= /usr/local

# SimBricks C library (headers + libsimbricks) needed to compile gem5. Defaults
# to the active conda env (where `simbricks-lib` installs them); override for a
# non-conda toolchain, e.g. SIMBRICKS_INC_DIR=/path/include.
SIMBRICKS_INC_DIR ?= $(CONDA_PREFIX)/include
SIMBRICKS_LIB_DIR ?= $(CONDA_PREFIX)/lib

# Optional: redirect conda-build output, e.g. OUTPUT_FOLDER=./conda-out.
OUTPUT_FOLDER     ?=
OUTPUT_FLAG       := $(if $(OUTPUT_FOLDER),--output-folder $(OUTPUT_FOLDER))
# Conda channels searched by `conda build`. The SimBricks channel hosts external
# deps not built here (e.g. simbricks-lib, simbricks-orchestration); conda-forge
# provides the rest. Override to point at a different channel if needed.
SIMB_CONDA_CHANNEL:= -c https://conda.simbricks.io/latest
BASE_BUILD_CMD    := conda build $(SIMB_CONDA_CHANNEL) -m conda-recipes/conda_build_config.yaml $(OUTPUT_FLAG)

.PHONY: all conda-packages pypi-build pypi-publish clean gem5-python-develop \
	gem5-sim-py-conda gem5-build gem5-install gem5-clean gem5-bin-conda \
	m5-build m5-install m5-clean

## --- Python packages -------------------------------------------------------

# Editable installs for local development.
gem5-python-develop:
	$(PYTHON) -m pip install -e ./$(GEM5_PY_SIM)

## --- gem5 simulator --------------------------------------------------------

# Compile gem5 with SimBricks support. gem5's SCons ignores conda's
# CFLAGS/LDFLAGS, so the SimBricks (and zlib/python etc.) headers/libs are made
# discoverable via env vars gem5 does honor: CPATH puts the include dir on the
# compiler's search path for every probe, LIBRARY_PATH on the link path, and
# CCFLAGS_EXTRA satisfies the SimBricks SConsopts probe explicitly. LD_LIBRARY_PATH
# lets gem5's Python-version probe (which compiles *and runs* a conftest that
# dynamically links libpython) load libpython at build time. The simbricks-lib
# conda package ships its static library under lib/simbricks, so that subdir is
# added to the link paths alongside the main lib dir (zlib, libpython). The rpath
# in LINKFLAGS_EXTRA lets the produced binary find the shared libs at run time.
gem5-build:
	cd $(GEM5_DIR) && \
	  CPATH="$(SIMBRICKS_INC_DIR)" \
	  CCFLAGS_EXTRA="-I$(SIMBRICKS_INC_DIR)" \
	  LIBRARY_PATH="$(SIMBRICKS_LIB_DIR):$(SIMBRICKS_LIB_DIR)/simbricks" \
	  LD_LIBRARY_PATH="$(SIMBRICKS_LIB_DIR)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" \
	  LINKFLAGS_EXTRA="-L$(SIMBRICKS_LIB_DIR) -L$(SIMBRICKS_LIB_DIR)/simbricks -Wl,-rpath,$(SIMBRICKS_LIB_DIR)" \
	  scons build/$(GEM5_ISA)/gem5.$(GEM5_VARIANT) --ignore-style -j$(GEM5_JOBS)

# Install the binary + config scripts under $(PREFIX), mirroring the local build
# layout ($(PREFIX)/gem5/build/<ISA>/gem5.<variant> and $(PREFIX)/gem5/configs)
# so the runtime path is identical to a local build with $(PREFIX) prepended.
# Depends on the build target so the binary is always (re)built first.
gem5-install: gem5-build
	install -d $(PREFIX)/opt/$(GEM5_DIR)/build/$(GEM5_ISA)
	install -m 0755 $(GEM5_BINARY) \
	  $(PREFIX)/opt/$(GEM5_DIR)/build/$(GEM5_ISA)/gem5.$(GEM5_VARIANT)
	cp -a $(GEM5_DIR)/configs $(PREFIX)/opt/$(GEM5_DIR)/configs

gem5-clean:
	rm -rf $(GEM5_DIR)/build

## --- m5 guest utility ------------------------------------------------------

# Build only the m5 binary for the target ABI. Naming an explicit target avoids
# SCons's default of building every ABI (which would need all the cross
# compilers); the m5 SConstruct is self-contained and needs no SimBricks flags.
m5-build:
	cd $(M5_DIR) && scons build/$(M5_ABI)/out/m5 -j$(GEM5_JOBS)

# Install the m5 binary under $(PREFIX) at a predictable, ABI-qualified path so a
# later image build (e.g. packer) can pick it up and drop it into the guest
# image. Depends on the build target so the binary is always (re)built first.
m5-install: m5-build
	install -d $(PREFIX)/opt/$(GEM5_DIR)/util/m5/$(M5_ABI)
	install -m 0755 $(M5_BINARY) \
	  $(PREFIX)/opt/$(GEM5_DIR)/util/m5/$(M5_ABI)/m5

m5-clean:
	rm -rf $(M5_DIR)/build

## --- Conda packages --------------------------------------------------------

gem5-sim-py-conda:
	$(BASE_BUILD_CMD) conda-recipes/simbricks-gem5-sim-py

gem5-bin-conda:
	$(BASE_BUILD_CMD) conda-recipes/simbricks-gem5-sim-bin

conda-packages: gem5-sim-py-conda gem5-bin-conda

## --- PyPI packages ---------------------------------------------------------

pypi-build:
	poetry build -C $(GEM5_PY_SIM)

pypi-publish: pypi-build
	poetry publish -C $(GEM5_PY_SIM)

## --- Default target ----------------------------------------------------------

# Default: local dev build of both halves.
all: conda-packages

## --- Housekeeping ----------------------------------------------------------

clean: gem5-clean m5-clean
	rm -rf $(GEM5_PY_SIM)/dist
