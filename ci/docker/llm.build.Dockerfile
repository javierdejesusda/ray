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
pip install --no-deps -r python/deplocks/llm/rayllm_test_${PYTHON_CODE}_${RAY_CUDA_CODE}.lock

# Overlay Python-only changes from the vLLM RayExecutorV2 PR
# (https://github.com/vllm-project/vllm/pull/36836) on top of the installed
# vllm 0.17.0 wheel. We clone and copy rather than pip-installing from the git
# URL because vllm's build backend tries to compile C/CUDA extensions.
VLLM_SITE="$(python -c 'import vllm, os; print(os.path.dirname(vllm.__file__))')"
git clone --depth 1 -b ray https://github.com/jeffreywang-anyscale/vllm.git /tmp/vllm-overlay
cp -r /tmp/vllm-overlay/vllm/* "${VLLM_SITE}/"
rm -rf /tmp/vllm-overlay

EOF

# Conda's libstdc++ provides CXXABI_1.3.15 needed by ICU 78 and other
# C++ libraries pulled in by vLLM 0.17.0. Place it before the system copy
# so the dynamic linker finds it first.
ENV LD_LIBRARY_PATH=/home/ray/anaconda3/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
ENV VLLM_USE_RAY_V2_EXECUTOR_BACKEND=1
