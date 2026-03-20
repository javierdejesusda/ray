# syntax=docker/dockerfile:1.3-labs

ARG DOCKER_IMAGE_BASE_BUILD=cr.ray.io/rayproject/oss-ci-base_build-py3.11
FROM $DOCKER_IMAGE_BASE_BUILD

ARG RAY_CI_JAVA_BUILD=
ARG RAY_CUDA_CODE=cpu

SHELL ["/bin/bash", "-ice"]

COPY . .

RUN <<EOF
#!/bin/bash

set -euo pipefail

SKIP_PYTHON_PACKAGES=1 ./ci/env/install-dependencies.sh

PYTHON_CODE="$(python -c "import sys; v=sys.version_info; print(f'py{v.major}{v.minor}')")"

LOCK_FILE="python/deplocks/llm/rayllm_test_${PYTHON_CODE}_${RAY_CUDA_CODE}.lock"

# Install everything from the lock file except vllm (git deps can't be hashed
# and building from source is slow). Then install vllm separately.
grep -v '^vllm ' "${LOCK_FILE}" | pip install --no-deps -r /dev/stdin
VLLM_URL="$(grep '^vllm @ ' "${LOCK_FILE}" | sed 's/^vllm @ //')"
if [ -n "${VLLM_URL}" ]; then
    pip install setuptools_scm
    pip install --no-deps --no-build-isolation "${VLLM_URL}"
fi

EOF

# Conda's libstdc++ provides CXXABI_1.3.15 needed by ICU 78 and other
# C++ libraries pulled in by vLLM 0.17.0. Place it before the system copy
# so the dynamic linker finds it first.
ENV LD_LIBRARY_PATH=/home/ray/anaconda3/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
