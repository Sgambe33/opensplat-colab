# opensplat-colab
Run [OpenSplat](https://github.com/WebODM/OpenSplat) on Google Colaboratory

[![Open in Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/drive/1USqQsIBcqdOP6Fy0aVAyoXzTdpaEoTL_)

## Usage
Select a GPU runtime, then paste and run the following code at the beginning of your notebook:
```bash
# Install COLMAP and OpenSplat (~3min)
!curl -fsSL https://sgambe33.github.io/opensplat-colab/install.sh | bash
```

### gsplat (optional)
[gsplat](https://github.com/nerfstudio-project/gsplat) can be installed from precompiled wheels as well, instead of compiling it in the notebook:
```bash
# Install gsplat and its example trainers (~1min)
!curl -fsSL https://sgambe33.github.io/opensplat-colab/install-gsplat.sh | bash
```
The example trainers are placed in `/opt/gsplat/examples`:
```bash
!python /opt/gsplat/examples/simple_trainer.py default --data_dir <project> --result_dir <output>
```
The wheels are built from a pinned commit of gsplat's `main` branch (see [gsplat.yml](.github/workflows/gsplat.yml)) against the PyTorch build that ships with Colab. The two installers are independent of each other.

## Runtime
This project continuously integrates the latest upstream changes from OpenSplat, ensuring compatibility with the latest version of Google Colaboratory (runtime `2026.10`).

| Component        | Version                          |
|------------------|----------------------------------|
| Ubuntu           | 24.04                            |
| Python           | 3.12 (gsplat wheels only)        |
| CUDA Toolkit     | 13.0                             |
| PyTorch          | 2.11.0+cu130                     |
| COLMAP           | 4.2.1 (CUDA, no GUI)             |
| GPUs             | T4, L4, A100, H100, RTX PRO 6000 |

The installer only supports the Ubuntu 24.04 / CUDA 13 runtimes. Older Colab runtimes (Ubuntu 22.04 / CUDA 12.x), selectable through *Change runtime version*, are no longer supported.
