#!/usr/bin/env bash
set -euo pipefail

REPO="Sgambe33/opensplat-colab"
RELEASE_URL="https://github.com/${REPO}/releases/download/gsplat"

# Must match the versions used in .github/workflows/gsplat.yml
UBUNTU_VERSION="24.04"
PYTHON_VERSION="3.12"
CUDA_MAJOR="13"
TORCH_VERSION="2.11.0"
TORCH_CUDA="cu130"

EXAMPLES_DIR="/opt/gsplat"

RED="\033[1;31m"
ORANGE='\033[1;33m'
GREEN="\033[1;32m"
CYAN="\033[1;36m"
RESET="\033[0m"

error_exit() {
    echo -e "${RED}   ✗ Error: $1${RESET}"
    exit 1
}

warning() {
    echo -e "${ORANGE}   ⚠ Warning: $1${RESET}"
}

ok() {
    echo -e "${GREEN}   ✔ $1${RESET}"
}

download() {
    wget -q "$1" -O "$2" || error_exit "Failed to download $1"
}

echo -e "${CYAN}──────────────────────────────────────────────────────────────────${RESET}"
echo -e "${CYAN}🫟 gsplat for Google Colab${RESET}"
echo -e "${CYAN}🔗 Project repository: https://github.com/${REPO}${RESET}"
echo -e "${CYAN}──────────────────────────────────────────────────────────────────${RESET}"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

echo
echo -e "🚧 Checking Colab runtime environment..."
os_version=$(. /etc/os-release && echo "$VERSION_ID")
if [[ "$os_version" != "$UBUNTU_VERSION" ]]; then
    error_exit "This script requires Ubuntu ${UBUNTU_VERSION} (Colab runtime 2026.10 or newer). Detected: ${os_version}"
fi
ok "Ubuntu ${UBUNTU_VERSION} detected"

command -v python3 &> /dev/null || error_exit "python3 not found"
python_version=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
if [[ "$python_version" != "$PYTHON_VERSION" ]]; then
    error_exit "The wheels are built for Python ${PYTHON_VERSION}. Detected: ${python_version}"
fi
ok "Python ${PYTHON_VERSION} detected"

# The wheels are compiled against one specific PyTorch build, so the one that
# ships with the runtime has to match
torch_info=$(python3 -c 'import torch; print(torch.__version__.split("+")[0], torch.version.cuda or "none")' 2>/dev/null) \
    || error_exit "PyTorch is not installed in this runtime"
read -r torch_version torch_cuda_version <<< "$torch_info"
if [[ "$torch_version" != "$TORCH_VERSION" || "${torch_cuda_version%%.*}" != "$CUDA_MAJOR" ]]; then
    error_exit "The wheels are built for PyTorch ${TORCH_VERSION}+${TORCH_CUDA}. Detected: ${torch_version} (CUDA ${torch_cuda_version})"
fi
ok "PyTorch ${TORCH_VERSION}+${TORCH_CUDA} detected"

if ! command -v nvidia-smi &> /dev/null; then
    warning "'nvidia-smi' not found. This runtime does not have a GPU, gsplat will not be able to run."
else
    gpu_model=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
    compute_cap=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -n1 | tr -d ' ')
    # Wheels contain kernels for sm_75, sm_80, sm_89, sm_90 and sm_120
    case "$compute_cap" in
        7.5|8.*|9.0|12.*) ok "Supported GPU detected: ${gpu_model} (compute capability ${compute_cap})" ;;
        *) error_exit "Unsupported GPU: ${gpu_model} (compute capability ${compute_cap})" ;;
    esac
fi

echo
echo -e "⬇️ Downloading precompiled wheels..."
download "${RELEASE_URL}/wheels.txt" wheels.txt
# Keep only plain wheel file names (skip anything malformed)
mapfile -t wheels < <(grep -E '^[A-Za-z0-9][A-Za-z0-9._+-]*\.whl$' wheels.txt | sort -u)
(( ${#wheels[@]} > 0 )) || error_exit "The release does not list any wheel"
mkdir wheels
for wheel in "${wheels[@]}"; do
    # '+' (local version tags) must be escaped in URLs
    download "${RELEASE_URL}/${wheel//+/%2B}" "wheels/${wheel}"
done
ok "${#wheels[@]} wheels downloaded"

# --no-deps: the wheels must not replace the runtime's PyTorch
if ! python3 -m pip install -q --no-deps --force-reinstall wheels/*.whl > pip.log 2>&1; then
    tail -n 20 pip.log
    error_exit "Failed to install the wheels"
fi
ok "gsplat installed"

echo
echo -e "📦 Installing Python dependencies..."
download "${RELEASE_URL}/requirements.txt" requirements.txt
if ! python3 -m pip install -q -r requirements.txt > pip.log 2>&1; then
    # Install one by one, so that a single unavailable package does not block the others
    failed=()
    while read -r req; do
        [[ -z "$req" ]] && continue
        python3 -m pip install -q "$req" > pip.log 2>&1 || failed+=("$req")
    done < requirements.txt
    for req in "${failed[@]}"; do
        warning "Could not install '${req}'"
    done
fi
ok "Python dependencies installed"

# pip must not have swapped the PyTorch build the wheels were compiled against
torch_after=$(python3 -c 'import torch; print(torch.__version__.split("+")[0])' 2>/dev/null || true)
if [[ "$torch_after" != "$TORCH_VERSION" ]]; then
    error_exit "PyTorch changed to '${torch_after}' while installing dependencies, gsplat will not work. Restart the runtime and try again."
fi

echo
echo -e "📂 Installing the example trainers..."
download "${RELEASE_URL}/gsplat-examples.tar.gz" gsplat-examples.tar.gz
rm -rf "${EXAMPLES_DIR}/examples"
mkdir -p "$EXAMPLES_DIR"
tar xf gsplat-examples.tar.gz -C "$EXAMPLES_DIR"
ok "Examples installed in ${EXAMPLES_DIR}/examples"

echo
echo -e "🔎 Checking the installation..."
gsplat_version=$(python3 -c 'import gsplat; print(gsplat.__version__)' 2>&1 | tail -n1) \
    || error_exit "gsplat failed to import: ${gsplat_version}"
# The compiled CUDA extension must load as is. If it does not, gsplat would
# try to compile it on first use, which takes a long time.
csrc_error=$(python3 -c 'from gsplat import csrc' 2>&1 | tail -n1) \
    || error_exit "The precompiled CUDA extension failed to load: ${csrc_error}"
ok "gsplat works (${gsplat_version})"

echo
echo "🚀 Everything is set up! Train a COLMAP project with:"
echo "   python ${EXAMPLES_DIR}/examples/simple_trainer.py default --data_dir <project> --result_dir <output>"
