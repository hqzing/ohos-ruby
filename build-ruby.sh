#!/bin/sh
set -e

alpine_repository_url="http://dl-cdn.alpinelinux.org/alpine/v3.22/main/aarch64/"

download_alpine_index() {
    mkdir -p /opt/alpine-index
    cd /opt/alpine-index/
    curl -fsSL -O "${alpine_repository_url}/APKINDEX.tar.gz"
    tar -zxf APKINDEX.tar.gz
    cd - >/dev/null
}

get_apk_url() {
    package_name=$1
    version=$(grep -A 2 "^P:${package_name}$" /opt/alpine-index/APKINDEX | grep '^V:' | sed 's/^V://')
    apk_url="${alpine_repository_url}${package_name}-${version}.apk"
    echo $apk_url
}

# Setup tools
download_alpine_index
curl -L -O $(get_apk_url m4)
curl -L -O $(get_apk_url autoconf)
curl -L -O $(get_apk_url busybox-static)
curl -L -O $(get_apk_url make)
curl -L -O $(get_apk_url grep)
curl -L -O $(get_apk_url pcre2)
for file in *.apk; do
  tar -zxf $file -C /
done
rm /bin/xargs
ln -s /bin/busybox.static /bin/xargs
ln -s /bin/busybox.static /bin/tr
ln -s /bin/busybox.static /bin/expr
ln -s /bin/busybox.static /bin/awk
ln -s /bin/busybox.static /bin/unzip
ln -s /bin/busybox.static /bin/fold

# 准备 ohos-sdk
sdk_ohos_download_url="https://cidownload.openharmony.cn/version/Master_Version/ohos-sdk-public_ohos/20251030_020613/version-Master_Version-ohos-sdk-public_ohos-20251030_020613-ohos-sdk-public_ohos.tar.gz"
curl $sdk_ohos_download_url -o ohos-sdk-public_ohos.tar.gz
mkdir /opt/ohos-sdk
tar -zxf ohos-sdk-public_ohos.tar.gz -C /opt/ohos-sdk
cd /opt/ohos-sdk/ohos/
unzip -q native-*.zip
unzip -q toolchains-*.zip
cd - >/dev/null

# Setup env 
export PATH=$PATH:/opt/ohos-sdk/ohos/native/llvm/bin
export AS=llvm-as
export CC=clang
export CXX=clang++
export LD=ld.lld
export STRIP=llvm-strip
export RANLIB=llvm-ranlib
export OBJDUMP=llvm-objdump
export OBJCOPY=llvm-objcopy
export NM=llvm-nm
export AR=llvm-ar
# export CFLAGS="-fPIC -D__MUSL__=1"
# export CXXFLAGS="-fPIC -D__MUSL__=1"

# 编译 perl。这个 perl 作为开发态工具，不会进入产物中。
curl -L https://github.com/Perl/perl5/archive/refs/tags/v5.42.0.tar.gz -o perl5-5.42.0.tar.gz
tar -zxf perl5-5.42.0.tar.gz
cd perl5-5.42.0
sed -i 's/defined(__ANDROID__)/defined(__ANDROID__) || defined(__OHOS__)/g' perl_langinfo.h
./Configure \
    -des \
    -Dprefix=/ \
    -Dcc=$CC \
    -Dcpp=$CXX \
    -Dar=$AR \
    -Dnm=$NM \
    -Accflags=-D_GNU_SOURCE
make -j$(nproc)
make install
cd ..

curl -L -O https://github.com/openssl/openssl/releases/download/openssl-3.3.4/openssl-3.3.4.tar.gz
tar zxf openssl-3.3.4.tar.gz
cd openssl-3.3.4
sed -i "s/SSL_CERT_FILE/PORTABLE_RUBY_SSL_CERT_FILE/g" include/internal/common.h
./Configure --prefix=/opt/openssl-3.3.4-ohos-arm64 --openssldir=/etc/ssl no-legacy no-module no-shared no-engine linux-aarch64
make -j$(nproc)
make install_dev
cd ..

curl -L -O https://github.com/yaml/libyaml/releases/download/0.2.5/yaml-0.2.5.tar.gz
tar zxf yaml-0.2.5.tar.gz
cd yaml-0.2.5
./configure --prefix=/opt/yaml-0.2.5-ohos-arm64 --disable-dependency-tracking --enable-static --disable-shared --host=aarch64-linux
make -j$(nproc)
make install
cd ..

curl -L -O https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz
tar zxf zlib-1.3.1.tar.gz
cd zlib-1.3.1
./configure --prefix=/opt/zlib-1.3.1-ohos-arm64 --static
make -j$(nproc)
make install
cd ..

curl -L -O https://github.com/libffi/libffi/releases/download/v3.4.5/libffi-3.4.5.tar.gz
tar zxf libffi-3.4.5.tar.gz
cd libffi-3.4.5
./configure --prefix=/opt/libffi-3.4.5-ohos-arm64 --enable-static --disable-shared --disable-docs --host=aarch64-linux
make -j$(nproc)
make install
cd ..

# 编译 ruby
curl -L -O https://cache.ruby-lang.org/pub/ruby/3.4/ruby-3.4.5.tar.gz
tar -zxf ruby-3.4.5.tar.gz
cd ruby-3.4.5
patch -p1 < ../0001-add-target-os.patch
patch -p1 < ../0002-change-variable-name.patch
autoconf
./configure \
  --prefix=/opt/ruby-3.4.5-ohos-arm64 \
  --host=aarch64-linux \
  --enable-load-relative \
  --with-static-linked-ext \
  --disable-install-doc \
  --disable-install-rdoc \
  --disable-install-capi \
  --with-opt-dir=/opt/openssl-3.3.4-ohos-arm64:/opt/yaml-0.2.5-ohos-arm64:/opt/zlib-1.3.1-ohos-arm64:/opt/libffi-3.4.5-ohos-arm64
make -j$(nproc)
make install
cd ..

# Codesign
export PATH=$PATH:/opt/ohos-sdk/ohos/toolchains/lib
binary-sign-tool sign -inFile /opt/ruby-3.4.5-ohos-arm64/bin/ruby -outFile /opt/ruby-3.4.5-ohos-arm64/bin/ruby -selfSign 1
find /opt/ruby-3.4.5-ohos-arm64/lib/ -type f | grep -E '\.so(\.[0-9]+)*$' | xargs -I {} binary-sign-tool sign -inFile {} -outFile {} -selfSign 1

# 履行开源义务，把使用的开源软件的 license 全部聚合起来放到制品中
ruby_txt=$(cat ruby-3.4.5/COPYING; echo)
openssl_txt=$(cat openssl-3.3.4/LICENSE.txt; echo)
yaml_txt=$(cat yaml-0.2.5/License; echo)
zlib_txt=$(cat zlib-1.3.1/LICENSE; echo)
libffi_txt=$(cat libffi-3.4.5/LICENSE; echo)
printf '%s' "$(cat <<EOF
This document describes the licenses of all software distributed with the
bundled application.
==========================================================================

ruby
=========
$ruby_txt

openssl
=========
$openssl_txt

yaml
=========
$yaml_txt

zlib
=========
$zlib_txt

libffi
=========
$libffi_txt
EOF
)" > /opt/ruby-3.4.5-ohos-arm64/licenses.txt

cd /opt
tar -zcf ruby-3.4.5-ohos-arm64.tar.gz ruby-3.4.5-ohos-arm64
