# mkdistro

Builds a package-managed QNX 8.0 system based on `apk-tools`

## Requirements

From your Linux distribution: `fakeroot`, `curl`, and `qemu-img` (only for `qcow2` output).

### Debian / Ubuntu
  `sudo apt install fakeroot curl qemu-utils`
### Alpine
  `doas apk add fakeroot curl qemu-img`
### Arch
  `sudo pacman -S fakeroot qemu-img`

From the QNX SDP 8.0.x: `diskimage`, `mkfatfsimg`, `mkqnx6fsimg`, `mkshadow`. Source
`qnxsdp-env.sh` before running mkdistro.

You need to have built [qsc-apk](https://github.com/qnx-ports/qsc-apk) Follow https://qnx.github.io/codelabs/apk-based-cross-compile steps 1-4

## Usage

```
mkdistro [OPTIONS] <preset>

  -h, --help       Show help.
  -o, --output DIR Output directory, relative to the current directory and
                   created if missing. Default: ./out
  --keep-tmp       Keep the temp build directory on success.
```

A successful build writes `<name>_<YYYYMMDD>.<ext>` to the output directory,
where `<name>` is the preset directory name.
Alongside it goes `<name>_<YYYYMMDD>.lock`, the apk lock file recording the
exact package versions installed. Failed builds keep the temp directory and
print where it is.

## Presets

A preset is a directory that describes one image: which packages go in, how big
the disk is, who can log in, what starts at boot. [See x86-64 qemu minimal preset](presets/x86_64-qemu/mkdistro.conf)

```
<preset>/
  mkdistro.conf     image configuration
  mkdyifs.conf      arguments for mkdyifs, which builds /ifs
  overlay/          files copied into the root filesystem
```

## License

Apache License 2.0. See `LICENSE`.
