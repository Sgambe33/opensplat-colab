# opensplat-colab
Run [OpenSplat](https://github.com/WebODM/OpenSplat) on Google Colaboratory

[![Open in Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/drive/1USqQsIBcqdOP6Fy0aVAyoXzTdpaEoTL_)

## Usage
Select a GPU runtime, then paste and run the following code at the beginning of your notebook:
```bash
# Install COLMAP and OpenSplat (~3min)
!curl -fsSL https://sgambe33.github.io/opensplat-colab/install.sh | bash
```

## Runtime
This project continuously integrates the latest upstream changes from OpenSplat, ensuring compatibility with the latest version of Google Colaboratory (runtime `2026.10`).

| Component        | Version                          |
|------------------|----------------------------------|
| Ubuntu           | 24.04                            |
| CUDA Toolkit     | 13.0                             |
| PyTorch          | 2.11.0+cu130                     |
| COLMAP           | 4.2.1 (CUDA, no GUI)             |
| GPUs             | T4, L4, A100, H100, RTX PRO 6000 |

The installer only supports the Ubuntu 24.04 / CUDA 13 runtimes. Older Colab runtimes (Ubuntu 22.04 / CUDA 12.x), selectable through *Change runtime version*, are no longer supported.
