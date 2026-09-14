#!/bin/bash -e

# RUN ME IN FAKEROOT!
# Activate the designated list of OpenRC services
# TODO support more runlevels, only default for now
function usage() {
  echo "openrc-enable-service [APKROOT] [SERVICE]

    [APKROOT] location to write files to
    [SERVICE] service to enable
"
}

function msg() {
  echo "[openrc-setup] $*"
}

apk_root=$1
service=$2

if ! [[ -d ${apk_root} ]]; then
  msg "bad out dir at ${apk_root}"
  exit 1
fi

# First create the default runlevel folder
if ! [[ -d /etc/runlevels/default ]]; then
  mkdir -vp "${apk_root}/etc/runlevels/default"
fi

cd "${apk_root}"
msg "Enabling service: ${service}"

if [[ -x /etc/init.d/${service} ]]; then
  msg "Attempting to enable ${service} but not found in /etc/init.d"
  exit 1
fi

ln -s "/etc/init.d/${service}" "${apk_root}/etc/runlevels/default/"
