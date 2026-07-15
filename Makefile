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

# Optional: redirect conda-build output, e.g. OUTPUT_FOLDER=./conda-out.
OUTPUT_FOLDER     ?=
OUTPUT_FLAG       := $(if $(OUTPUT_FOLDER),--output-folder $(OUTPUT_FOLDER))
# Conda channels searched by `conda build`. The SimBricks channel hosts external
# deps not built here (e.g. simbricks-lib, simbricks-orchestration); conda-forge
# provides the rest. Override to point at a different channel if needed.
SIMB_CONDA_CHANNEL:= -c https://conda.simbricks.io/latest
BASE_BUILD_CMD    := conda build $(SIMB_CONDA_CHANNEL) -m conda-recipes/conda_build_config.yaml $(OUTPUT_FLAG)

.PHONY: all conda-packages pypi-build pypi-publish clean gem5-python-develop \
	gem5-sim-py-conda

## --- Python packages -------------------------------------------------------

# Editable installs for local development.
gem5-python-develop:
	$(PYTHON) -m pip install -e ./$(GEM5_PY_SIM)

## --- Conda packages --------------------------------------------------------

gem5-sim-py-conda:
	$(BASE_BUILD_CMD) conda-recipes/simbricks-gem5-sim-py

conda-packages: gem5-sim-py-conda

## --- PyPI packages ---------------------------------------------------------

pypi-build:
	poetry build -C $(GEM5_PY_SIM)

pypi-publish: pypi-build
	poetry publish -C $(GEM5_PY_SIM)

## --- Default target ----------------------------------------------------------

# Default: local dev build of both halves.
all: conda-packages

## --- Housekeeping ----------------------------------------------------------

clean:
	rm -rf $(GEM5_PY_SIM)/dist
