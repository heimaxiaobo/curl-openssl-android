#!/bin/bash -e
set -o pipefail

# 功能: 初始化构建路径及通用配置
# 说明: 将工作目录设为脚本所在目录，设置最低 API 等级与构建输出目录
WORK_PATH=$(cd "$(dirname "$0")";pwd)
MIN_API=21
HOST_TAG=linux-x86_64
BUILD_DIR=${WORK_PATH}/build
OPENSSL_SRC_DIR=${WORK_PATH}/openssl-${OPENSSL_VERSION}
CURL_SRC_DIR=${WORK_PATH}/curl-${CURL_VERSION}

# 调试与HTTP/3开关
# DEBUG: 设置为1时输出更详细的调试信息（包括命令跟踪）
# ENABLE_HTTP3: 设置为1时启用HTTP/3（默认关闭）
DEBUG=${DEBUG:-1}
ENABLE_HTTP3=${ENABLE_HTTP3:-0}

# 设置HTTP/3相关源码目录
NGHTTP3_SRC_DIR=${WORK_PATH}/nghttp3-${NGHTTP3_VERSION}
NGTCP2_SRC_DIR=${WORK_PATH}/ngtcp2-${NGTCP2_VERSION}
NGHTTP2_SRC_DIR=${WORK_PATH}/nghttp2-${NGHTTP2_VERSION}

