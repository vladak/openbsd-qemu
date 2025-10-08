# OpenBSD on Soekris

I have a Soekris 4511 box sitting around that is used for a particular purpose.
It is currently running an old version of OpenBSD and I'd like to upgrade
to a more recent one.

The Soekris has limited amount of RAM and other constraints so it is necessary
to compile a custom kernel for it. This is not doable on the Soekris itself,
because the CPU is too slow and the Compact Flash is slow and small (and would
probably wear out rather quickly with all this I/O).

The plan is to install OpenBSD via network (PXE) and compile the kernel in Qemu.

## OpenBSD install on Soekris over the network

XXX

## Compiling the kernel

## Unattended OpenBSD installation into Qemu

The motivation for this is to create Qemu based OpenBSD machine that can be used
for compiling custom OpenBSD kernel and also some experimentation with the
system.

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

Although the `LD_PRELOAD` trick used by
https://github.com/0xJJ/autoinstall-openbsd-on-qemu/tree/main is cool, I did not
want to have a dependency on a compiler, so the HTTP server to serve the install
bits has to be run as
```
sudo python3 -m http.server 80
```

After the initial install in the VM is successfully done, start the VM as
follows:
```
XXX
```

## OpenBSD setup

XXX
