#!/bin/bash -e

# change our dir to where our script is, and then print pwd
WORK_PATH=$(cd "$(dirname "$0")";pwd)
MIN_API=21
HOST_TAG=linux-x86_64
BUILD_DIR=${WORK_PATH}/build
OPENSSL_SRC_DIR=${WORK_PATH}/openssl-${OPENSSL_VERSION}
CURL_SRC_DIR=${WORK_PATH}/curl-${CURL_VERSION}

# 设置HTTP/3相关源码目录
NGHTTP3_SRC_DIR=${WORK_PATH}/nghttp3-${NGHTTP3_VERSION}
NGTCP2_SRC_DIR=${WORK_PATH}/ngtcp2-${NGTCP2_VERSION}

export ANDROID_NDK_ROOT=${WORK_PATH}/android-ndk-${ANDROID_NDK_VERSION}
TOOLCHAIN=${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/${HOST_TAG}
PATH=${TOOLCHAIN}/bin:$PATH


function build_openssl() {
    TARGET_HOST=$1
    OPENSSL_ARCH=$2
    INSTALL_DIR=${BUILD_DIR}/openssl-${OPENSSL_VERSION}/${ANDROID_ABI}
    mkdir -p ${INSTALL_DIR}
    
    # 修改OpenSSL编译选项，保留HTTP/3所需的加密算法
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
    
    # 添加HTTP/3支持的配置选项
    ./configure --host=${TARGET_HOST} \
                --target=${TARGET_HOST} \
                --prefix=${INSTALL_DIR} \
                --with-openssl=${BUILD_DIR}/openssl-${OPENSSL_VERSION}/${ANDROID_ABI} \
                --with-nghttp3=${BUILD_DIR}/nghttp3-${NGHTTP3_VERSION}/${ANDROID_ABI} \
                --with-ngtcp2=${BUILD_DIR}/ngtcp2-${NGTCP2_VERSION}/${ANDROID_ABI} \
                --with-pic --enable-ipv6 --enable-http2 \
                --enable-alt-svc \
                --disable-ldap --disable-ldaps --disable-manual --disable-libcurl-option \
                --disable-rtsp --disable-dict --disable-telnet --disable-tftp --disable-pop3 \
                --disable-imap --disable-smtp --disable-gopher --disable-smb \
                --disable-mqtt --disable-manual --disable-unix-sockets \
                --disable-verbose --disable-versioned-symbols \
                --disable-ftp --disable-file --disable-netrc --disable-fsck-zero-pct \
                --without-brotli --without-zlib --without-zstd --without-libidn2 \
                --without-librtmp --without-libpsl \
                --enable-shared --disable-static \
                --build=x86_64-linux-gnu \
                --with-cross-build

    make -j$(($(getconf _NPROCESSORS_ONLN) + 1))
    make install
    #clean up
    rm -rf ${INSTALL_DIR}/bin
    rm -rf ${INSTALL_DIR}/share
    rm -rf ${INSTALL_DIR}/lib/pkgconfig
}


if [ "$ANDROID_ABI" == "armeabi-v7a" ]
then
    cd ${OPENSSL_SRC_DIR}
    build_openssl armv7a-linux-androideabi android-arm
    
    cd ${NGHTTP3_SRC_DIR}
    build_nghttp3 armv7a-linux-androideabi
    
    cd ${NGTCP2_SRC_DIR}
    build_ngtcp2 armv7a-linux-androideabi
    
    cd ${CURL_SRC_DIR}
    build_curl armv7a-linux-androideabi
    
elif [ "$ANDROID_ABI" == "arm64-v8a" ]
then
    cd ${OPENSSL_SRC_DIR}
    build_openssl aarch64-linux-android android-arm64
    
    cd ${NGHTTP3_SRC_DIR}
    build_nghttp3 aarch64-linux-android
    
    cd ${NGTCP2_SRC_DIR}
    build_ngtcp2 aarch64-linux-android
    
    cd ${CURL_SRC_DIR}
    build_curl aarch64-linux-android
else
    echo "Unsupported target ABI: $ANDROID_ABI"
    exit 1
fi
