#!/usr/bin/env bash

# RUN ME IN FAKEROOT!
# Generate the passwd, shadow and group files for a root filesystem from the
# preset's user and group lists, and create home folders from /etc/skel.
# The preset owns the root account: the passwd list must start with a root
# entry and nothing here creates a root home implicitly.

set -Eeuo pipefail

PROG="passwd-gen"
# shellcheck source=steps/prelude.sh
source "$(dirname -- "$(realpath -e -- "${BASH_SOURCE[0]}")")/prelude.sh"

usage() {
  echo "passwd-gen.sh [ROOT] [PASSWD_FILE] [GROUP_FILE]

    [ROOT]         directory to output generated passwd/shadow/group files
    [PASSWD_FILE]  path to passwd file as a base; first entry must be root
    [GROUP_FILE]   path to group file as a base
"
}

if (($# != 3)); then
  usage >&2
  die "expected ROOT, PASSWD_FILE and GROUP_FILE, got $#: $*"
fi

root_path="$1"
passwd_file="$2"
groups_file="$3"

[[ -e "${passwd_file}" ]] || die "passwd_file undefined!"
[[ -e "${groups_file}" ]] || die "groups_file undefined!"
[[ -d "${root_path}" ]] || die "bad out dir ${root_path}"
command -v mkshadow >/dev/null 2>&1 || die "mkshadow command not found. SDP not activated?"

users="$(cat "${passwd_file}")"
groups="$(cat "${groups_file}")"

first_entry="$(awk 'NF && $0 !~ /^#/ { print; exit }' <<<"${users}")"
[[ "${first_entry%%:*}" == "root" ]] ||
  die "the passwd list must start with a root entry, got: ${first_entry:-<empty>}"

passwd_tmp="$(mktemp)"
groups_tmp="$(mktemp)"
shadow_tmp="$(mktemp)"
shadow_names="$(mktemp)"
trap 'rm -f -- "${passwd_tmp}" "${groups_tmp}" "${shadow_tmp}" "${shadow_names}"' EXIT

prune_replaced() {
  local target="$1"
  local incoming="$2"
  local id_field="$3"
  local tmp

  touch -- "${target}" || die "Unable to create ${target}"
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
    die "Unable to rewrite ${target}"
  fi

  if ! cat -- "${tmp}" >"${target}"; then
    rm -f -- "${tmp}"
    die "Unable to update ${target}"
  fi
  rm -f -- "${tmp}"
}

declare -a fields=()
line=""

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

  [[ -n ${newshell} ]] || die "malformed passwd entry, no shell field: ${line}"
  echo "${line}" >>"${passwd_tmp}"

  # Create home folder for root and regular users; system accounts
  # (0 < uid < 1000) don't get one.
  if [[ -n ${newuid} && -n ${newgid} && -n ${newhome} ]] && [[ ${newuid} =~ ^[0-9]+$ ]] && ((newuid == 0 || newuid >= 1000)); then
    [[ "${newhome}" == '/' ]] && continue

    home_dir="${root_path}${newhome}"

    # Prevent path traversal
    [[ "$(realpath -qm -- "${home_dir}")" == "${root_path}"* ]] ||
      die "Unable to setup ${newname}, home dir \"${home_dir}\" outside of ${root_path}"

    msg "Creating home folder for ${newname} (${newuid}:${newgid})"

    mkdir -p -- "$(dirname -- "${home_dir}")" \
      || die "Unable to create parent directory for ${newname}"

    if [[ -e ${home_dir} ]]; then
      msg "Home folder for ${newname} already exists, not copying /etc/skel"
    else
      mkdir -p -- "${home_dir}" || die "Unable to create home directory for ${newname}"
      if [[ ! ${newuid} == 0 && -d "${root_path}/etc/skel" ]]; then
        cp -rv -- "${root_path}/etc/skel/." "${home_dir}" \
          || die "Unable to copy /etc/skel for ${newname}"
      fi
    fi

    chmod 750 -- "${home_dir}" || die "Unable to set mode on ${home_dir}"
    chown -R -- "${newuid}:${newgid}" "${home_dir}" \
      || die "Unable to set ownership on ${home_dir}"
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

  mkshadow -u "${shadow_user}" -p "${shadow_pw}" >>"${shadow_tmp}" || die "mkshadow failed for ${shadow_user}"
  echo "${shadow_user}" >>"${shadow_names}"
done <"${passwd_tmp}"

declare -a gfields=()

while read -r line; do
  if [[ -z ${line} ]] || [[ ${line} =~ ^# ]]; then
    continue
  fi

  gfields=()
  IFS=: read -r -a gfields <<<"${line}"
  [[ -n ${gfields[2]:-} ]] || die "malformed group entry, no gid field: ${line}"
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
  chown 0:0 -- "${root_path}/etc/${etc_file}" \
    || die "Unable to set ownership on /etc/${etc_file}"
done
chmod 0644 -- "${root_path}/etc/passwd" "${root_path}/etc/group" \
  || die "Unable to set mode on /etc/passwd and /etc/group"
chmod 0640 -- "${root_path}/etc/shadow" || die "Unable to set mode on /etc/shadow"
