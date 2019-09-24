#!/usr/bin/env bash

# exit script if any command fails
set -e
set -o pipefail

RDIR=$(git rev-parse --show-toplevel)

if [ -z "${RISCV}" ] ; then
    ! [ -r "${RDIR}/env.sh" ] || . "${RDIR}/env.sh"
    if [ -z "${RISCV}" ] ; then
        echo "${0}: set the RISCV environment variable to desired install path"
        exit 1
    fi
fi

echo '=>  Starting riscv-openocd build'
srcdir='toolchains/riscv-tools/riscv-openocd'
git config --unset submodule."${srcdir}".update || :
git submodule update --init "${RDIR}/${srcdir}"

cd "${RDIR}/${srcdir}"
if [ -e build ] ; then
    echo '==>  Removing existing riscv-openocd/build directory'
    rm -rf build
fi

(
    echo '==>  Bootstrapping riscv-openocd'
    ./bootstrap
    mkdir -p build
    cd build
    echo '==>  Configuring riscv-openocd'
    ../configure --prefix="${RISCV}" --enable-remote-bitbang --enable-jtag_vpi --disable-werror
    echo '==>  Building riscv-openocd'
    MAKE=$(command -v gmake || command -v make)
    "${MAKE}"
    echo '==>  Installing riscv-openocd'
    "${MAKE}" install
) 2>&1 | tee build/build.log
