#! /bin/bash

# Auto-install OpenBSD/amd64 $OPENBSD_VER on QEMU.
#
# First published at https://www.skreutz.com/posts/autoinstall-openbsd-on-qemu/
# on 22 July 2020.
#
# Copyright (c) 2020 Stefan Kreutz <mail@skreutz.com>
# Copyright (c) 2025 Vladimir Kotal
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

# HTTPS OpenBSD mirror to fetch the install sets.
HTTPS_MIRROR="${HTTPS_MIRROR-https://cdn.openbsd.org/pub/OpenBSD/}"

# Size of the disk image.
DISK_SIZE="${DISK_SIZE-32G}"

# Number of virtual CPUs.
CPU_COUNT="${CPU_COUNT-4}"

# Size of virtual memory.
MEMORY_SIZE="${MEMORY_SIZE-4G}"

# File name of the public SSH key to authorize.
SSH_KEY="${SSH_KEY-${HOME}/.ssh/id_ed25519.pub}"

OPENBSD_VER=7.7

ARCH=i386 # or amd64

openbsd_ver_short=$( echo $OPENBSD_VER | tr -d . )

# File name of the disk image.
DISK_FILE="${DISK_FILE-disk-${ARCH}-obsd_${openbsd_ver_short}.qcow2}"

if [[ ! -r ${SSH_KEY} ]]; then
	echo "${SSH_KEY} does not exist"
	exit 1
fi
ssh_key_data=$( cat ${SSH_KEY} )
if [[ -z $ssh_key_data ]]; then
	echo "empty ssh key in ${SSH_KEY}"
	exit 1
fi

# Check required commands.
for cmd in curl qemu-img qemu-system-x86_64 rsync signify-openbsd ssh; do
	if ! command -v "${cmd}" >/dev/null; then
		echo "command not found: %s\\n" "${cmd}"
		exit 1
	fi
done

# Cannot run the Qemu commands without sudo unless being part of these groups.
if ! groups | tr ' ' '\n' | grep ^kvm$ >/dev/null; then
	echo "must have the kvm supplementary group"
	exit 1
fi
if ! groups | tr ' ' '\n' | grep ^libvirt$ >/dev/null; then
	echo "must have the kvm supplementary group"
	exit 1
fi

PUBKEY_LOCATION="https://ftp.openbsd.org/pub/OpenBSD/"

# Fetch base public key from trusted location.
# ftp.openbsd.org is used on purpose to differ from the HTTPS_MIRROR.
if [[ $PUBKEY_LOCATION == $HTTPS_MIRROR ]]; then
	echo "pubkey and HTTPs locations should differ"
	exit 1
fi
mkdir -p mirror/pub/OpenBSD/$OPENBSD_VER
if [[ ! -e mirror/pub/OpenBSD/$OPENBSD_VER/openbsd-${openbsd_ver_short}-base.pub ]]; then
	curl \
	    --silent \
	    --output mirror/pub/OpenBSD/$OPENBSD_VER/openbsd-${openbsd_ver_short}-base.pub \
	    "$PUBKEY_LOCATION/$OPENBSD_VER/openbsd-${openbsd_ver_short}-base.pub"
	printf "Fetched base public key from %s\\n" "${PUBKEY_LOCATION}"
fi

# Fetch kernel, PXE bootstrap program, and file sets.
# TODO: check the existence of all necessary files under
if [[ ! -d mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH} ]]; then
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

# Add autoinstall(8) configuration.
cat install.conf | sed \
    -e "s/\${openbsd_ver_short}/${openbsd_ver_short}/" \
    -e "s/\${ssh_key_data}/${ssh_key_data}/" \
    > mirror/install.conf

# Create disklabel(8) configuration.
cp disklabel mirror/disklabel

# Create site-specific file.
[[ -d site ]] || mkdir site
cp install.site site/install.site
chmod +x site/install.site

# Package site-specific file set if not exists or changed.
site_dir_changed="$( find site -exec stat -c %Y {} \; | sort -r | head -n 1 )"
if [[ ! -e "mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH}/site${openbsd_ver_short}.tgz" ]] || [[ $( stat -c %Y "mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH}/site${openbsd_ver_short}.tgz" ) -lt "${site_dir_changed}" ]]; then
	rm -f mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH}/site$openbsd_ver_short.tgz
	( cd site && tar -czf ../mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH}/site${openbsd_ver_short}.tgz . )
	( cd mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH} && ls -l > index.txt )
fi

# Create TFTP directory.
rm -rf tftp
mkdir tftp
ln -s ../mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH}/pxeboot tftp/auto_install
ln -s ../mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH}/bsd.rd tftp/bsd.rd
mkdir tftp/etc
dd if=/dev/random of=tftp/etc/random.seed count=1 bs=512
cp boot.conf tftp/etc/boot.conf
printf "Created example boot(8) configuration at ./tftp/etc/boot.conf\\n"

# Remove existing disk image if configuration changed.
if [[ -e "${DISK_FILE}" ]]; then
	vm_created="$( stat -c %W "${DISK_FILE}" )"
	for f in mirror/install.conf mirror/disklabel mirror/pub/OpenBSD/$OPENBSD_VER/${ARCH}/site$openbsd_ver_short.tgz tftp/etc/boot.conf; do
		if [[ "${vm_created}" -lt "$( stat -c %Y "$f" )" ]]; then
			printf "Re-creating virtual machine due to changed configuration: %s\\n" "$f"
			rm "${DISK_FILE}"
			break
		fi
	done
fi

# Create disk image if not exists.
if [[ ! -e "${DISK_FILE}" ]]; then
	qemu-img create -q -f qcow2 "${DISK_FILE}" "${DISK_SIZE}"
	printf "Created %s copy-on-write disk image at %s\\n" "${DISK_SIZE}" "${DISK_FILE}"
fi

# Wait until ./mirror is served at http://127.0.0.1:80/.
while [[ ! "$( curl --silent --location --write-out '%{http_code}\n' --output /dev/null http://127.0.0.1:80/install.conf )" = 200 ]]; do
	( >&2 printf "Please serve the directory ./mirror at http://127.0.0.1:80/\n" )
	sleep 5
done

# Auto-install OpenBSD.
printf "Starting virtual machine ...\\n"
if [[ $ARCH == "amd64" ]]; then
	qemu_cmd=qemu-system-x86_64
elif [[ $ARCH == "i386" ]]; then
	qemu_cmd=qemu-system-i386
else
	echo "unknown arch"
	exit 1
fi
${qemu_cmd} \
    -enable-kvm \
    -smp "cpus=${CPU_COUNT}" \
    -m "${MEMORY_SIZE}" \
    -drive "file=${DISK_FILE},media=disk,if=virtio" \
    -device virtio-net-pci,netdev=n1 \
    -netdev "user,id=n1,hostname=openbsd-vm,tftp=tftp,bootfile=auto_install,hostfwd=tcp::2222-:22" \
    -nographic
