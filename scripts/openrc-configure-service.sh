#!/bin/bash -e

# RUN ME IN FAKEROOT!
# Activate the designated list of OpenRC services
# TODO support more runlevels, only default for now
function usage() {
  echo "openrc-enable-service [APKROOT] [SERVICE] [CONFD]

    [APKROOT] location to write files to
    [SERVICE] service to configure
    [CONFD] path to confd file
"
}

function msg() {
  echo "[openrc-setup] $*"
}

apk_root=$1
service=$2
confd_file=$3

if ! [[ -d ${apk_root} ]]; then
  msg "bad out dir at ${apk_root}"
  exit 1
fi

if ! [[ -e ${confd_file} ]]; then
  msg "bad confd file at ${confd_file}"
  exit 1
fi

cd "${apk_root}"
msg "Configuring service: ${service}"

if [[ -x /etc/init.d/${service} ]]; then
  msg "Attempting to configure ${service} but not found in /etc/init.d"
  exit 1
fi

cat "${confd_file}" | awk NF >"${apk_root}"/etc/conf.d/"${service}"