# 功能: 设置NDK版本与工具链路径
# 说明: 若未在环境中指定 ANDROID_NDK_VERSION，则默认使用 r28c
ANDROID_NDK_VERSION=${ANDROID_NDK_VERSION:-r28c}
export ANDROID_NDK_ROOT=${WORK_PATH}/android-ndk-${ANDROID_NDK_VERSION}
TOOLCHAIN=${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/${HOST_TAG}
PATH=${TOOLCHAIN}/bin:$PATH

# 调试输出环境信息
if [ "${DEBUG}" = "1" ]; then
    set -x
    echo "[DEBUG] 工作目录: ${WORK_PATH}"
    echo "[DEBUG] 构建目录: ${BUILD_DIR}"
    echo "[DEBUG] ANDROID_NDK_VERSION: ${ANDROID_NDK_VERSION}"
    echo "[DEBUG] ANDROID_NDK_ROOT: ${ANDROID_NDK_ROOT}"
    echo "[DEBUG] TOOLCHAIN: ${TOOLCHAIN}"
    echo "[DEBUG] PATH: ${PATH}"
    echo "[DEBUG] ANDROID_ABI: ${ANDROID_ABI}"
    echo "[DEBUG] MIN_API: ${MIN_API}"
    echo "[DEBUG] OPENSSL_VERSION: ${OPENSSL_VERSION}"
    echo "[DEBUG] CURL_VERSION: ${CURL_VERSION}"
    echo "[DEBUG] NGHTTP3_VERSION: ${NGHTTP3_VERSION}"
    echo "[DEBUG] NGTCP2_VERSION: ${NGTCP2_VERSION}"
    echo "[DEBUG] ENABLE_HTTP3: ${ENABLE_HTTP3}"
fi


##
## 函数: build_openssl
## 作用: 编译并安装 OpenSSL 到指定 ABI 的目标安装目录
## 参数:
##   $1 TARGET_HOST   目标三元组前缀 (如 aarch64-linux-android)
##   $2 OPENSSL_ARCH  OpenSSL配置目标 (如 android-arm64)
## 说明: 保留HTTP/3相关所需加密算法，并仅安装软件部分（不含测试与工具）
##
function build_openssl() {
    TARGET_HOST=$1
    OPENSSL_ARCH=$2
    INSTALL_DIR=${BUILD_DIR}/openssl-${OPENSSL_VERSION}/${ANDROID_ABI}
    mkdir -p ${INSTALL_DIR}
    
    # 修改OpenSSL编译选项，保留HTTP/3所需的加密算法
    echo "[DEBUG] OpenSSL Configure 目标: ${OPENSSL_ARCH}, 安装目录: ${INSTALL_DIR}"
    ./Configure ${OPENSSL_ARCH} no-tests no-unit-test shared -D__ANDROID_API__=${MIN_API} --prefix=${INSTALL_DIR} -fPIC \
    -ffunction-sections -fdata-sections \
    enable-tls1_3 enable-ec enable-ecdh enable-ecdsa

    make -j$(($(getconf _NPROCESSORS_ONLN) + 1))
    make install_sw
    #clean up
    rm -rf ${INSTALL_DIR}/bin
    rm -rf ${INSTALL_DIR}/share
    rm -rf ${INSTALL_DIR}/ssl
    rm -rf ${INSTALL_DIR}/lib/engines*
    rm -rf ${INSTALL_DIR}/lib/pkgconfig
    # Keep dynamic libraries but remove unnecessary files
    rm -rf ${INSTALL_DIR}/lib/ossl-modules
}

##
## 函数: build_nghttp3
## 作用: 以静态库方式编译并安装 nghttp3（HTTP/3的HTTP库）
## 参数:
##   $1 TARGET_HOST   目标三元组前缀 (如 aarch64-linux-android)
## 说明: 仅构建库，不构建共享库与可执行文件
##
function build_nghttp3() {
    export TARGET_HOST=$1
    export ANDROID_ARCH=${ANDROID_ABI}
    export AR=${TOOLCHAIN}/bin/llvm-ar
    export CC=${TOOLCHAIN}/bin/${TARGET_HOST}${MIN_API}-clang
    export AS=${CC}
    export CXX=${TOOLCHAIN}/bin/${TARGET_HOST}${MIN_API}-clang++
    export LD=${TOOLCHAIN}/bin/ld
    export RANLIB=${TOOLCHAIN}/bin/llvm-ranlib
    export STRIP=${TOOLCHAIN}/bin/llvm-strip
    
    INSTALL_DIR=${BUILD_DIR}/nghttp3-${NGHTTP3_VERSION}/${ANDROID_ABI}
    mkdir -p ${INSTALL_DIR}
    
    # 配置nghttp3
    autoreconf -fi
    ./configure --host=${TARGET_HOST} \
                --target=${TARGET_HOST} \
                --prefix=${INSTALL_DIR} \
                --enable-lib-only \
                --disable-shared \
                --enable-static
    
    make -j$(($(getconf _NPROCESSORS_ONLN) + 1))
    make install
    
    # 清理
    rm -rf ${INSTALL_DIR}/bin
    rm -rf ${INSTALL_DIR}/share
    rm -rf ${INSTALL_DIR}/lib/pkgconfig
}

##
## 函数: build_ngtcp2
## 作用: 以静态库方式编译并安装 ngtcp2（HTTP/3所需的QUIC传输层库），并链接 OpenSSL
## 参数:
##   $1 TARGET_HOST   目标三元组前缀 (如 aarch64-linux-android)
## 说明: 仅构建库，且通过 --with-openssl 指定 OpenSSL 路径
##
function build_ngtcp2() {
    export TARGET_HOST=$1
    export ANDROID_ARCH=${ANDROID_ABI}
    export AR=${TOOLCHAIN}/bin/llvm-ar
    export CC=${TOOLCHAIN}/bin/${TARGET_HOST}${MIN_API}-clang
    export AS=${CC}
    export CXX=${TOOLCHAIN}/bin/${TARGET_HOST}${MIN_API}-clang++
    export LD=${TOOLCHAIN}/bin/ld
    export RANLIB=${TOOLCHAIN}/bin/llvm-ranlib
    export STRIP=${TOOLCHAIN}/bin/llvm-strip
    
    INSTALL_DIR=${BUILD_DIR}/ngtcp2-${NGTCP2_VERSION}/${ANDROID_ABI}
    mkdir -p ${INSTALL_DIR}
    
    # 配置ngtcp2
    autoreconf -fi
    ./configure --host=${TARGET_HOST} \
                --target=${TARGET_HOST} \
                --prefix=${INSTALL_DIR} \
                --with-openssl=${BUILD_DIR}/openssl-${OPENSSL_VERSION}/${ANDROID_ABI} \
                --enable-lib-only \
                --disable-shared \
                --enable-static
    
    make -j$(($(getconf _NPROCESSORS_ONLN) + 1))
    make install
    
    # 清理
    rm -rf ${INSTALL_DIR}/bin
    rm -rf ${INSTALL_DIR}/share
    rm -rf ${INSTALL_DIR}/lib/pkgconfig
}

##
## 函数: build_nghttp2
## 作用: 以共享库方式编译并安装 nghttp2（HTTP/2 所需的库），供 Curl 链接使用
## 参数:
##   $1 TARGET_HOST   目标三元组前缀 (如 aarch64-linux-android)
## 说明:
## - 开启 --enable-lib-only，仅构建库本身，不编译可执行示例
## - 启用共享库（.so），关闭静态库，便于在 Android 端以动态依赖方式加载
## - 为了让 Curl 的 configure 能够顺利检测到 nghttp2，这里保留 lib/pkgconfig（不在此函数中清理）
##
function build_nghttp2() {
    export TARGET_HOST=$1
    export ANDROID_ARCH=${ANDROID_ABI}
    export AR=${TOOLCHAIN}/bin/llvm-ar
    export CC=${TOOLCHAIN}/bin/${TARGET_HOST}${MIN_API}-clang
    export AS=${CC}
    export CXX=${TOOLCHAIN}/bin/${TARGET_HOST}${MIN_API}-clang++
    export LD=${TOOLCHAIN}/bin/ld
    export RANLIB=${TOOLCHAIN}/bin/llvm-ranlib
    export STRIP=${TOOLCHAIN}/bin/llvm-strip

    INSTALL_DIR=${BUILD_DIR}/nghttp2-${NGHTTP2_VERSION}/${ANDROID_ABI}
    mkdir -p ${INSTALL_DIR}

    echo "[DEBUG] nghttp2 安装目录: ${INSTALL_DIR}"
    autoreconf -fi || true
    ./configure --host=${TARGET_HOST} \
                --target=${TARGET_HOST} \
                --prefix=${INSTALL_DIR} \
                --enable-lib-only \
                --enable-shared \
                --disable-static

    make -j$(($(getconf _NPROCESSORS_ONLN) + 1))
    make install

    # 清理不必要目录（保留 lib/pkgconfig 以便 curl 检测）
    rm -rf ${INSTALL_DIR}/bin
    rm -rf ${INSTALL_DIR}/share

    # 构建结果提示
    if [ -f "${INSTALL_DIR}/lib/libnghttp2.so" ] || [ -f "${INSTALL_DIR}/lib/libnghttp2.a" ]; then
        echo "[INFO] nghttp2 已安装到: ${INSTALL_DIR}"
        ls -l "${INSTALL_DIR}/lib" || true
    else
        echo "[WARN] 未找到libnghttp2库，请检查nghttp2源代码与配置。"
    fi
}

##
## 函数: build_curl
## 作用: 编译并安装 Curl，启用 HTTP/3 所需的 nghttp3 与 ngtcp2 支持，并链接 OpenSSL
## 参数:
##   $1 TARGET_HOST   目标三元组前缀 (如 aarch64-linux-android)
## 说明: 精简禁用不需要的协议/特性，启用共享库（.so），关闭静态库
##
function build_curl() {
    export TARGET_HOST=$1
    export ANDROID_ARCH=${ANDROID_ABI}
    export AR=${TOOLCHAIN}/bin/llvm-ar
    export CC=${TOOLCHAIN}/bin/${TARGET_HOST}${MIN_API}-clang
    export AS=${CC}
    export CXX=${TOOLCHAIN}/bin/${TARGET_HOST}${MIN_API}-clang++
    export LD=${TOOLCHAIN}/bin/ld
    export RANLIB=${TOOLCHAIN}/bin/llvm-ranlib
    export STRIP=${TOOLCHAIN}/bin/llvm-strip
    
    INSTALL_DIR=${BUILD_DIR}/curl-${CURL_VERSION}/${ANDROID_ABI}
    mkdir -p ${INSTALL_DIR}
    
    # 显式关闭HTTP/3（仅当 ENABLE_HTTP3=1 且依赖存在时才启用）
    HTTP3_FLAGS=""
    if [ "${ENABLE_HTTP3}" = "1" ]; then
        if [ -n "${NGHTTP3_VERSION}" ] && [ -n "${NGTCP2_VERSION}" ] \
           && [ -d "${BUILD_DIR}/nghttp3-${NGHTTP3_VERSION}/${ANDROID_ABI}" ] \
           && [ -d "${BUILD_DIR}/ngtcp2-${NGTCP2_VERSION}/${ANDROID_ABI}" ]; then
            HTTP3_FLAGS="--with-nghttp3=${BUILD_DIR}/nghttp3-${NGHTTP3_VERSION}/${ANDROID_ABI} \
                          --with-ngtcp2=${BUILD_DIR}/ngtcp2-${NGTCP2_VERSION}/${ANDROID_ABI} \
                          --enable-alt-svc"
            echo "[DEBUG] 启用HTTP/3，HTTP3_FLAGS: ${HTTP3_FLAGS}"
        else
            echo "[DEBUG] ENABLE_HTTP3=1 但未找到nghttp3/ngtcp2依赖，跳过HTTP/3"
        fi
    else
        echo "[DEBUG] 已显式关闭HTTP/3 (ENABLE_HTTP3=${ENABLE_HTTP3})"
    fi

    # 检测并启用 HTTP/2（若找到 nghttp2 安装路径则启用）
    HTTP2_FLAGS=""
    if [ -n "${NGHTTP2_VERSION}" ] && [ -d "${BUILD_DIR}/nghttp2-${NGHTTP2_VERSION}/${ANDROID_ABI}" ]; then
        HTTP2_FLAGS="--with-nghttp2=${BUILD_DIR}/nghttp2-${NGHTTP2_VERSION}/${ANDROID_ABI}"
        echo "[DEBUG] 启用HTTP/2，HTTP2_FLAGS: ${HTTP2_FLAGS}"
    else
        echo "[DEBUG] 未启用HTTP/2（未设置 NGHTTP2_VERSION 或未找到 nghttp2 安装目录）"
    fi

    echo "[DEBUG] Curl 安装目录: ${INSTALL_DIR}"
    echo "[DEBUG] 将使用的编译器: CC=${CC}, CXX=${CXX}, AR=${AR}, RANLIB=${RANLIB}"
    echo "[DEBUG] Curl 配置选项即将执行"
    ./configure --host=${TARGET_HOST} \
                --target=${TARGET_HOST} \
                --prefix=${INSTALL_DIR} \
                --with-openssl=${BUILD_DIR}/openssl-${OPENSSL_VERSION}/${ANDROID_ABI} \
                --with-pic --enable-ipv6 \
                ${HTTP3_FLAGS} \
                ${HTTP2_FLAGS} \
                --disable-ldap --disable-ldaps --disable-manual --disable-libcurl-option \
                --disable-rtsp --disable-dict --disable-telnet --disable-tftp --disable-pop3 \
                --disable-imap --disable-smtp --disable-gopher --disable-smb \
                --disable-mqtt --disable-manual --disable-unix-sockets \
                --disable-verbose --disable-versioned-symbols \
                --disable-ftp --disable-file --disable-netrc \
                --without-brotli --without-zlib --without-zstd --without-libidn2 \
                --without-librtmp --without-libpsl \
                --enable-shared --disable-static

    make -j$(($(getconf _NPROCESSORS_ONLN) + 1))
    make install
    #clean up
    rm -rf ${INSTALL_DIR}/bin
    rm -rf ${INSTALL_DIR}/share
    rm -rf ${INSTALL_DIR}/lib/pkgconfig

    # 构建结果校验与提示
    if [ -f "${INSTALL_DIR}/lib/libcurl.so" ] || [ -f "${INSTALL_DIR}/lib/libcurl.a" ]; then
        echo "[INFO] curl 已安装到: ${INSTALL_DIR}"
        ls -l "${INSTALL_DIR}/lib" || true
    else
        echo "[WARN] 未找到libcurl库，请检查配置与依赖（可能缺少nghttp2/HTTP3或OpenSSL路径不正确）。"
    fi
}


if [ "$ANDROID_ABI" == "armeabi-v7a" ]
then
    cd ${OPENSSL_SRC_DIR}
    build_openssl armv7a-linux-androideabi android-arm

    # 若开启HTTP/3且提供依赖，则构建之
    if [ "${ENABLE_HTTP3}" = "1" ]; then
        if [ -n "${NGHTTP3_VERSION}" ] && [ -d "${NGHTTP3_SRC_DIR}" ]; then
            cd ${NGHTTP3_SRC_DIR}
            build_nghttp3 armv7a-linux-androideabi
        fi
        if [ -n "${NGTCP2_VERSION}" ] && [ -d "${NGTCP2_SRC_DIR}" ]; then
            cd ${NGTCP2_SRC_DIR}
            build_ngtcp2 armv7a-linux-androideabi
        fi
    fi

    # 若设置了 NGHTTP2_VERSION 且提供源码，则构建 nghttp2 以启用 HTTP/2
    if [ -n "${NGHTTP2_VERSION}" ] && [ -d "${NGHTTP2_SRC_DIR}" ]; then
        cd ${NGHTTP2_SRC_DIR}
        build_nghttp2 armv7a-linux-androideabi
    else
        echo "[DEBUG] 跳过 nghttp2 构建（未设置 NGHTTP2_VERSION 或未找到源码目录）"
    fi

    cd ${CURL_SRC_DIR}
    build_curl armv7a-linux-androideabi
    
elif [ "$ANDROID_ABI" == "arm64-v8a" ]
then
    cd ${OPENSSL_SRC_DIR}
    build_openssl aarch64-linux-android android-arm64

    # 若开启HTTP/3且提供依赖，则构建之
    if [ "${ENABLE_HTTP3}" = "1" ]; then
        if [ -n "${NGHTTP3_VERSION}" ] && [ -d "${NGHTTP3_SRC_DIR}" ]; then
            cd ${NGHTTP3_SRC_DIR}
            build_nghttp3 aarch64-linux-android
        fi
        if [ -n "${NGTCP2_VERSION}" ] && [ -d "${NGTCP2_SRC_DIR}" ]; then
            cd ${NGTCP2_SRC_DIR}
            build_ngtcp2 aarch64-linux-android
        fi
    fi

    # 若设置了 NGHTTP2_VERSION 且提供源码，则构建 nghttp2 以启用 HTTP/2
    if [ -n "${NGHTTP2_VERSION}" ] && [ -d "${NGHTTP2_SRC_DIR}" ]; then
        cd ${NGHTTP2_SRC_DIR}
        build_nghttp2 aarch64-linux-android
    else
        echo "[DEBUG] 跳过 nghttp2 构建（未设置 NGHTTP2_VERSION 或未找到源码目录）"
    fi

    cd ${CURL_SRC_DIR}
    build_curl aarch64-linux-android
else
    echo "Unsupported target ABI: $ANDROID_ABI"
    exit 1
fi
