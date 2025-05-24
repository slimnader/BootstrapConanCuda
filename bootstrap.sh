#!/bin/bash
#set -euo pipefail

cmake_version="3.28.3"
cmake_current=$(cmake --version | grep -o '[0-9]\{1\}\.[0-9]\{1,2\}')
conan_version="2.15.1"
project_name="untitled"
cuda=1
nccl=1
nvidia_driver_version="566.36"
cuda_version="12.7"
py_version="3.12"
python_command="python$py_version"
venv_name="venv_linux"
venv_bin=$(realpath "$(find . -type f -path '*/bin/activate' -print -quit)" 2>/dev/null)
conan_command=$(realpath "$(find . -type f -path '*/bin/conan' -print -quit)" 2>/dev/null)
boiler_plate_files=(
     /src/
     /conan_provider.cmake
     /conanfile.py
     /CMakeLists.txt
#     /README.md
     /helpers.cmake
)

function cmd_build() {
    source $venv_bin
    path="$venv:$PATH:$PATH"
    export PATH=$path
    cmake -S . -B debug \
      -DCMAKE_BUILD_TYPE=Debug \
      -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES="${PWD}/conan_provider.cmake" \
      -DCONAN_COMMAND="$conan_command"

    # build
    cmake --build debug --config Debug -- -j"$(nproc)" VERBOSE=1
}


function cmd_clear(){
     rm -rf ./cmake-build-debug
     rm -rf   ./.idea
     rm -rf ./conandata.yml
     rm -rf ./venv_linux
     rm -rf ./CMakeUserPresets.json
     rm -rf ./resources
     rm -rf ./main
     rm -rf ./src/
     rm -rf ./conan_provider.cmake
     rm -rf ./conanfile.py
     rm -rf ./CMakeLists.txt
     rm -rf ./helpers.cmake
}

function cmd_help() {
  cat <<EOF
Usage: $0 [OPTIONS] [COMMAND]

A one-stop script to install dependencies, configure and build your CMake/CUDA
project with Conan.

OPTIONS (all take --key=VALUE syntax; defaults shown in brackets):
  --cmake_version=VERSION        CMake version to install     [3.28.3]
  --conan_version=VERSION        Conan version (in venv)      [2.15.1]
  --project_name=NAME            Project name in templates    [untitled]
  --cuda={0|1}                   Enable CUDA (1) or disable   [1]
  --nccl={0|1}                   Enable NCCL (1) or disable   [1]
  --nvidia_driver_version=VER    NVIDIA driver version        [566.36]
  --cuda_version=VERSION         CUDA toolkit version         [12.7]
  --venv_name=NAME               give a custom name to venv   [venv_linux]
                                 folder
  --py_version=MAJOR.MINOR       Python version for venv      [3.12]
                      Show this help message and exit

COMMAND (treated as non-build params):
  build      Configure & build the project
  clear      Remove build dirs, venv, CMake files, boilerplate
  help       Print this message


EXAMPLES:
  --cuda=0                  # disable CUDA
  --project_name=MyApp      # designate project name
  $0 build                  # configure & make debug
  $0 clear                  # cleanup everything
  $0 help                   # print this message

EOF
}


for arg in "$@"; do
  case $arg in
    --*=*)
      key="${arg%%=*}"   # Extract part before '='
      value="${arg#*=}"  # Extract part after '='


      key="${key#--}"    # Remove leading '--' from key

      # Export or store the value in a variable dynamically
      declare "$key=$value"
      ;;
    *)
      echo "Non Build Param: $arg"
      if [[ "$arg" == "clear" || "$arg" == "build" || "$arg" == "help" ]]; then
        eval "cmd_$arg"
      fi
      ;;
  esac
done


conandata_yml=$(cat <<YAML
# This file is managed by Conan, contents will be overwritten.
# To keep your changes, remove these comment lines, but the plugin won't be able to modify your requirements

requirements:
  - "gtest/1.16.0"

YAML
)

src_CMakeLists_no_cuda=$(cat <<CMakeLists
# Source directory: /src/CMakeLists.txt
include(\${CMAKE_SOURCE_DIR}/helpers.cmake)
include(./packages.cmake)
set(name ConanCuda)

file(GLOB_RECURSE LIB_SOURCES "lib/*.cpp")
file(GLOB_RECURSE LIB_HEADERS "lib/*.h" "lib/*.hpp")

# Copy the resources folder to build directory at build-time
add_custom_target(copy_resources ALL
        COMMAND \${CMAKE_COMMAND} -E copy_directory
        "\${CMAKE_SOURCE_DIR}/resources"
        "\${CMAKE_BINARY_DIR}/resources"
        COMMENT "Copying resources into build"
)
add_executable(\${name} main.cpp \${LIB_SOURCES} \${LIB_HEADERS})
add_dependencies(\${name} copy_resources)
target_link_all_packages("\${CONANDEPS_LEGACY}" "\${name}")
CMakeLists
)

