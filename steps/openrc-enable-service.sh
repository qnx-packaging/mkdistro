#!/usr/bin/env bash

# RUN ME IN FAKEROOT!
# Activate the designated list of OpenRC services
# TODO support more runlevels, only default for now

set -Eeuo pipefail

function usage() {
  echo "openrc-enable-service [APKROOT] [SERVICE]

    [APKROOT] location to write files to
    [SERVICE] service to enable
"
}

function msg() {
  echo "[openrc-setup] $*"
}

function msg_error() {
  printf '[openrc-setup] ERROR: %s\n' "${1}" >&2
  exit 1
}

if (($# != 2)); then
  usage >&2
  msg_error "expected an APKROOT and a SERVICE, got $#: $*"
fi

apk_root=$1
service=$2

if ! [[ -d ${apk_root} ]]; then
  msg_error "bad out dir at ${apk_root}"
fi

if ! [[ -x "${apk_root}/etc/init.d/${service}" ]]; then
  msg_error "service ${service} is not installed: no executable /etc/init.d/${service} in ${apk_root}"
fi

# First create the default runlevel folder
if ! mkdir -p "${apk_root}/etc/runlevels/default"; then
  msg_error "unable to create ${apk_root}/etc/runlevels/default"
fi

msg "Enabling service: ${service}"
if ! ln -sfn "/etc/init.d/${service}" "${apk_root}/etc/runlevels/default/"; then
  msg_error "unable to link /etc/init.d/${service} into ${apk_root}/etc/runlevels/default"
fi
