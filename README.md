# OpenBSD on Soekris

I have a Soekris 4511 box sitting around that is used for a particular purpose.
It is currently running an old version of OpenBSD and I'd like to upgrade
to a more recent one.

The Soekris has limited amount of RAM and other constraints so it is necessary
to compile a custom kernel for it. This is not doable on the Soekris itself,
because the CPU is too slow and the Compact Flash is slow and small (and would
probably wear out rather quickly with all this I/O).

The plan is to compile the kernel in Qemu and then install OpenBSD via network (PXE).

## Compiling the kernel

## Unattended OpenBSD installation into Qemu

The motivation for this is to create Qemu based OpenBSD machine that can be used
for compiling custom OpenBSD kernel and also some experimentation with the
system.

Although OpenBSD system can cross-compile kernels, I chose to run OpenBSD i386
in case a utility/program needs to be compiled as well.

To do that, I modified the
[`autoinstall-openbsd-on-qemu.sh`](https://git.skreutz.com/autoinstall-openbsd-on-qemu.git/)
script by Stefan Kreutz, who described his approach in a
[blog post](https://www.skreutz.com/posts/autoinstall-openbsd-on-qemu/)
similarly to
what https://github.com/0xJJ/autoinstall-openbsd-on-qemu/tree/main has done.

Some notable changes:
  - change of the default SSH key type to ed25519
  - configurable OpenBSD version
  - reduce the install sets (exclude the X.org sets)
  - use HTTPS instead of rsync
  - use bash instead of `/bin/sh`
  - store `install.conf`, `disklabel`, `boot.conf` and `install.site` files separately
  - create `random.seed` for the install
  - used HTTPs instead of rsync, still keeping distinct location for the public
    key used by `signify` to verify the install sets

The script assumes a Linux distribution with the necessary tools such as `curl`,
`ssh`, `openbsd-signify`, the Qemu itself, etc.

Also assumes the user can run Qemu direcly, i.e.
```
sudo usermod -aG libvirt,kvm $USER
```

Although the `LD_PRELOAD` trick used by
https://github.com/0xJJ/autoinstall-openbsd-on-qemu/tree/main is cool, I did not
want to have a dependency on a compiler, so the HTTP server to serve the install
bits has to be run as
```
cd mirror
sudo python3 -m http.server 80
```

After the initial install in the VM is successfully done, start the VM as follows:
```
./openbsd-qemu.sh run
```
Then ssh into the VM via:
```
./openbsd-qemu.sh ssh
```

### Qemu gotchas

The `user` networking type does not allow for ICMP to be used.

### kernel compilation

Technically the kernel can be cross-compiled so it is not necessary to build inside OpenBSD/i386.

Follow https://www.openbsd.org/faq/faq5.html:
```
doas user mod -G wsrc puffy
doas user mod -G wobj puffy
exit
# relogin via SSH so that group changes take effect.
cd /usr
cvs -qd anoncvs@anoncvs.eu.openbsd.org:/cvs checkout -rOPENBSD_7_7 -P src/sys
cd /sys/arch/i386/conf
cp GENERIC CUSTOM
# make your changes
config CUSTOM
cd ../compile/CUSTOM
time make
```
It takes some 339 minutes (almost 6 hours) to compile the `GENERIC` kernel in the i386 guest.
Also, it panicked once in page table management routines on an assert. On amd64 the i386 `GENERIC` kernel
compilation takes some 6 minutes.

The size of `GENERIC` `bsd` is some 15 MB.

## OpenBSD install on Soekris over the network

### Prerequisites

```
cd /tftproot
mkdir etc
dd if=/dev/random of=/tftproot/etc/random.seed bs=512 count=1 status=none
cat >/tftproot/etc/boot.conf << EOF                                                                                                                        
set tty com0
stty com0 115200
boot bsd.rd
EOF
curl -o /tftproot/bsd.rd https://cdn.openbsd.org/pub/OpenBSD/7.7/i386/bsd.rd
curl -o /tftproot/pxeboot https://cdn.openbsd.org/pub/OpenBSD/7.7/i386/pxeboot
```

The `dhcpd.conf` needs to have the `next-server` and `filename "pxeboot";` directives
in the respective section.

There ought to be PF rules to allow for TFTP and HTTP[S] traffic.

## OpenBSD setup

XXX

# Links

- Qemu on Ubuntu: https://idroot.us/install-qemu-ubuntu-24-04/
- Soekris boot: http://jurjenbokma.com/ApprenticesNotes/ar01s03.xhtml

