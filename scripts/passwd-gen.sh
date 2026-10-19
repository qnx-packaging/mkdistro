#!/bin/bash -e

root_path=$1

shopt -s extglob

# RUN ME IN FAKEROOT!
# Install a bunch of apk packages, then generate a list of files to be used by mkqnximage
function usage() {
  echo "passwd-gen.sh [ROOT]

    [ROOT]        directory to output generated passwd/shadow/group files
    [PASSWD_FILE] path to passwd file as a base
    [GROUP_FILE]  path to group file as a base
"
}

root_path="$1"
passwd_file="$2"
groups_file="$3"

function msg() {
  echo "[passwd-gen] $*"
}

msg_error() {
  printf '[passwd-gen] ERROR: %s\n' "${1}"
  if ((${2} > 0)); then
    exit "${2}"
  fi
}

if ! [[ -e "${passwd_file}" ]]; then
  msg "passwd_file undefined!"
fi

if ! [[ -e "${groups_file}" ]]; then
  msg "groups_file undefined!"
  exit 1
fi

if ! [[ -d ${root_path} ]]; then
  msg "bad out dir"
  exit 1
fi

if ! command -v mkshadow >/dev/null 2>&1; then
  msg "mkshadow command not found. SDP not activated?"
  exit 1
fi

users="$(cat "${passwd_file}")"
groups="$(cat "${groups_file}")"

# Pick all the valid lines
passwd_tmp="$(mktemp)"
while read -r line; do
  if [[ -z ${line} ]] || [[ ${line} =~ "^#" ]]; then
    continue
  elif [[ -z $(echo "${line}" | cut -d':' -f7) ]]; then
    msg "Ignoring malformed line: ${line}"
    continue
  fi
  echo "${line}" >>"${passwd_tmp}"
  # Create home folder
  newname=$(echo "${line}" | cut -d':' -f1)
  newuid=$(echo "${line}" | cut -d':' -f3)
  newgid=$(echo "${line}" | cut -d':' -f4)
  newhome=$(echo "${line}" | cut -d':' -f6)
  if ! [[ -z ${newuid} || -z ${newgid} || -z ${newhome} ]] && [[ ${newuid} -ge 1000 ]]; then
    [[ "${newhome}" == '/' ]] && continue

    # Prevent path traversal
    if [[ ! "$(realpath -qm -- "${root_path}${newhome}")" == "${root_path}"* ]]; then
      msg_error "Unable to setup ${newname}, home dir \"${root_path}${newhome}\" outside of ${root_path}" 1
    fi

    msg "Creating home folder for ${newname} (${newuid}:${newgid})"

    mkdir -p "$(dirname "${root_path}"/"${newhome}")"
    cp -vr "${root_path}"/etc/skel "${root_path}"/"${newhome}"
    chmod 750 "${root_path}"/"${newhome}"
    chown -R "${newuid}":"${newgid}" "${root_path}"/"${newhome}"
  fi
done <<<"${users}"

# Special case: always create home folder for root
mkdir -p "${root_path}"/var/home/root
chmod 750 "${root_path}"/var/home/root

# Generate shadow
cat "${passwd_tmp}" | sed '/^[[:space:]]*$/d' | awk -F: '
    { system("mkshadow -u "$1" -p "$2)  }
' >>"${root_path}"/etc/shadow

# Pick all the valid lines for groups as well
while read line; do
  if [[ -z ${line} ]] || [[ ${line} =~ "^#" ]]; then
    continue
  elif [[ -z $(echo "${line}" | cut -d':' -f3) ]]; then
    msg "Ignoring malformed group line: ${line}"
    continue
  fi
  echo "${line}" >>"${root_path}"/etc/group
done <<<"${groups}"

# Write it down, write it down!
cat "${passwd_tmp}" | awk -F ':' -v OFS=':' '
    { if ($2 != "") $2="x"; print }
' >>"${root_path}"/etc/passwd
rm "${passwd_tmp}"

msg "DONE"
