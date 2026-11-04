#!/usr/bin/env bash
set -euo pipefail

REPO="Sgambe33/opensplat-colab"
RELEASE_URL="https://github.com/${REPO}/releases/latest/download"

# Must match the versions used in .github/workflows/ci.yml
UBUNTU_VERSION="24.04"
CUDA_MAJOR="13"
TORCH_VERSION="2.11.0"
TORCH_CUDA="cu130"
LIBTORCH_URL="https://download.pytorch.org/libtorch/${TORCH_CUDA}/libtorch-shared-with-deps-${TORCH_VERSION}%2B${TORCH_CUDA}.zip"

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

echo -e "${CYAN}"
cat << "EOF"
 _______  _______  _______  __    _  _______  _______  ___      _______  _______         _______  _______  ___      _______  _______
|       ||       ||       ||  |  | ||       ||       ||   |    |   _   ||       |       |       ||       ||   |    |   _   ||  _    |
|   _   ||    _  ||    ___||   |_| ||  _____||    _  ||   |    |  |_|  ||_     _| ____  |       ||   _   ||   |    |  |_|  || |_|   |
|  | |  ||   |_| ||   |___ |       || |_____ |   |_| ||   |    |       |  |   |  |____| |       ||  | |  ||   |    |       ||       |
|  |_|  ||    ___||    ___||  _    ||_____  ||    ___||   |___ |       |  |   |         |      _||  |_|  ||   |___ |       ||  _   |
|       ||   |    |   |___ | | |   | _____| ||   |    |       ||   _   |  |   |         |     |_ |       ||       ||   _   || |_|   |
|_______||___|    |_______||_|  |__||_______||___|    |_______||__| |__|  |___|         |_______||_______||_______||__| |__||_______|

EOF
echo -e "${RESET}"

echo -e "${CYAN}──────────────────────────────────────────────────────────────────${RESET}"
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

if ! command -v nvidia-smi &> /dev/null; then
    warning "'nvidia-smi' not found. This runtime does not have a GPU, OpenSplat will not be able to run on CUDA."
else
    gpu_model=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
    compute_cap=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -n1 | tr -d ' ')
    # Binaries contain kernels for sm_75, sm_80, sm_89, sm_90 and sm_120
    case "$compute_cap" in
        7.5|8.*|9.0|12.*) ok "Supported GPU detected: ${gpu_model} (compute capability ${compute_cap})" ;;
        *) error_exit "Unsupported GPU: ${gpu_model} (compute capability ${compute_cap})" ;;
    esac

    driver_cuda=$(nvidia-smi | grep -oE "CUDA Version: [0-9]+\.[0-9]+" | awk '{print $3}')
    if [[ -n "$driver_cuda" && "${driver_cuda%%.*}" -lt "$CUDA_MAJOR" ]]; then
        error_exit "The NVIDIA driver must support CUDA ${CUDA_MAJOR}.x. Detected: ${driver_cuda}"
    fi
    ok "NVIDIA driver supports CUDA ${driver_cuda:-unknown}"
fi

echo
echo -e "⬇️ Downloading precompiled binaries..."
download "${RELEASE_URL}/colmap-ubuntu-${UBUNTU_VERSION}.tar.gz" colmap.tar.gz
tar xf colmap.tar.gz -C /usr/local
ok "colmap installed"

download "${RELEASE_URL}/opensplat" opensplat
chmod +x opensplat
mv opensplat /usr/local/bin/opensplat
ok "opensplat installed"

echo
echo -e "📦 Installing runtime dependencies..."
download "${RELEASE_URL}/runtime-deps.txt" runtime-deps.txt
# Keep only valid Debian package names (skip anything malformed)
mapfile -t deps < <(grep -E '^[a-z0-9][a-z0-9.+-]+$' runtime-deps.txt | sort -u)
if (( ${#deps[@]} > 0 )); then
    apt-get update -qq > /dev/null 2>&1 || warning "apt-get update failed"
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${deps[@]}" > apt.log 2>&1; then
        tail -n 20 apt.log
        error_exit "Failed to install runtime dependencies"
    fi
fi
ok "${#deps[@]} system packages installed"

# Make sure the CUDA Toolkit libraries shipped with Colab are visible to the loader
if [[ -d /usr/local/cuda/lib64 ]]; then
    echo "/usr/local/cuda/lib64" > /etc/ld.so.conf.d/opensplat-cuda.conf
    ldconfig > /dev/null 2>&1
fi

# Prefer the PyTorch build that ships with Colab (saves a ~2 GB download).
# Fall back to the official libtorch package if it does not match.
torch_lib=""
if command -v python3 &> /dev/null; then
    torch_lib=$(python3 - << EOF 2>/dev/null || true
import os, torch
if torch.__version__.split("+")[0] == "${TORCH_VERSION}" and (torch.version.cuda or "").startswith("${CUDA_MAJOR}."):
    print(os.path.join(os.path.dirname(torch.__file__), "lib"))
EOF
)
fi

if [[ -n "$torch_lib" && -d "$torch_lib" ]]; then
    echo "$torch_lib" > /etc/ld.so.conf.d/opensplat-torch.conf
    ldconfig > /dev/null 2>&1
    ok "Using Colab's PyTorch ${TORCH_VERSION} (${torch_lib})"
fi

missing_libs() {
    ldd /usr/local/bin/opensplat /usr/local/bin/colmap | grep "not found" | sort -u || true
}

if [[ -n "$(missing_libs)" ]]; then
    [[ -n "$torch_lib" ]] && warning "Colab's PyTorch is not usable, downloading libtorch ${TORCH_VERSION}+${TORCH_CUDA} instead"
    rm -f /etc/ld.so.conf.d/opensplat-torch.conf
    download "$LIBTORCH_URL" libtorch.zip
    unzip -q libtorch.zip
    rm -f libtorch.zip
    mkdir -p /opt/libtorch
    cp -r libtorch/. /opt/libtorch
    rm -rf libtorch/
    echo "/opt/libtorch/lib" > /etc/ld.so.conf.d/opensplat-torch.conf
    ldconfig > /dev/null 2>&1
    ok "libtorch ${TORCH_VERSION}+${TORCH_CUDA} installed"
fi

missing=$(missing_libs)
if [[ -n "$missing" ]]; then
    echo "$missing"
    error_exit "Some shared libraries could not be found"
fi

colmap -h > /dev/null 2>&1 || error_exit "colmap failed to start"
ok "colmap works"
opensplat_version=$(opensplat --version 2>&1 | head -n1) || error_exit "opensplat failed to start: ${opensplat_version}"
ok "opensplat works (${opensplat_version})"

echo
echo "🚀 Everything is set up! You can now run OpenSplat in this Colab environment 🫟"
