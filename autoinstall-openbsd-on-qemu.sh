#! /bin/bash

# Auto-install OpenBSD/amd64 $OPENBSD_VER on QEMU.
#
# First published at https://www.skreutz.com/posts/autoinstall-openbsd-on-qemu/
# on 22 July 2020.
#
# Copyright (c) 2020 Stefan Kreutz <mail@skreutz.com>
#
# Permission to use, copy, modify, and distribute this software for any purpose
# with or without fee is hereby granted, provided that the above copyright
# notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.

set -o errexit
set -o nounset

# TODO Trusted HTTPS OpenBSD mirror to fetch the base public key from.
HTTPS_MIRROR="${HTTPS_MIRROR-https://cdn.openbsd.org/pub/OpenBSD/}"

# File name of the disk image.
DISK_FILE="${DISK_FILE-disk.qcow2}"

# Size of the disk image.
DISK_SIZE="${DISK_SIZE-24G}"

# Number of virtual CPUs.
CPU_COUNT="${CPU_COUNT-4}"

# Size of virtual memory.
MEMORY_SIZE="${MEMORY_SIZE-4G}"

# File name of the public SSH key to authorize.
SSH_KEY="${SSH_KEY-${HOME}/.ssh/id_ed25519.pub}"

OPENBSD_VER=7.7

ARCH=i386 # or amd64

openbsd_ver_short=$( echo $OPENBSD_VER | tr -d . )

# Check required commands.
for cmd in curl qemu-img qemu-system-x86_64 rsync signify-openbsd socat ssh
do
  if ! command -v "${cmd}" >/dev/null
  then
    ( >&2 printf "command not found: %s\\n" "${cmd}" )
    exit 1
  fi
done

# Fetch base public key from trusted HTTPS mirror.
# TODO: use different mirror than CDN
mkdir -p mirror/pub/OpenBSD/$OPENBSD_VER
if [ ! -e mirror/pub/OpenBSD/$OPENBSD_VER/openbsd-${openbsd_ver_short}-base.pub ]
then
  curl \
    --silent \
    --output mirror/pub/OpenBSD/$OPENBSD_VER/openbsd-${openbsd_ver_short}-base.pub \
    "${HTTPS_MIRROR}$OPENBSD_VER/openbsd-${openbsd_ver_short}-base.pub"
  printf "Fetched base public key from %s\\n" "${HTTPS_MIRROR}"
fi