src_CMakeLists_no_nccl=$(cat <<CMakeLists
# Source directory: /src/CMakeLists.txt
include(\${CMAKE_SOURCE_DIR}/helpers.cmake)
include(./packages.cmake)
set(name ConanCuda)

file(GLOB_RECURSE LIB_SOURCES "lib/*.cpp")
file(GLOB_RECURSE LIB_HEADERS "lib/*.h" "lib/*.hpp")

# Copy the resources folder to build directory at build-time
add_custom_target(copy_resources ALL
        COMMAND \${CMAKE_COMMAND} -E copy_directory
        "\${CMAKE_SOURCE_DIR}/resources"
        "\${CMAKE_BINARY_DIR}/resources"
        COMMENT "Copying resources into build"
)
add_executable(\${name} main.cu \${LIB_SOURCES} \${LIB_HEADERS})
add_dependencies(\${name} copy_resources)

set_target_properties(\${name} PROPERTIES
        POSITION_INDEPENDENT_CODE ON
        CUDA_SEPARABLE_COMPILATION ON
        CUDA_ARCHITECTURES "\${CMAKE_CUDA_ARCHITECTURES}"
        COMPILE_OPTIONS -G
)


target_link_all_packages("\${CONANDEPS_LEGACY}" "\${name}")
CMakeLists
)

root_CMakeLists_no_cuda=$(cat <<CMakeLists
include(./helpers.cmake)

cmake_minimum_required(VERSION 3.24 FATAL_ERROR)

project(ConanCuda LANGUAGES C CXX CUDA)
message("starting root cmake")

# Conan will define these in CMakeToolchain; keep defaults tiny
include(\${CMAKE_BINARY_DIR}/conan_toolchain.cmake OPTIONAL)

# ---- Global compile options ----
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CUDA_STANDARD 17)

load_conan_deps()
add_subdirectory(src)

CMakeLists
)


function configure_cmake(){

   cmake_path=$(which cmake)
   if [[ -n $cmake_path ]]; then

      if dpkg --compare-versions "$cmake_current" lt "3.24"; then
        sudo apt install cmake="$cmake_version-*"
      else
        echo "cmake already installed $cmake_current"
       fi
   else
     sudo apt install cmake="$cmake_version-*"
   fi

}


#================= NVIDIA + CUDA =============================================

function configure_nvidia_drivers() {
    if [[ -n $(which nvidia-smi) ]]; then
      printf "✅ Nvidia drivers already installed --> %s\n" "$(nvidia-smi --version | grep DRIVER)"
    else
      echo "installing driver version $nvidia_driver_version"
      sudo apt install nvidia-driver-$nvidia_driver_version
    fi
}

function configure_cuda_toolkit() {
    if [[ -n $(which nvcc) ]]; then
      printf "✅ Cuda Toolkit already installed \n %s" "$(nvcc --version | grep DRIVER)"
    else
      echo "installing driver version $nvidia_driver_version"
     # Add CUDA repository
     wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin
     sudo mv cuda-ubuntu2204.pin /etc/apt/preferences.d/cuda-repository-pin-600

     sudo apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/3bf863cc.pub
     sudo add-apt-repository "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/ /"

     sudo apt update
     sudo apt install -y cuda-${cuda_version//\./-}
    fi
}

function install_nccl(){
  if dpkg -s libnccl2 >/dev/null 2>&1 && dpkg -s libnccl-dev >/dev/null 2>&1; then
    echo "✅ NCCL already installed"
    return
  fi

  # 1) detect Ubuntu distro (e.g. “20.04” → “ubuntu2004”)
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    [ "$ID" = "ubuntu" ] || { echo "Error: only Ubuntu supported, got $ID"; exit 1; }
    ver=${VERSION_ID//./}           # strip the dot: “20.04” → “2004”
    distro="ubuntu${ver}"
  else
    echo "Error: cannot find /etc/os-release"; exit 1
  fi

  # 2) detect architecture & map dpkg → NVIDIA’s repo dir
  dpkg_arch=$(dpkg --print-architecture)
  case "$dpkg_arch" in
    amd64)   arch="x86_64"   ;;
    ppc64el) arch="ppc64le"   ;;
    arm64)   arch="sbsa"      ;;  # NVIDIA uses “sbsa” for ARM64
    *)       echo "Error: unsupported arch: $dpkg_arch"; exit 1;;
  esac

  # 3) build the repo base URL
  base="https://developer.download.nvidia.com/compute/cuda/repos"
  repo_url="${base}/${distro}/${arch}"

  # 4) grab & install the repo key + list (the “keyring” .deb is arch-agnostic)
  keyring_pkg="cuda-keyring_1.0-1_all.deb"
  wget -q "${repo_url}/${keyring_pkg}"
  sudo dpkg -i "${keyring_pkg}"
  rm -f "${keyring_pkg}"

  # 5) update & install NCCL
  sudo apt-get update
  sudo apt-get install -y libnccl2 libnccl-dev

  echo "✅ NCCL installed (distro=${distro}, arch=${arch})"
}




