#!/bin/bash -e

# change our dir to where our script is, and then print pwd
WORK_PATH=$(cd "$(dirname "$0")";pwd)
MIN_API=21
HOST_TAG=linux-x86_64
BUILD_DIR=${WORK_PATH}/build
OPENSSL_SRC_DIR=${WORK_PATH}/openssl-${OPENSSL_VERSION}
CURL_SRC_DIR=${WORK_PATH}/curl-${CURL_VERSION}

export ANDROID_NDK_ROOT=${WORK_PATH}/android-ndk-${ANDROID_NDK_VERSION}
TOOLCHAIN=${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/${HOST_TAG}
PATH=${TOOLCHAIN}/bin:$PATH


function build_openssl() {
    TARGET_HOST=$1
    OPENSSL_ARCH=$2
    INSTALL_DIR=${BUILD_DIR}/openssl-${OPENSSL_VERSION}/${ANDROID_ABI}
    mkdir -p ${INSTALL_DIR}
    
    # 添加更多no-xxx选项和编译优化选项以减小libcrypto.so大小
    ./Configure ${OPENSSL_ARCH} no-tests no-unit-test no-idea no-camellia no-seed no-whirlpool no-md2 no-md4 no-mdc2 no-rc2 no-rc4 no-rc5 no-bf no-cast no-dsa no-ripemd no-scrypt no-srp no-gost no-blake2 no-siphash no-poly1305 no-aria no-sm2 no-sm3 no-sm4 no-cms no-ts no-ocsp no-dgram no-sock no-srtp no-cmac no-ct no-async no-engine no-deprecated no-comp no-ssl3 no-dtls no-nextprotoneg no-psk no-srtp no-ec2m no-weak-ssl-ciphers no-err no-filenames no-ui-console no-stdio no-autoload-config no-autoerrinit no-afalgeng no-apps no-asm no-legacy shared -D__ANDROID_API__=${MIN_API} --prefix=${INSTALL_DIR} -fPIC -ffunction-sections -fdata-sections
    -ffunction-sections -fdata-sections
    make -j$(($(getconf _NPROCESSORS_ONLN) + 1))
    make install_sw
    #clean up
    rm -rf ${OPENSSL_SRC_DIR}
    rm -rf ${INSTALL_DIR}/bin
    rm -rf ${INSTALL_DIR}/share
    rm -rf ${INSTALL_DIR}/ssl
    rm -rf ${INSTALL_DIR}/lib/engines*
    rm -rf ${INSTALL_DIR}/lib/pkgconfig
    # Keep dynamic libraries but remove unnecessary files
    rm -rf ${INSTALL_DIR}/lib/ossl-modules

    
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
    
    ./configure --host=${TARGET_HOST} \
                --target=${TARGET_HOST} \
                --prefix=${INSTALL_DIR} \
                --with-openssl=${BUILD_DIR}/openssl-${OPENSSL_VERSION}/${ANDROID_ABI} \
                --with-pic --enable-ipv6 --enable-http2 \
                --disable-ldap --disable-ldaps --disable-manual --disable-libcurl-option \
                --disable-rtsp --disable-dict --disable-telnet --disable-tftp --disable-pop3 \
                --disable-imap --disable-smtp --disable-gopher --disable-smb \
                --disable-mqtt --disable-manual --disable-unix-sockets \
                --disable-verbose --disable-versioned-symbols \
                --disable-ftp --disable-file --disable-netrc --disable-fsck-zero-pct \
                --without-brotli --without-zlib --without-zstd --without-libidn2 \
                --without-nghttp2 --without-librtmp --without-libpsl \
                --enable-shared --disable-static

    make -j$(($(getconf _NPROCESSORS_ONLN) + 1))
    make install
    #clean up
    rm -rf ${CURL_SRC_DIR}
    rm -rf ${INSTALL_DIR}/bin
    rm -rf ${INSTALL_DIR}/share
    rm -rf ${INSTALL_DIR}/lib/pkgconfig
}




if [ "$ANDROID_ABI" == "armeabi-v7a" ]
then
    cd ${OPENSSL_SRC_DIR}
    build_openssl armv7a-linux-androideabi android-arm
    cd ${CURL_SRC_DIR}
    build_curl armv7a-linux-androideabi
    
elif [ "$ANDROID_ABI" == "arm64-v8a" ]
then
    cd ${OPENSSL_SRC_DIR}
    build_openssl aarch64-linux-android android-arm64
    cd ${CURL_SRC_DIR}
    build_curl aarch64-linux-android
else
    echo "Unsupported target ABI: $ANDROID_ABI"
    exit 1
fi
