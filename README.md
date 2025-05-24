# Conan Cuda Boot Strapper

`bootstrap.sh` is a helper script to quickly set up and build a CMake/C++/CUDA project using Conan for dependency management. It can:

- Install or verify required tools (CMake, NVIDIA drivers, CUDA Toolkit, NCCL, Python & Conan)
- Populate your project from a boilerplate GitHub template
- Configure and activate a Python virtual environment
- Generate Conan recipes and CMakeLists for CUDA and non-CUDA builds
- Build (`build`) or clean (`clear`) the project artifacts

## Prerequisites

Make sure you have:

- **Ubuntu 22.04+** (only Ubuntu is supported)
- **sudo** privileges
- Internet access for package installs and boilerplate download

The script will attempt to install:

- **CMake** (>= 3.24)
- **NVIDIA driver** (>= 566.36) & **CUDA Toolkit** (12.7)
- **NCCL** (if `nccl=1`)
- **Python 3.12**, `venv` & `dev` packages
- **Conan** 2.15.1 (inside venv)

_All paths, versions, and defaults_ can be overridden via `--key=value` flags :contentReference[oaicite:0]{index=0}.

## Getting Started

1. **Clone** your empty repo and `cd` into it.

2. **Make the script executable** (if not already):

   ```bash
   chmod +x bootstrap.sh
## Examples

Here are some common ways to use `bootstrap.sh`:

- **Basic bootstrap**
  ```bash
  ./bootstrap.sh --project_name=conancuda  
  ```
- **Pure C++**
  ```bash
  ./bootstrap.sh --project_name=conancuda --cuda=0
  ```

- **Exclude NCCL**
  ```bash
  ./bootstrap.sh --project_name=conancuda --nccl=0
  ```
- **Designate Python and Conan Version**
  ```bash
  ./bootstrap.sh --project_name=conancuda --nccl=0
  ```