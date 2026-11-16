#!/usr/bin/env bash

# RUN ME IN FAKEROOT!
# Write the conf.d file for an already enabled OpenRC service
# TODO support more runlevels, only default for now

set -Eeuo pipefail

PROG="openrc-setup"
# shellcheck source=steps/prelude.sh
source "$(dirname -- "$(realpath -e -- "${BASH_SOURCE[0]}")")/prelude.sh"

usage() {
  echo "openrc-configure-service.sh [APKROOT] [SERVICE] [CONFD]
    [APKROOT] location to write files to
    [SERVICE] service to configure
    [CONFD] path to confd file"
}

if (($# != 3)); then
  usage >&2
  die "expected an APKROOT, a SERVICE and a CONFD file, got $#: $*"
fi

apk_root="$1"
service="$2"
confd_file="$3"

[[ -d "${apk_root}" ]] || die "bad out dir at ${apk_root}"
[[ -e "${confd_file}" ]] || die "bad confd file at ${confd_file}"
[[ -x "${apk_root}/etc/init.d/${service}" ]] ||
  die "service ${service} is not installed: no executable /etc/init.d/${service} in ${apk_root}"
[[ -d "${apk_root}/etc/runlevels/default" ]] ||
  die "service ${service} is not enabled: ${apk_root}/etc/runlevels/default does not exist"

msg "Configuring service: ${service}"

mkdir -p -- "${apk_root}/etc/conf.d" || die "unable to create ${apk_root}/etc/conf.d"
awk NF "${confd_file}" >"${apk_root}/etc/conf.d/${service}" ||
  die "unable to write ${apk_root}/etc/conf.d/${service}"
