#!/bin/bash

set -e

export GIT_ADVICE_DETACHED_HEAD=false

# ================= 配置区 =================
FOX_TERM_VERSION="0.0.1"
OPENSSL_VERSION="openssl-3.6.3"
LIBSSH_VERSION="0.12.2"
MACOS_TARGET="14.0"
IOS_TARGET="16.0"

WORK_DIR="$(pwd)/xcframework_build"
SOURCE_DIR="${WORK_DIR}/sources"
DEPS_DIR="${WORK_DIR}/deps"
BUILD_DIR="${WORK_DIR}/build"
OUTPUT_DIR="$(pwd)/xcframework"

mkdir -p "${SOURCE_DIR}" "${DEPS_DIR}" "${BUILD_DIR}" "${OUTPUT_DIR}"

# 依赖检查
FOR_CMDS="cmake ninja git curl tar xcodebuild libtool nasm lipo autoconf automake"
for cmd in $FOR_CMDS; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd 未安装，请先安装 (例: brew install cmake ninja nasm autoconf automake libtool)"
        exit 1
    fi
done

# 检查 glibtoolize 或 libtoolize
if ! command -v glibtoolize &> /dev/null && ! command -v libtoolize &> /dev/null; then
    echo "Error: 未找到 libtoolize / glibtoolize，请先执行: brew install libtool"
    exit 1
fi

# ================= 1. 源码下载 =================
echo "==> [1/4] 克隆与下载依赖库源码..."

if [ ! -d "${SOURCE_DIR}/openssl" ]; then
    echo "正在克隆 OpenSSL (${OPENSSL_VERSION})..."
    git clone --depth 1 --branch "${OPENSSL_VERSION}" https://github.com/openssl/openssl.git "${SOURCE_DIR}/openssl"
fi

if [ ! -d "${SOURCE_DIR}/libssh" ]; then
    echo "正在下载 libssh (${LIBSSH_VERSION})..."
    mkdir -p "${SOURCE_DIR}/libssh"
    curl -L "https://www.libssh.org/files/0.12/libssh-${LIBSSH_VERSION}.tar.xz" | tar -xz -C "${SOURCE_DIR}/libssh" --strip-components=1
fi

# ================= 2. 编译依赖库 (OpenSSL) =================
compile_deps_single_arch() {
    local target_id=$1
    local arch=$2
    local sysroot=$3
    local min_flag=$4

    local install_prefix="${DEPS_DIR}/${target_id}"
    mkdir -p "${install_prefix}"

    echo "---> 编译依赖库 OpenSSL [${target_id}]..."

    if [ ! -f "${install_prefix}/lib/libssl.a" ]; then
        local sdk_path=$(xcrun --sdk ${sysroot} --show-sdk-path)
        local src_copy="${BUILD_DIR}/deps_build/${target_id}/openssl_src"
        rm -rf "${src_copy}"
        mkdir -p "${src_copy}"
        cp -R "${SOURCE_DIR}/openssl/" "${src_copy}"

        pushd "${src_copy}" > /dev/null
        local os_compiler=""
        case ${target_id} in
            "macos-arm64")       os_compiler="darwin64-arm64-cc" ;;
            "macos-x86_64")      os_compiler="darwin64-x86_64-cc" ;;
            "ios-arm64")         os_compiler="ios64-cross" ;;
            "ios-sim-arm64")     os_compiler="iossimulator-arm64-xcrun" ;;
        esac

        export CFLAGS="${min_flag} -isysroot ${sdk_path}"
        ./Configure ${os_compiler} no-shared no-async no-tests no-dso --prefix="${install_prefix}"
        make -j$(sysctl -n hw.ncpu) build_libs
        make install_dev
        popd > /dev/null
    fi
}

echo "==> [2/4] 构建各架构 OpenSSL..."
compile_deps_single_arch "macos-arm64" "arm64" "macosx" "-mmacosx-version-min=${MACOS_TARGET}"
compile_deps_single_arch "macos-x86_64" "x86_64" "macosx" "-mmacosx-version-min=${MACOS_TARGET}"
compile_deps_single_arch "ios-arm64" "arm64" "iphoneos" "-miphoneos-version-min=${IOS_TARGET}"
compile_deps_single_arch "ios-sim-arm64" "arm64" "iphonesimulator" "-mios-simulator-version-min=${IOS_TARGET}"

