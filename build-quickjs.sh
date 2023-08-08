# cross-platform build script for quickjs shared library based on Zig & MinGW
# Usage:
#  bash Make.sh -pwindows -ax64
#  bash Make.sh -pmacos -aaarch64

# Read PLATFORM and ARCH from options
#   PLATFORM: linux, windows, macos
#   ARCH: x64, arm, aarch64

PLATFORM=linux
ARCH=x64
CC="zig cc"
BUILD_REPL=""
BUILD_REPL_SOURCE=""

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -p|--platform)
            PLATFORM="$2"
            shift
            shift
            ;;
        -a|--arch)
            ARCH="$2"
            shift
            shift
            ;;
        --build-repl-source)
            BUILD_REPL_SOURCE="true"
            shift
            ;;
        --build-repl)
            BUILD_REPL="true"
            shift
            ;;
        *)
            echo "unknown option: $key"

            # echo help
            echo "usage: bash Make.sh -p<platform> -a<arch>"
            echo "  -p|--platform: linux, windows, macos"
            echo "  -a|--arch: x64, arm, aarch64"
            echo "  --build-repl: build repl"
            echo "  --build-repl-source: build repl source code"
            exit 1
            ;;
    esac
done


echo "PLATFORM: $PLATFORM";
echo "ARCH: $ARCH";

LINK_ARGS=""
COMP_ARGS=""
DLEXT=""

# C sources should define CONFIG_BIGNUM=1 and CONFIG_VERSION="2021-03-27"
COMP_ARGS="$COMP_ARGS -D_GNU_SOURCE -DCONFIG_BIGNUM -DCONFIG_VERSION=\"2021-03-27\""

# If not windows, then CONFIG_WIN32 is not defined.
# Besides, # compute zig target from PLATFORM and ARCH
if [ "$PLATFORM" == "windows" ]; then
    echo "building for windows"
    LINK_ARGS="$LINK_ARGS -static -s"
    DLEXT=".dll"

    echo "warning: windows build only supports the host architecture"
    COMP_ARGS="$COMP_ARGS -ldl"
    CC="gcc"

    # if [ "$ARCH" == "x64" ]; then
    #     echo "building for x64"
    #     COMP_ARGS="$COMP_ARGS -target x86_64-windows-gnu"
    # elif [ "$ARCH" == "arm" ]; then
    #     echo "building for arm"
    #     COMP_ARGS="$COMP_ARGS -target armv7-windows-gnu"
    # elif [ "$ARCH" == "aarch64" ]; then
    #     echo "building for aarch64"
    #     COMP_ARGS="$COMP_ARGS -target aarch64-windows-gnu"
    # else
    #     echo "ARCH not supported"
    #     exit 1
    # fi

elif [ "$PLATFORM" == "linux" ]; then
    echo "building for linux"
    COMP_ARGS="$COMP_ARGS -lm -ldl -lpthread"
    DLEXT=".so"

    if [ "$ARCH" == "x64" ]; then
        echo "building for x64"
        COMP_ARGS="$COMP_ARGS -target x86_64-linux-gnu.2.17"
    elif [ "$ARCH" == "arm" ]; then
        echo "building for arm"
        COMP_ARGS="$COMP_ARGS -target armv7-linux-gnueabihf"
    elif [ "$ARCH" == "aarch64" ]; then
        echo "building for aarch64"
        COMP_ARGS="$COMP_ARGS -target aarch64-linux-gnu"
    else
        echo "ARCH not supported"
        exit 1
    fi

elif [ "$PLATFORM" == "macos" ]; then
    echo "building for macos"
    DLEXT=".dylib"

    if [ "$ARCH" == "x64" ]; then
        echo "building for x64"
        COMP_ARGS="$COMP_ARGS -target x86_64-macos-none"
    elif [ "$ARCH" == "arm" ]; then
        echo "building for arm"
        echo "arm macos not supported"
        exit 1
    elif [ "$ARCH" == "aarch64" ]; then
        echo "building for aarch64"
        COMP_ARGS="$COMP_ARGS -target aarch64-macos-none"
    else
        echo "ARCH not supported"
        exit 1
    fi
else
    echo "PLATFORM not supported"
    exit 1
fi


# macos
COMP_ARGS="$COMP_ARGS -Werror=incompatible-pointer-types -Wno-int-conversion"

# avoid zig to cause illegal instructions:  https://github.com/ziglang/zig/issues/4830#issuecomment-605491606
COMP_ARGS="$COMP_ARGS -O2"

prefix=./bin/quickjs/${PLATFORM}-${ARCH}
mkdir -p $prefix

echo "COMP_ARGS: $COMP_ARGS"

headerDirectory="./git-deps/quickjs"
sources=(
    ${headerDirectory}/cutils.c
    ${headerDirectory}/libbf.c
    ${headerDirectory}/libregexp.c
    ${headerDirectory}/libunicode.c
    ${headerDirectory}/quickjs.c
    ${headerDirectory}/quickjs-libc.c
)

# create shared library
echo "creating shared library"
echo "$CC -std=gnu99 -shared -fPIC -o $prefix/libquickjs$DLEXT ${sources[@]} $COMP_ARGS $LINK_ARGS -I${headerDirectory}"
$CC -std=gnu99 -shared -fPIC -o $prefix/libquickjs$DLEXT ${sources[@]} $COMP_ARGS $LINK_ARGS -I${headerDirectory}

# compile js bytecode compiler
echo "$CC -std=gnu99 -o $prefix/qjsc ${headerDirectory}/qjsc.c ${sources[@]} $COMP_ARGS $LINK_ARGS -I${headerDirectory}"
$CC -std=gnu99 -o $prefix/qjsc ${headerDirectory}/qjsc.c ${sources[@]} $COMP_ARGS $LINK_ARGS -I${headerDirectory}

if [ -z "$BUILD_REPL_SOURCE" ]; then
    echo "not building repl source"
else
    rm -rf ./build/quickjs
    mkdir -p ./build/quickjs
    chmod u+x ./$prefix/qjsc
    ./$prefix/qjsc -c -o ./build/quickjs/repl.c -m ${headerDirectory}/repl.js
    ./$prefix/qjsc -c -o ./build/quickjs/qjscalc.c -m ${headerDirectory}/qjscalc.js
fi

if [ -z "$BUILD_REPL" ]; then
    echo "not building repl"
else
    # check if build/quickjs/repl.c exists
    if [ ! -f "./build/quickjs/repl.c" ]; then
        echo "repl.c not found, run with --build-repl-source"
        exit 1
    fi
    echo "$CC -std=gnu99 -o $prefix/qjs ${headerDirectory}/qjs.c ./build/quickjs/qjscalc.c ./build/quickjs/repl.c ${sources[@]} $COMP_ARGS $LINK_ARGS -I${headerDirectory}"
    $CC -std=gnu99 -o $prefix/qjs ${headerDirectory}/qjs.c ./build/quickjs/qjscalc.c ./build/quickjs/repl.c\
         ${sources[@]} $COMP_ARGS $LINK_ARGS -I${headerDirectory}
fi
