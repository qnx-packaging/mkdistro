#!/usr/bin/env bash

# RUN ME IN FAKEROOT!
# Enable one OpenRC service in the default runlevel
# TODO support more runlevels, only default for now

set -Eeuo pipefail

PROG="openrc-setup"
# shellcheck source=steps/prelude.sh
source "$(dirname -- "$(realpath -e -- "${BASH_SOURCE[0]}")")/prelude.sh"

usage() {
  echo "openrc-enable-service.sh [APKROOT] [SERVICE]
    [APKROOT] location to write files to
    [SERVICE] service to enable"
}

if (($# != 2)); then
  usage >&2
  die "expected an APKROOT and a SERVICE, got $#: $*"
fi

apk_root="$1"
service="$2"

[[ -d "${apk_root}" ]] || die "bad out dir at ${apk_root}"
[[ -x "${apk_root}/etc/init.d/${service}" ]] ||
  die "service ${service} is not installed: no executable /etc/init.d/${service} in ${apk_root}"

mkdir -p -- "${apk_root}/etc/runlevels/default" \
  || die "unable to create ${apk_root}/etc/runlevels/default"

msg "Enabling service: ${service}"
ln -sfn "/etc/init.d/${service}" "${apk_root}/etc/runlevels/default/" \
  || die "unable to link /etc/init.d/${service} into ${apk_root}/etc/runlevels/default"
