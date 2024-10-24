#!/bin/bash

set -eax

OSS_CAD_RELEASE_DATE=2024-10-02
OSS_CAD_RELEASE_VERSION=20241002
LINUX_ARCH=

case $(uname -i) in
  "aarch64")
    LINUX_ARCH="arm64";;
  "x86_64")
    LINUX_ARCH="x64";;
  default)
    LINUX_ARCH="x64";;
esac

# Don't install oss-cad-suite over old install to avoid future mysteries.
if [ -d "oss-cad-suite" ] ; then
  echo "'oss-cad-suite' directory already exists, you must remove it before reinstalling. Try: rm -rf oss-cad-suite"
  exit -1
fi

# Check if .gitignore knows about oss-cad-suite or else add it.
if [[ $(cat .gitignore) =~ "oss-cad-suite" ]]; then
echo "oss-cad-suite already in .gitignore"
else
cat >> .gitignore << EOF
oss-cad-suite
EOF
fi

# Download and extract oss-cad-suite
RELEASE_FILENAME="oss-cad-suite-linux-$LINUX_ARCH-$OSS_CAD_RELEASE_VERSION.tgz"

curl -L -O "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/$OSS_CAD_RELEASE_DATE/$RELEASE_FILENAME"
tar zxvf $RELEASE_FILENAME

# Set the environment variables. TODO: make this permanent to the devcontainer.
if [ -f oss-cad-suite/environment ] ; then
  source oss-cad-suite/environment
fi
