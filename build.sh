#!/bin/sh
#
# Build armv8 Ubuntu base image for docker (on x86 as well as armhf machines)
# - needs qemu-user-static installed (w/qemu-arm64)
# - image will be tagged with the chosen version
#
# Synopsis: build.sh [VERSION] [IMAGE NAME]
#
# Defaults: build.sh 14.04 <YOUR-DOCKER-USER>/arm64-ubuntu

# Fail on error
set -e

VERSION=${1:-14.04}
ARCHIVE_NAME=ubuntu-core-$VERSION-core-arm64.tar
BASE_IMAGE_URL=http://cdimage.ubuntu.com/ubuntu-core/releases/$VERSION/release/${ARCHIVE_NAME}.gz

# Use given image name or the default one (with your username)
if [ -n "$2" ]; then
  IMAGE_NAME=$2:$VERSION
else
  DOCKER_USER=$(sudo docker info | grep Username | awk '{print $2;}')
  IMAGE_NAME=$DOCKER_USER/armhf-ubuntu:$VERSION
fi

echo Building $IMAGE_NAME

# Unzip Ubuntu core image
curl $BASE_IMAGE_URL | gunzip -c >/tmp/${ARCHIVE_NAME}

# Keep us lean by effectively running "apt-get clean" after every install
aptGetClean='"rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true";'
aptConfPath=etc/apt/apt.conf.d
mkdir -p /tmp/$aptConfPath
echo >&2 "+ cat > '/tmp/$aptConfPath/docker-clean'"
cat > "/tmp/$aptConfPath/docker-clean" <<-EOF
  DPkg::Post-Invoke { ${aptGetClean} };
  APT::Update::Post-Invoke { ${aptGetClean} };

  Dir::Cache::pkgcache "";
  Dir::Cache::srcpkgcache "";
EOF

# Remove apt-cache translations for fast "apt-get update"
echo >&2 "+ cat > '/tmp/$aptConfPath/docker-no-languages'"
echo 'Acquire::Languages "none";' > "/tmp/$aptConfPath/docker-no-languages"

# Add files to base image and import it
cd /tmp && tar rf /tmp/${ARCHIVE_NAME} -P /usr/bin/qemu-arm64 $aptConfPath
cat /tmp/${ARCHIVE_NAME} | sudo docker import - $IMAGE_NAME
rm /tmp/${ARCHIVE_NAME} /tmp/$aptConfPath -fR

# EVH: TODO: removing the update process which requires binfmt_misc, etc. Lets just grab base images for now.
# Use qemu unless running on armv7l architecture
#if [ $(uname -m) != "armv7l" -a ! -f /proc/sys/fs/binfmt_misc/arm ]; then
#  sudo sh -c 'echo ":arm:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-arm-static:" >/proc/sys/fs/binfmt_misc/register'
#fi

# Update packages
#UPDATE_SCRIPT="dpkg-divert --local --rename --add /sbin/initctl && \
#               ln -s /bin/true /sbin/initctl && \
#               export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get -y upgrade"
#CID=`sudo docker run -d $IMAGE_NAME sh -c "$UPDATE_SCRIPT"`
#sudo docker attach $CID
#sudo docker commit $CID $IMAGE_NAME
#sudo docker rm $CID

echo "Successfully built image $IMAGE_NAME."
