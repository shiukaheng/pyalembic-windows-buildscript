#!/usr/bin/env bash
# build.sh  ── POSIX/Bash port of build.ps1  (tested on Ubuntu 22.04 & manylinux_2_28)

set -euo pipefail
IFS=$'\n\t'

# ──────────────────────────  Parameters  ──────────────────────────
BOOST_URL="${BOOST_URL:-https://github.com/boostorg/boost/releases/download/boost-1.87.0/boost-1.87.0-b2-nodocs.tar.gz}"
BOOST_DIR="boost"                           # after extraction / rename
PYTHON_EXE="${PYTHON_EXE:-python3}"         # override with PYTHON_EXE=/opt/python/cp312-cp312/bin/python
SKIP_BOOST="${SKIP_BOOST:-0}"
SKIP_IMATH="${SKIP_IMATH:-0}"
SKIP_ALEMBIC="${SKIP_ALEMBIC:-0}"
SKIP_PACKAGING="${SKIP_PACKAGING:-0}"
SKIP_INSTALL="${SKIP_INSTALL:-0}"

echo "Build started: $(date)"
echo "Python executable: ${PYTHON_EXE}"

# turn relative paths into absolute for later CMake cache reuse
BOOST_ROOT="$(realpath "${BOOST_DIR}" || echo "")"

# ──────────────────────────  Build Boost  ─────────────────────────
if [[ "${SKIP_BOOST}" == 0 ]]; then
  if [[ ! -d "${BOOST_DIR}" ]]; then
    echo "› Downloading Boost …"
    curl -L "${BOOST_URL}" -o boost.tgz
    tar -xf boost.tgz
    mv "$(tar -tf boost.tgz | head -1 | cut -f1 -d/)" "${BOOST_DIR}"
  fi

  pushd "${BOOST_DIR}"
    ./bootstrap.sh
    echo "using python : : ${PYTHON_EXE} ;" > user-config.jam
    ./b2 -j"$(nproc)"                       \
        --with-python                       \
        variant=release                     \
        link=shared                         \
        cxxstd=17                           \
        threading=multi
  popd
  BOOST_ROOT="$(realpath "${BOOST_DIR}")"
fi

# ──────────────────────────  Build Imath  ─────────────────────────
if [[ "${SKIP_IMATH}" == 0 ]]; then
  git clone --depth=1 https://github.com/AcademySoftwareFoundation/Imath || true
  pushd Imath
    # rollback one commit to avoid the Alembic issue mentioned in the PS script
    git checkout 84f9a674802f6c3197bd478c9b40399f451fecb3
    mkdir -p build && cd build

    cmake ..                               \
      -DCMAKE_BUILD_TYPE=Release           \
      -DPython_EXECUTABLE="${PYTHON_EXE}"  \
      -DPython3_EXECUTABLE="${PYTHON_EXE}" \
      -DBoost_ROOT="${BOOST_ROOT}"         \
      -DPYTHON=ON                          \
      -DCMAKE_INSTALL_PREFIX="../_installed"
    cmake --build . -j"$(nproc)"
    cmake --install .
  popd
fi

# ──────────────────────────  Build Alembic  ───────────────────────
if [[ "${SKIP_ALEMBIC}" == 0 ]]; then
  git clone --depth=1 https://github.com/alembic/alembic || true
  pushd alembic
    mkdir -p build && cd build
    cmake ..                               \
      -DCMAKE_BUILD_TYPE=Release           \
      -DUSE_PYALEMBIC=ON                   \
      -DImath_DIR="../Imath/_installed/lib/cmake/Imath" \
      -DPython3_EXECUTABLE="${PYTHON_EXE}" \
      -DBoost_ROOT="${BOOST_ROOT}"         \
      -DALEMBIC_PYTHON_INSTALL_DIR="../_installed/lib/python_site"
    cmake --build . -j"$(nproc)"
    cmake --install .
  popd
fi

# ──────────────────────────  Wheel build / test  ──────────────────
if [[ "${SKIP_PACKAGING}" == 0 ]]; then
  "${PYTHON_EXE}" -m pip install --upgrade pip setuptools wheel
  "${PYTHON_EXE}" setup.py bdist_wheel
fi

if [[ "${SKIP_INSTALL}" == 0 ]]; then
  "${PYTHON_EXE}" -m pip install dist/*.whl --force-reinstall --upgrade
  "${PYTHON_EXE}" - <<'PYTEST'
import alembic, os, sys
print("Alembic version:", alembic.Abc.GetLibraryVersion())
arch = alembic.Abc.OArchive("dummy.abc")
assert os.path.exists("dummy.abc")
print("Smoke-test OK ✅")
PYTEST
fi
echo "Build finished: $(date)"
