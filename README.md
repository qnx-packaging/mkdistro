# mkdistro

Builds a QNX disk image from a preset: a small shell file that says which
packages to install, how big to make the disk, and what services to enable.

## Requirements

From your Linux distribution: `fakeroot`, `apk`, `curl`, `sed`, `awk`, `find`,
`numfmt`, `mktemp`, `realpath`, `getopt`, and `qemu-img` (only for `qcow2`
output).

From the QNX SDK: `diskimage`, `mkfatfsimg`, `mkqnx6fsimg`, `mkshadow`. Source
`qnxsdp-env.sh` before running mkdistro.

## Usage

```sh
./mkdistro presets/x86_64-qemu
```

The preset is a directory containing a `preset.sh`, given by path.

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

See `preset`

A preset directory may also contain an `overlay/` directory, whose contents are
copied into the root filesystem.

Only `boot_partition_type="efi"` works. `boot_partition_layout` and
`mkdynifs_preset` are read but not implemented yet.

## Layout

```text
mkdistro     main script
bin/         wrapper used after install
presets/     preset directories
scripts/     helpers called by mkdistro
common/      boot partition layouts
```

## Development

```sh
make lint      # bash -n and shellcheck
make install   # PREFIX=/usr/local, DESTDIR supported
```

`make install` puts the script and its data under `$(PREFIX)/share/mkdistro`
and the `mkdistro` entrypoint in `$(PREFIX)/bin`. Set `MKDISTRO_DATADIR` to a
directory containing `scripts/` and `common/` to run the data tree from
elsewhere; by default it is read from next to the script.

## Exit codes

| Code | Meaning                    |
| ---- | -------------------------- |
| 2    | bad arguments              |
| 3    | bad preset                 |
| 4    | missing dependencies       |
| 5    | build failed               |

## License

Apache License 2.0. See `LICENSE`.
