#!/usr/bin/env bash

# RUN ME IN FAKEROOT!
# Generate the passwd, shadow and group files for a root filesystem from the
# preset's user and group lists, and create home folders from /etc/skel.
# The preset owns the root account: the passwd list must start with a root
# entry and nothing here creates a root home implicitly.

set -Eeuo pipefail

function usage() {
  echo "passwd-gen.sh [ROOT] [PASSWD_FILE] [GROUP_FILE]

    [ROOT]         directory to output generated passwd/shadow/group files
    [PASSWD_FILE]  path to passwd file as a base; first entry must be root
    [GROUP_FILE]   path to group file as a base
"
}

if (($# != 3)); then
  usage >&2
  echo "[passwd-gen] ERROR: expected ROOT, PASSWD_FILE and GROUP_FILE, got $#: $*" >&2
  exit 1
fi

root_path="$1"
passwd_file="$2"
groups_file="$3"

shadow_user=""
shadow_pw=""

line=""
home_dir=""
etc_file=""
incoming=""
id_field=""
pw_entry=""

function prune_replaced() {
  local target="$1"
  local incoming="$2"
  local id_field="$3"
  local tmp

  touch -- "${target}"
  tmp="$(mktemp)"
  if ! awk -F: -v excl="${incoming}" -v idf="${id_field}" '
    BEGIN {
      while ((getline line < excl) > 0) {
        split(line, f, ":")
        if (f[1] == "") { continue }
        names[f[1]] = 1
        if (f[idf] != "") { ids[f[idf]] = 1 }
      }
    }
    {
      drop = ($1 in names)
      if (idf != 0 && ($idf in ids)) { drop = 1 }
      if (!drop) { print }
    }
  ' "${target}" >"${tmp}"; then
    rm -f -- "${tmp}"
    msg_error "Unable to rewrite ${target}"
  fi

  if ! cat -- "${tmp}" >"${target}"; then
    rm -f -- "${tmp}"
    msg_error "Unable to update ${target}"
  fi
  rm -f -- "${tmp}"
}

function msg() {
  echo "[passwd-gen] $*"
}

msg_error() {
  printf '[passwd-gen] ERROR: %s\n' "${1}" >&2
  exit 1
}

if ! [[ -e "${passwd_file}" ]]; then
  msg_error "passwd_file undefined!"
fi

if ! [[ -e "${groups_file}" ]]; then
  msg_error "groups_file undefined!"
fi

if ! [[ -d "${root_path}" ]]; then
  msg_error "bad out dir ${root_path}"
fi

if ! command -v mkshadow >/dev/null 2>&1; then
  msg_error "mkshadow command not found. SDP not activated?"
fi

users="$(cat "${passwd_file}")"
groups="$(cat "${groups_file}")"

first_entry="$(awk 'NF && $0 !~ /^#/ { print; exit }' <<<"${users}")"
if [[ "${first_entry%%:*}" != "root" ]]; then
  msg_error "the passwd list must start with a root entry, got: ${first_entry:-<empty>}"
fi

passwd_tmp="$(mktemp)"
groups_tmp="$(mktemp)"
shadow_tmp="$(mktemp)"
shadow_names="$(mktemp)"
trap 'rm -f -- "${passwd_tmp}" "${groups_tmp}" "${shadow_tmp}" "${shadow_names}"' EXIT

newname=""
newuid=""
newgid=""
newhome=""
newshell=""
declare -a fields=()

while read -r line; do
  if [[ -z ${line} ]] || [[ ${line} =~ ^# ]]; then
    continue
  fi

  fields=()
  IFS=: read -r -a fields <<<"${line}"
  newname="${fields[0]:-}"
  newuid="${fields[2]:-}"
  newgid="${fields[3]:-}"
  newhome="${fields[5]:-}"
  newshell="${fields[6]:-}"

  if [[ -z ${newshell} ]]; then
    msg_error "malformed passwd entry, no shell field: ${line}"
  fi
  echo "${line}" >>"${passwd_tmp}"

  # Create home folder for root and regular users; system accounts
  # (0 < uid < 1000) don't get one.
  if [[ -n ${newuid} && -n ${newgid} && -n ${newhome} ]] && [[ ${newuid} =~ ^[0-9]+$ ]] && ((newuid == 0 || newuid >= 1000)); then
    [[ "${newhome}" == '/' ]] && continue

    home_dir="${root_path}${newhome}"

    # Prevent path traversal
    if ! [[ "$(realpath -qm -- "${home_dir}")" == "${root_path}"* ]]; then
      msg_error "Unable to setup ${newname}, home dir \"${home_dir}\" outside of ${root_path}"
    fi

    msg "Creating home folder for ${newname} (${newuid}:${newgid})"

    if ! mkdir -p -- "$(dirname -- "${home_dir}")"; then
      msg_error "Unable to create parent directory for ${newname}"
    fi

    if [[ -e ${home_dir} ]]; then
      msg "Home folder for ${newname} already exists, not copying /etc/skel"
    elif ! mkdir -p -- "${home_dir}"; then
      msg_error "Unable to create home directory for ${newname}"
    elif [[ ${newuid} == 0 || ! -d "${root_path}/etc/skel" ]]; then
      continue
    elif ! cp -rv -- "${root_path}/etc/skel" "${home_dir}/"; then
      msg_error "Unable to copy /etc/skel for ${newname}"
    fi

    if ! chmod 750 -- "${home_dir}"; then
      msg_error "Unable to set mode on ${home_dir}"
    fi
    if ! chown -R -- "${newuid}:${newgid}" "${home_dir}"; then
      msg_error "Unable to set ownership on ${home_dir}"
    fi
  fi
done <<<"${users}"

while IFS=: read -r pw_entry; do
  shadow_user="${pw_entry%%:*}"
  shadow_pw="${pw_entry#*:}"
  shadow_pw="${shadow_pw%%:*}"

  if [[ -z ${shadow_user} ]]; then
    continue
  fi

  if [[ -z ${shadow_pw} || ${shadow_pw} == "x" || ${shadow_pw} == '!' || ${shadow_pw} == '*' ]]; then
    msg "No password set for ${shadow_user}, keeping existing shadow entry"
    continue
  fi

  if ! mkshadow -u "${shadow_user}" -p "${shadow_pw}" >>"${shadow_tmp}"; then
    msg_error "mkshadow failed for ${shadow_user}"
  fi
  echo "${shadow_user}" >>"${shadow_names}"
done <"${passwd_tmp}"

group_gid=""
declare -a gfields=()

while read -r line; do
  if [[ -z ${line} ]] || [[ ${line} =~ ^# ]]; then
    continue
  fi

  gfields=()
  IFS=: read -r -a gfields <<<"${line}"
  group_gid="${gfields[2]:-}"

  if [[ -z ${group_gid} ]]; then
    msg_error "malformed group entry, no gid field: ${line}"
  fi
  echo "${line}" >>"${groups_tmp}"
done <<<"${groups}"

prune_replaced "${root_path}/etc/passwd" "${passwd_tmp}" 3
awk -F ':' -v OFS=':' '{ $2 = "x"; print }' "${passwd_tmp}" >>"${root_path}/etc/passwd"

prune_replaced "${root_path}/etc/group" "${groups_tmp}" 3
cat -- "${groups_tmp}" >>"${root_path}/etc/group"

if [[ -s "${shadow_tmp}" ]]; then
  prune_replaced "${root_path}/etc/shadow" "${shadow_names}" 0
  cat -- "${shadow_tmp}" >>"${root_path}/etc/shadow"
fi

for etc_file in passwd group shadow; do
  if ! chown 0:0 -- "${root_path}/etc/${etc_file}"; then
    msg_error "Unable to set ownership on /etc/${etc_file}"
  fi
done
if ! chmod 0644 -- "${root_path}/etc/passwd" "${root_path}/etc/group"; then
  msg_error "Unable to set mode on /etc/passwd and /etc/group"
fi
if ! chmod 0640 -- "${root_path}/etc/shadow"; then
  msg_error "Unable to set mode on /etc/shadow"
fi