# ========================= PYTHON ===========================
function configure_python(){
#   global_python=$(which python3 2>/dev/null)
#   if [[ ! -s "${global_python}" ]]; then
 echo "installing python version $py_version"
 sudo apt install -y python$py_version python$py_version-venv python$py_version-dev
# py_path=$(which python3 | sed "s/python3/python$py_ver/g")

#   fi
}

function configure_venv() {
  if [ -s "$venv_bin" ];then
    echo "found py bin ${venv_bin}"
    path="$PWD$venv_bin:$PATH:$PATH"
    export PATH=$path
  else
    echo "creating venv"
    eval "$python_command -m venv $venv_name"
  fi
}



function configure_conan() {
  if [ -s "$venv_bin" ];then
    echo "found py bin ${venv_bin}"
    source "$venv_bin"
    pip3 install "conan==$conan_version"
  else
    eval "$python_command -m venv $venv_name"
    venv_bin="$venv_name/bin/activate"
    echo  creating $venv_bin
    path="$PWD$venv_bin:$PATH:$PATH"
    export PATH=$path
    source "$venv_bin"
    pip3 install "conan==$conan_version"
  fi
}



function prepare_conandata_yml(){
  conandata_path=$PWD/conandata.yml
  if [[ ! -f $(find $conandata_path) ]]; then
      echo "no conan data, populating..."
      echo "$conandata_yml" >> ./conandata.yml
  fi
}

function populate_repo(){
  targets=()
  for f in "${boiler_plate_files[@]}"; do
    if [[ $f == */ ]]; then
      targets+=("*$f*")
    else
       targets+=("*$f")
    fi
  done

  curl -sL https://codeload.github.com/slimnader/ConanCuda/tar.gz/master | tar -xzf - \
   --strip-components=1 \
   --wildcards \
   --no-anchored \
   "${targets[@]}"
}

function apply_names(){
  find . -path './bootstrap.sh' -prune -o -type f -print0 | xargs -0 sed -i "s/ConanCuda/$project_name/g"
}

function remove_cuda_configs(){
  echo "Removing Cuda Configurations "

  start_variables=$(cat conanfile.py | grep -n 'variables.*=.*{' | sed s/[^0-9]//g)
  end_rel_variables=$(tail -n +"$start_variables" ./conanfile.py| grep -no '^}'| head -n 1 |  sed s/[^0-9]//g )
  end_variables=$(( $start_variables + $end_rel_variables ))

  sed -i "${start_variables},${end_variables}d" conanfile.py
  sed -i "${start_variables}i\\variables = {}\\n" conanfile.py

  start_cached=$(cat conanfile.py | grep -n 'cached_env_vars.*=.*{' | sed s/[^0-9]//g)
  end_rel_cached=$(tail -n +"$start_cached" ./conanfile.py| grep -no '^}'| head -n 1 |  sed s/[^0-9]//g )
  end_cached=$(( $start_cached + $end_rel_cached ))

  sed -i "${start_cached},${end_cached}d" conanfile.py
  sed -i "${start_cached}i\\cached_env_vars = {}\\n" conanfile.py

  sed -i 's/CUDA//g' CMakeLists.txt
  sed -i 's/main\.cu/main\.cpp/g' src/CMakeLists.txt

  echo "$src_CMakeLists_no_cuda" > ./src/CMakeLists.txt
  mv ./src/main.cu ./src/main.cpp
}

function remove_nccl(){
    echo "$src_CMakeLists_no_nccl" > ./src/CMakeLists.txt
}
function show_current_configs(){
  if(($cuda == 1)); then
    install_cuda=YES
    else
      install_cuda=NO
  fi
  if(($nccl == 1)); then
      install_nccl=YES
    else
      install_nccl=NO
  fi
  cat <<EOF
CURRENT CONFIGS
    cmake version = $cmake_version
    python version = $py_version
    conan version = $conan_version
    Include CUDA?   $install_cuda
    Include NCCL?   $install_nccl

EOF
}

show_current_configs
if [[ "$1" != "clear" && "$1" != "build" && "$1" != "help" ]]; then
      configure_cmake
      populate_repo
      configure_python
      configure_venv
      configure_conan
      prepare_conandata_yml
      sudo mkdir resources
      if (( cuda == 0)); then
        nccl=0
        echo "Cuda will not be installed"
        remove_cuda_configs
      else
        configure_nvidia_drivers
        configure_cuda_toolkit
      fi
      if (( nccl == 0)); then
        remove_nccl
        echo "NCCL Library will not be included"
      else
        install_nccl
      fi
      apply_names
fi




