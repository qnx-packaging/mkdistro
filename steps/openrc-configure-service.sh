#!/usr/bin/env bash

# RUN ME IN FAKEROOT!
# Write the conf.d file for an already enabled OpenRC service
# TODO support more runlevels, only default for now

set -Eeuo pipefail

function usage() {
  echo "openrc-configure-service [APKROOT] [SERVICE] [CONFD]

    [APKROOT] location to write files to
    [SERVICE] service to configure
    [CONFD] path to confd file
"
}

function msg() {
  echo "[openrc-setup] $*"
}

function msg_error() {
  printf '[openrc-setup] ERROR: %s\n' "${1}" >&2
  exit 1
}

if (($# != 3)); then
  usage >&2
  msg_error "expected an APKROOT, a SERVICE and a CONFD file, got $#: $*"
fi

apk_root=$1
service=$2
confd_file=$3

if ! [[ -d ${apk_root} ]]; then
  msg_error "bad out dir at ${apk_root}"
fi

if ! [[ -e ${confd_file} ]]; then
  msg_error "bad confd file at ${confd_file}"
fi

if ! [[ -x "${apk_root}/etc/init.d/${service}" ]]; then
  msg_error "service ${service} is not installed: no executable /etc/init.d/${service} in ${apk_root}"
fi

if ! [[ -d "${apk_root}/etc/runlevels/default" ]]; then
  msg_error "service ${service} is not enabled: ${apk_root}/etc/runlevels/default does not exist"
fi

msg "Configuring service: ${service}"

if ! mkdir -p "${apk_root}/etc/conf.d"; then
  msg_error "unable to create ${apk_root}/etc/conf.d"
fi

if ! awk NF "${confd_file}" >"${apk_root}/etc/conf.d/${service}"; then
  msg_error "unable to write ${apk_root}/etc/conf.d/${service}"
fi
