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

# Overlay only the files changed by the vLLM RayExecutorV2 PR
# (https://github.com/vllm-project/vllm/pull/36836) on top of the installed
# vllm 0.18.0 wheel. We copy individual files rather than the whole tree to
# avoid overwriting compiled C extensions with incompatible Python code.
VLLM_SITE="$(python -c 'import vllm, os; print(os.path.dirname(vllm.__file__))')"
git clone --depth 1 -b ray https://github.com/jeffreywang-anyscale/vllm.git /tmp/vllm-overlay
# Copy only the PR-changed source files (not envs.py -- see below)
cp /tmp/vllm-overlay/vllm/config/parallel.py "${VLLM_SITE}/config/parallel.py"
cp /tmp/vllm-overlay/vllm/v1/engine/core.py "${VLLM_SITE}/v1/engine/core.py"
cp /tmp/vllm-overlay/vllm/v1/executor/abstract.py "${VLLM_SITE}/v1/executor/abstract.py"
cp /tmp/vllm-overlay/vllm/v1/executor/ray_executor_v2.py "${VLLM_SITE}/v1/executor/ray_executor_v2.py"
cp /tmp/vllm-overlay/vllm/v1/executor/ray_utils.py "${VLLM_SITE}/v1/executor/ray_utils.py"
cp /tmp/vllm-overlay/vllm/v1/worker/gpu_worker.py "${VLLM_SITE}/v1/worker/gpu_worker.py"
cp /tmp/vllm-overlay/vllm/v1/worker/worker_base.py "${VLLM_SITE}/v1/worker/worker_base.py"
rm -rf /tmp/vllm-overlay

# Patch VLLM_USE_RAY_V2_EXECUTOR_BACKEND into the existing v0.18.0 envs.py.
# Append to the end of the file to avoid fragile regex matching.
python -c "
import pathlib
p = pathlib.Path('${VLLM_SITE}/envs.py')
p.write_text(p.read_text() + '''

# Patched: add VLLM_USE_RAY_V2_EXECUTOR_BACKEND support
import os as _os
environment_variables[\"VLLM_USE_RAY_V2_EXECUTOR_BACKEND\"] = lambda: bool(int(_os.getenv(\"VLLM_USE_RAY_V2_EXECUTOR_BACKEND\", \"0\")))
''')
"

EOF

# Conda's libstdc++ provides CXXABI_1.3.15 needed by ICU 78 and other
# C++ libraries pulled in by vLLM 0.17.0. Place it before the system copy
# so the dynamic linker finds it first.
ENV LD_LIBRARY_PATH=/home/ray/anaconda3/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
ENV VLLM_USE_RAY_V2_EXECUTOR_BACKEND=1