# Fetch kernel, PXE bootstrap program, and file sets.
# TODO: check the existence of all necessary files under
if [ ! -d mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH} ]
then
  mkdir -p tmp mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH}
  printf "Fetching installation files for $ARCH ...\\n"
  # Note: No X.org sets
  for file in BUILDINFO SHA256.sig base${openbsd_ver_short}.tgz bsd bsd.mp bsd.rd comp${openbsd_ver_short}.tgz game${openbsd_ver_short}.tgz man${openbsd_ver_short}.tgz pxeboot; do
    curl --silent -o tmp/$file "${HTTPS_MIRROR}$OPENBSD_VER/${ARCH}/$file"
  done
  ( cd tmp && signify-openbsd -C -q \
      -p ../mirror/pub/OpenBSD/$OPENBSD_VER/openbsd-${openbsd_ver_short}-base.pub \
      -x SHA256.sig \
      -- bsd bsd.* pxeboot *$openbsd_ver_short.tgz )
  # TODO: move only the files listed above
  mv tmp/* mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH}/
  printf "Fetched kernel, PXE bootstrap program, and file sets from %s\\n" "${HTTPS_MIRROR}"
fi

# Create autoinstall(8) configuration if not exists.
if [ ! -e mirror/install.conf ]
then
  cat << EOF > mirror/install.conf
Change the default console to com0 = yes
Which speed should com0 use = 115200
System hostname = openbsd
Password for root = *************
Allow root ssh login = no
Setup a user = puffy
Password for user = *************
Public ssh key for user = $( cat "${SSH_KEY}" )
What timezone are you in = UTC
Location of sets = http
HTTP Server = 10.0.2.2
Unable to connect using https. Use http instead = yes
URL to autopartitioning template for disklabel = http://10.0.2.2/disklabel
Set name(s) = -x* site${openbsd_ver_short}
Checksum test for site${openbsd_ver_short}.tgz failed. Continue anyway = yes
Unverified sets: site${openbsd_ver_short}.tgz. Continue without verification = yes
EOF
  printf "Created example response file for autoinstall(8) at ./mirror/install.conf\\n"
fi

# Create disklabel(8) configuration if not exists.
if [ ! -e mirror/disklabel ]
then
  cat << EOF > mirror/disklabel
/            2G
swap         8G
/tmp         1G
/var         1G
/usr         2G
/usr/local   4G
/usr/src     1M
/usr/obj     1M
/home        4G
EOF
  printf "Created example disklabel(8) template at ./mirror/disklabel.conf\\n"
fi

# Create site-specific file set if not exists.
if [ ! -d site ]
then
  mkdir site
  cat << EOF > site/install.site
#! /bin/ksh

set -o errexit

# Reset OpenBSD mirror server used by pkg_add(1) and other commands.
echo "https://cdn.openbsd.org/pub/OpenBSD" > /etc/installurl

# Permit user group wheel to run any command as root without entering their
# password using doas(1).
echo "permit nopass keepenv :wheel" > /etc/doas.conf

# Patch the base system on the first boot.
#echo "syspatch && shutdown -r now" >> /etc/rc.firsttime
EOF
  chmod +x site/install.site
  printf "Created example site-specific file set at ./site\\n"
fi

# Package site-specific file set if not exists or changed.
site_dir_changed="$( find site -exec stat -c %Y {} \; | sort -r | head -n 1 )"
if [ ! -e mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH}/site$openbsd_ver_short.tgz ] || [ "$( stat -c %Y mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH}/site$openbsd_ver_short.tgz )" -lt "${site_dir_changed}" ]
then
  rm -f mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH}/site$openbsd_ver_short.tgz
  ( cd site && tar -czf ../mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH}/site$openbsd_ver_short.tgz . )
  ( cd mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH} && ls -l > index.txt )
fi

# TODO: always recreate
# Create TFTP directory if not exists.
if [ ! -d tftp ]
then
  mkdir tftp
  ln -s ../mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH}/pxeboot tftp/auto_install
  ln -s ../mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH}/bsd.rd tftp/bsd.rd
  mkdir tftp/etc
  cat << EOF > tftp/etc/boot.conf
stty com0 115200
set tty com0
boot tftp:/bsd.rd
EOF
  printf "Created example boot(8) configuration at ./tftp/etc/boot.conf\\n"
fi

# Remove existing disk image if configuration changed.
if [ -e "${DISK_FILE}" ]
then
  vm_created="$( stat -c %W "${DISK_FILE}" )"
  for f in mirror/install.conf mirror/disklabel mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH}/site$openbsd_ver_short.tgz tftp/etc/boot.conf
  do
    if [ "${vm_created}" -lt "$( stat -c %Y "$f" )" ]
    then
      printf "Re-creating virtual machine due to changed configuration: %s\\n" "$f"
      rm "${DISK_FILE}"
    fi
  done
fi

# Create disk image if not exists.
if [ ! -e "${DISK_FILE}" ]
then
  qemu-img create -q -f qcow2 "${DISK_FILE}" "${DISK_SIZE}"
  printf "Created %s copy-on-write disk image at %s\\n" "${DISK_SIZE}" "${DISK_FILE}"
fi

# Wait until ./mirror is served at http://127.0.0.1:80/.
while [ ! "$( curl --silent --location --write-out '%{http_code}\n' --output /dev/null http://127.0.0.1:80/install.conf )" = 200 ]
do
  ( >&2 printf "Please serve the directory ./mirror at http://127.0.0.1:80/\n" )
  sleep 5
done

# Auto-install OpenBSD.
printf "Starting virtual machine ...\\n"
if [[ $ARCH == "amd64" ]]; then
  qemu_cmd=qemu-system-x86_64
elif [[ $ARCH == "i386" ]]; then
  qemu_cmd=qemu-system-i386
fi
${qemu_cmd} \
  -enable-kvm \
  -smp "cpus=${CPU_COUNT}" \
  -m "${MEMORY_SIZE}" \
  -drive "file=${DISK_FILE},media=disk,if=virtio" \
  -device virtio-net-pci,netdev=n1 \
  -netdev "user,id=n1,hostname=openbsd-vm,tftp=tftp,bootfile=auto_install,hostfwd=tcp::2222-:22" \
  -nographic
