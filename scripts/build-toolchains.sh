#!/usr/bin/env bash

#this script is based on the firesim build toolchains script

# exit script if any command fails
set -e
set -o pipefail

RDIR=$(git rev-parse --show-toplevel)
: ${CHIPYARD_DIR:=${RDIR}} # default value is RDIR unless overridden

PRECOMPILED_REPO_HASH=56a40961c98db5e8f904f15dc6efd0870bfefd9e

usage() {
    echo "usage: ${0} [riscv-tools | esp-tools | ec2fast]"
    echo "   riscv: if set, builds the riscv toolchain (this is also the default)"
    echo "   hwacha: if set, builds esp-tools toolchain"
    echo "   ec2fast: if set, pulls in a pre-compiled RISC-V toolchain for an EC2 manager instance"
    exit "$1"
}

error() {
    echo "${0##*/}: ${1}" >&2
}

TOOLCHAIN="riscv-tools"
EC2FASTINSTALL="false"
FASTINSTALL="false"

while getopts 'hH-:' opt ; do
    case $opt in
    h|H)
        usage 3 ;;
    -)
        case $OPTARG in
        help)
            usage 3 ;;
        ec2fast) # Preserve compatibility
            EC2FASTINSTALL=true ;;
        *)
            error "invalid option: --${OPTARG}"
            usage 1 ;;
        esac ;;
    *)
        error "invalid option: -${opt}"
        usage 1 ;;
    esac
done

shift $((OPTIND - 1))

if [ "$1" = ec2fast ] ; then
    EC2FASTINSTALL=true
elif [ -n "$1" ] ; then
    TOOLCHAIN="$1"
fi


if [ "$EC2FASTINSTALL" = "true" ]; then
    if [ "$TOOLCHAIN" = "riscv-tools" ]; then
      cd "$RDIR"
      git clone https://github.com/firesim/firesim-riscv-tools-prebuilt.git
      cd firesim-riscv-tools-prebuilt
      git checkout "$PRECOMPILED_REPO_HASH"
      PREBUILTHASH="$(cat HASH)"
      git -C "${CHIPYARD_DIR}" submodule update --init "toolchains/${TOOLCHAIN}"
      cd "$CHIPYARD_DIR/toolchains/$TOOLCHAIN"
      GITHASH="$(git rev-parse HEAD)"
      cd "$RDIR"
      echo "prebuilt hash: $PREBUILTHASH"
      echo "git      hash: $GITHASH"
      if [[ $PREBUILTHASH == $GITHASH && "$EC2FASTINSTALL" == "true" ]]; then
          FASTINSTALL=true
          echo "Using fast pre-compiled install for riscv-tools"
      else
          error 'error: hash of precompiled toolchain does not match the riscv-tools submodule hash'
          exit -1
      fi
    else
          error "error: unsupported precompiled toolchain: ${TOOLCHAIN}"
          exit -1
    fi
fi

INSTALL_DIR="$TOOLCHAIN-install"

RISCV="$(pwd)/$INSTALL_DIR"

# install risc-v tools
export RISCV="$RISCV"

if [ "$FASTINSTALL" = true ]; then
    cd firesim-riscv-tools-prebuilt
    ./installrelease.sh
    mv distrib "$RISCV"
    # copy HASH in case user wants it later
    cp HASH "$RISCV"
    cd "$RDIR"
    rm -rf firesim-riscv-tools-prebuilt
else
    mkdir -p "$RISCV"

    SRCDIR="${CHIPYARD_DIR}/toolchains/${TOOLCHAIN}"
    if ! [ -d "${SRCDIR}" ] ; then
        error "unsupported toolchain: ${TOOLCHAIN}"
        exit -1
    fi

    echo "=> Initializing ${TOOLCHAIN} submodules"
    git submodule update --init "${SRCDIR}/riscv-gnu-toolchain"
    git -C "${SRCDIR}/riscv-gnu-toolchain" config submodule.qemu.update none
    git config submodule.toolchains/riscv-tools/riscv-openocd.update none
    git submodule update --init --recursive "${SRCDIR}" #--jobs 8

    # Scale number of parallel make jobs by hardware thread count
    ncpu="$(getconf _NPROCESSORS_ONLN || # GNU
        getconf NPROCESSORS_ONLN || # *BSD, Solaris
        nproc --all || # Linux
        sysctl -n hw.ncpu || # *BSD, OS X
        :)" 2>/dev/null
    case ${ncpu} in
    ''|*[^0-9]*) ;; # Ignore non-integer values
    *) export MAKEFLAGS="-j ${ncpu}" ;;
    esac

    MAKE=$(command -v gmake || command -v make)

    # Derived from
    # https://github.com/riscv/riscv-tools/blob/master/build.common
    build_submodule() ( # <submodule> <configure args>
        name=$1
        shift

        echo "=>  Starting ${name} build"
        cd "${CHIPYARD_DIR}/toolchains/${TOOLCHAIN}/${name}"

        if [ -e build ] ; then
            echo "==>  Removing existing ${name}/build directory"
            rm -rf build
        fi
        if ! [ -e configure ] ; then
            echo "==>  Updating autoconf files for ${name}"
            find . -iname configure.ac -type f -print0 |
            while read -r -d '' file ; do
                mkdir -p -- "${file%/*}/m4"
            done
            autoreconf -i
        fi

        mkdir -p build
        cd build
        {
            export PATH="${RISCV}/bin:${PATH}"
            echo "==>  Configuring ${name}"
            ../configure "$@"
            echo "==>  Building ${name}"
            "${MAKE}"
            echo "==>  Installing ${name}"
            "${MAKE}" install
        } 2>&1 | tee build.log
    )

    # Run a secondary make target
    build_extra() ( # <submodule> <target>
        cd "${SRCDIR}/${1}/build"
        "${MAKE}" "$2" 2>&1 | tee "build-${2}.log"
    )

    echo '=> Starting RISC-V ELF toolchain build'
    build_submodule riscv-isa-sim --prefix="${RISCV}"
    # build static libfesvr library for linking into firesim driver (or others)
    echo '==>  Installing libfesvr static library'
    build_extra riscv-isa-sim libfesvr.a
    cp -p "${SRCDIR}/riscv-isa-sim/build/libfesvr.a" "${RISCV}/lib/"

    build_submodule riscv-gnu-toolchain --prefix="${RISCV}"
    CC= CXX= build_submodule riscv-pk --prefix="${RISCV}" --host=riscv64-unknown-elf
    build_submodule riscv-tests --prefix="${RISCV}/riscv64-unknown-elf"
    echo '=> Completed RISC-V ELF toolchain installation'

    # build linux toolchain
    echo '=> Starting RISC-V GNU/Linux toolchain build'
    build_extra riscv-gnu-toolchain linux
    echo '=> Completed RISC-V GNU/Linux toolchain installation'
fi


{
    echo "export CHIPYARD_TOOLCHAIN_SOURCED=1"
    echo "export RISCV=$(printf '%q' "$RISCV")"
    echo "export PATH=\${RISCV}/bin:\${PATH}"
    echo "export LD_LIBRARY_PATH=\${RISCV}/lib\${LD_LIBRARY_PATH:+":\${LD_LIBRARY_PATH}"}"
} > "${RDIR}/env.sh"
echo "Toolchain Build Complete!"
