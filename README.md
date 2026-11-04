# mkdistro

Builds a packaged managed QNX system based on apk-tools

## Requirements

From your Linux distribution: `fakeroot`, `apk`, `curl`, `sed`, `awk`, `find`,
`numfmt`, `mktemp`, `realpath`, `getopt`, and `qemu-img` (only for `qcow2`
output).

From the QNX SDK: `diskimage`, `mkfatfsimg`, `mkqnx6fsimg`, `mkshadow`. Source
`qnxsdp-env.sh` before running mkdistro.

## Usage

```
mkdistro [OPTIONS] <preset>

  -h, --help       Show help.
  -o, --output DIR Output directory, relative to the current directory and
                   created if missing. Default: ./out
  --keep-tmp       Keep the temp build directory on success.
```

A successful build writes `<name>_<YYYYMMDD>.<ext>` to the output directory,
where `<name>` is the preset directory name, and `<ext>` is `img` or `qcow2`.
Alongside it goes `<name>_<YYYYMMDD>.lock`, the apk lock file recording the
exact package versions installed. Failed builds keep the temp directory and
print where it is.

## Presets

A preset is a directory that describes one image: which packages go in, how big
the disk is, who can log in, what starts at boot. Pass it as the only positional
argument; the directory name becomes the image name. Everything is set by
variables in the preset's `mkdistro.conf`.

```
preset/
  mkdistro.conf     variables, described below
  mkdyifs.conf      arguments for mkdyifs, which builds /ifs
  overlay/          files copied into the root filesystem
```

## License

Apache License 2.0. See `LICENSE`.
