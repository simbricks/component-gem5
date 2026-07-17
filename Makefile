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
	gem5-sim-py-conda gem5-build gem5-install gem5-clean gem5-bin-conda

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

clean: gem5-clean
	rm -rf $(GEM5_PY_SIM)/dist
