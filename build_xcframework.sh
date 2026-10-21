#!/bin/bash

set -e

export GIT_ADVICE_DETACHED_HEAD=false

# ================= 配置区 =================
FOX_TERM_VERSION="0.0.1"
LIBSSH_VERSION="0.12.2"
MACOS_TARGET="14.0"
IOS_TARGET="17.0"

WORK_DIR="$(pwd)/xcframework_build"
SOURCE_DIR="${WORK_DIR}/sources"
BUILD_DIR="${WORK_DIR}/build"
OUTPUT_DIR="$(pwd)/xcframework"

# OpenSSL 预编译产物路径 (基于您指定的 ../OpenSSL/openssl_xcframework_build)
OPENSSL_BUILD_DIR="$(cd "$(pwd)/../OpenSSL/openssl_xcframework_build" && pwd)"

mkdir -p "${SOURCE_DIR}" "${BUILD_DIR}" "${OUTPUT_DIR}"

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
    echo "Error: 未找到 libtoolize / libtoolize，请先执行: brew install libtool"
    exit 1
fi

# 检查 OpenSSL 预编译目录是否存在
if [ ! -d "${OPENSSL_BUILD_DIR}" ]; then
    echo "Error: 未找到 OpenSSL 预编译路径: ${OPENSSL_BUILD_DIR}，请先编译 OpenSSL！"
    exit 1
fi

# ================= 1. 源码下载 (仅保留 libssh) =================
echo "==> [1/3] 下载 libssh 源码..."

if [ ! -d "${SOURCE_DIR}/libssh" ]; then
    echo "正在下载 libssh (${LIBSSH_VERSION})..."
    mkdir -p "${SOURCE_DIR}/libssh"
    curl -L "https://www.libssh.org/files/0.12/libssh-${LIBSSH_VERSION}.tar.xz" | tar -xz -C "${SOURCE_DIR}/libssh" --strip-components=1
fi

# ================= 2. 编译 libssh 并链接外部 OpenSSL =================
compile_libssh_single_arch() {
    local target_id=$1
    local arch=$2
    local sysroot=$3
    local min_flag=$4

    # 映射外部 OpenSSL 对应的架构产物目录
    local openssl_arch_dir="${OPENSSL_BUILD_DIR}/build/install_${target_id}"
    if [ ! -d "${openssl_arch_dir}" ]; then
        echo "Error: 找不到 OpenSSL 针对架构 [${target_id}] 的产物目录: ${openssl_arch_dir}"
        exit 1
    fi

    local bdir="${BUILD_DIR}/ssh_${target_id}"
    local install_dir="${BUILD_DIR}/install_${target_id}"
    local sdk_path=$(xcrun --sdk ${sysroot} --show-sdk-path)

    rm -rf "${bdir}" "${install_dir}"
    mkdir -p "${bdir}" "${install_dir}"

    echo "---> 编译并安装 libssh [Release] [${target_id}]..."

    cmake -B "${bdir}" -S "${SOURCE_DIR}/libssh" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${install_dir}" \
        -DCMAKE_OSX_SYSROOT="${sysroot}" \
        -DCMAKE_OSX_ARCHITECTURES="${arch}" \
        -DCMAKE_C_FLAGS="${min_flag} -isysroot ${sdk_path} -O3 -DNDEBUG -I${openssl_arch_dir}/include -DCLIENT_BANNER_SSH2=\\\"SSH-2.0-libssh_${LIBSSH_VERSION}-FoxTerm_${FOX_TERM_VERSION}\\\"" \
        -DCMAKE_EXE_LINKER_FLAGS="-L${openssl_arch_dir}/lib" \
        -DBUILD_SHARED_LIBS=OFF \
        -DWITH_GSSAPI=OFF \
        -DWITH_ZLIB=ON \
        -DWITH_EXAMPLES=OFF \
        -DWITH_SERVER=OFF \
        -DOPENSSL_ROOT_DIR="${openssl_arch_dir}" \
        -DOPENSSL_INCLUDE_DIR="${openssl_arch_dir}/include" \
        -DOPENSSL_CRYPTO_LIBRARY="${openssl_arch_dir}/lib/libcrypto.a" \
        -DOPENSSL_SSL_LIBRARY="${openssl_arch_dir}/lib/libssl.a"

    # 执行构建与安装
    cmake --build "${bdir}" --target install

    # 导出编译好的 libssh.a
    local target_out="${BUILD_DIR}/packaged_${target_id}"
    mkdir -p "${target_out}"
    cp "${install_dir}/lib/libssh.a" "${target_out}/libssh.a"

    # 针对 Release 模式剥离符号
    strip -S "${target_out}/libssh.a"
}

echo "==> [2/3] 编译各架构 libssh..."
compile_libssh_single_arch "macos-arm64"     "arm64"  "macosx"          "-mmacosx-version-min=${MACOS_TARGET}"
compile_libssh_single_arch "macos-x86_64"    "x86_64" "macosx"          "-mmacosx-version-min=${MACOS_TARGET}"
compile_libssh_single_arch "ios-arm64"       "arm64"  "iphoneos"        "-miphoneos-version-min=${IOS_TARGET}"
compile_libssh_single_arch "ios-sim-arm64"   "arm64"  "iphonesimulator" "-mios-simulator-version-min=${IOS_TARGET}"

echo "---> 打包各 Platform 静态库..."
mkdir -p "${BUILD_DIR}/packaged_macos" "${BUILD_DIR}/packaged_ios-simulator" "${BUILD_DIR}/packaged_ios"

lipo -create \
    "${BUILD_DIR}/packaged_macos-arm64/libssh.a" \
    "${BUILD_DIR}/packaged_macos-x86_64/libssh.a" \
    -output "${BUILD_DIR}/packaged_macos/libssh.a"

cp "${BUILD_DIR}/packaged_ios-sim-arm64/libssh.a" "${BUILD_DIR}/packaged_ios-simulator/libssh.a"
cp "${BUILD_DIR}/packaged_ios-arm64/libssh.a" "${BUILD_DIR}/packaged_ios/libssh.a"

# ================= 3. 构建 Headers 及最终 XCFramework =================
echo "==> [3/3] 打包生成 libssh.xcframework..."

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
echo "完成！已成功构建 Release 版 libssh.xcframework"
echo "输出文件: ${OUTPUT_DIR}/libssh.xcframework"
echo "=========================================="