# ================= 3. 编译 libssh 并提取静态库 =================
compile_libssh_single_arch() {
    local target_id=$1
    local arch=$2
    local sysroot=$3
    local min_flag=$4

    local deps="${DEPS_DIR}/${target_id}"
    local bdir="${BUILD_DIR}/ssh_${target_id}"
    local install_dir="${BUILD_DIR}/install_${target_id}"
    local sdk_path=$(xcrun --sdk ${sysroot} --show-sdk-path)

    rm -rf "${bdir}" "${install_dir}"
    mkdir -p "${bdir}" "${install_dir}"

    echo "---> 编译并安装 libssh [${target_id}]..."

    cmake -B "${bdir}" -S "${SOURCE_DIR}/libssh" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${install_dir}" \
        -DCMAKE_OSX_SYSROOT="${sysroot}" \
        -DCMAKE_OSX_ARCHITECTURES="${arch}" \
        -DCMAKE_C_FLAGS="${min_flag} -isysroot ${sdk_path} -I${deps}/include -DCLIENT_BANNER_SSH2=\\\"SSH-2.0-libssh_${LIBSSH_VERSION}-FoxTerm_${FOX_TERM_VERSION}\\\"" \
        -DCMAKE_EXE_LINKER_FLAGS="-L${deps}/lib" \
        -DBUILD_SHARED_LIBS=OFF \
        -DWITH_GSSAPI=OFF \
        -DWITH_ZLIB=ON \
        -DWITH_EXAMPLES=OFF \
        -DWITH_SERVER=OFF \
        -DWITH_GSSAPI=OFF \
        -DOPENSSL_ROOT_DIR="${deps}" \
        -DOPENSSL_INCLUDE_DIR="${deps}/include" \
        -DOPENSSL_CRYPTO_LIBRARY="${deps}/lib/libcrypto.a" \
        -DOPENSSL_SSL_LIBRARY="${deps}/lib/libssl.a"

    # 执行构建与安装
    cmake --build "${bdir}" --target install

    # 仅导出 libssh.a 本身，不再打包 libcrypto.a 和 libssl.a
    local target_out="${BUILD_DIR}/packaged_${target_id}"
    mkdir -p "${target_out}"
    cp "${install_dir}/lib/libssh.a" "${target_out}/libssh.a"
}

echo "==> [3/4] 编译各架构 libssh..."
compile_libssh_single_arch "macos-arm64" "arm64" "macosx" "-mmacosx-version-min=${MACOS_TARGET}"
compile_libssh_single_arch "macos-x86_64" "x86_64" "macosx" "-mmacosx-version-min=${MACOS_TARGET}"
compile_libssh_single_arch "ios-arm64" "arm64" "iphoneos" "-miphoneos-version-min=${IOS_TARGET}"
compile_libssh_single_arch "ios-sim-arm64" "arm64" "iphonesimulator" "-mios-simulator-version-min=${IOS_TARGET}"

echo "---> 打包各 Platform 静态库..."
mkdir -p "${BUILD_DIR}/packaged_macos" "${BUILD_DIR}/packaged_ios-simulator" "${BUILD_DIR}/packaged_ios"

lipo -create \
    "${BUILD_DIR}/packaged_macos-arm64/libssh.a" \
    "${BUILD_DIR}/packaged_macos-x86_64/libssh.a" \
    -output "${BUILD_DIR}/packaged_macos/libssh.a"

cp "${BUILD_DIR}/packaged_ios-sim-arm64/libssh.a" "${BUILD_DIR}/packaged_ios-simulator/libssh.a"
cp "${BUILD_DIR}/packaged_ios-arm64/libssh.a" "${BUILD_DIR}/packaged_ios/libssh.a"

# ================= 4. 构建 Headers 及最终 XCFramework =================
echo "==> [4/4] 打包生成 XCFramework..."

prepare_headers() {
    local platform_name=$1
    local sample_target_id=$2
    local target_headers_dir="${BUILD_DIR}/Headers_${platform_name}"

    rm -rf "${target_headers_dir}"
    mkdir -p "${target_headers_dir}"

    # 从安装产物中复制完整的 include/libssh 目录
    cp -R "${BUILD_DIR}/install_${sample_target_id}/include/libssh" "${target_headers_dir}/"

    # 生成 Umbrella Header
    cat << 'EOF' > "${target_headers_dir}/libssh/ssh.h"
#include "callbacks.h"
#include "legacy.h"
#include "libssh.h"
#include "libssh_version.h"
#include "sftp.h"
#include "ssh2.h"
EOF

    # 生成 modulemap
    cat << 'EOF' > "${target_headers_dir}/libssh/module.modulemap"
module libssh {
    umbrella header "ssh.h"
    export *
}
EOF
}

prepare_headers "macos" "macos-arm64"
prepare_headers "ios" "ios-arm64"
prepare_headers "ios-simulator" "ios-sim-arm64"

rm -rf "${OUTPUT_DIR}/libssh.xcframework"

xcodebuild -create-xcframework \
    -library "${BUILD_DIR}/packaged_macos/libssh.a" -headers "${BUILD_DIR}/Headers_macos" \
    -library "${BUILD_DIR}/packaged_ios/libssh.a" -headers "${BUILD_DIR}/Headers_ios" \
    -library "${BUILD_DIR}/packaged_ios-simulator/libssh.a" -headers "${BUILD_DIR}/Headers_ios-simulator" \
    -output "${OUTPUT_DIR}/libssh.xcframework"

echo "=========================================="
echo "完成！已成功构建 XCFramework"
echo "输出文件: ${OUTPUT_DIR}/libssh.xcframework"
echo "=========================================="
