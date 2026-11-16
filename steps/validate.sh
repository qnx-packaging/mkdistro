#!/usr/bin/env bash

# Validate a preset's mkdistro.conf
# Exits 0 when the preset is valid, 1 with one ERROR line per problem when not.

# shellcheck disable=SC2034 # preset variables are read dynamically via
# preset_var/${!name} and preset_each namerefs, which shellcheck cannot trace

set -Eeuo pipefail

PROG="validate"
# shellcheck source=steps/prelude.sh
source "$(dirname -- "$(realpath -e -- "${BASH_SOURCE[0]}")")/prelude.sh"

usage() {
  echo "validate.sh [PRESET]
    [PRESET] directory containing a mkdistro.conf"
}

#--- state -------------------------------------------------------------------

# Defaults mirror the preset variable block in mkdistro; a preset only needs
# to override what it changes.
arch=""
boot_partition_type=""
boot_partition_size=0
boot_partition_layout=""
image_size=0
image_format=""
image_inodes=""
repositories=()
local_repositories=()
packages=()
keys=()
users=()
groups=()
openrc_services=()
declare -A openrc_confd=()
declare -A file_permissions=()

#--- validation helpers ------------------------------------------------------

preset_errors=()

preset_error() {
  preset_errors+=("${1}")
  printf '[%s] ERROR: %s\n' "${PROG}" "${1}" >&2
}

report_preset_errors() {
  if ((${#preset_errors[@]} > 0)); then
    printf '[%s] ERROR: preset is invalid (%d problem(s))\n' "${PROG}" "${#preset_errors[@]}" >&2
    quit 1
  fi
}

# preset_check VALUE SUBJECT MESSAGE REGEX
preset_check() {
  local value="${1}" subject="${2}" message="${3}" regex="${4}"

  # shellcheck disable=SC2254 # the regex must stay dynamic
  if [[ -z "${value}" ]]; then
    preset_error "${subject} is empty or unset"
  elif [[ ! "${value}" =~ ${regex} ]]; then
    preset_error "${subject}: ${message} (got '${value}')"
  fi
}

# preset_var NAME REGEX MESSAGE -- check the scalar variable NAME.
preset_var() {
  local name="${1}" regex="${2}" message="${3}"

  preset_check "${!name-}" "'${name}'" "${message}" "${regex}"
}

# preset_nonempty NAME -- array NAME must have at least one entry.
preset_nonempty() {
  local name="${1}"
  local -n list="${name}"

  if ((${#list[@]} == 0)); then
    preset_error "array '${name}' is empty or unset"
  fi
}

# preset_each NAME REGEX MESSAGE -- every entry of array NAME must match
# REGEX. An empty array is itself an error.
preset_each() {
  local name="${1}" regex="${2}" message="${3}"
  local -n list="${name}"
  local entry

  if ((${#list[@]} == 0)); then
    preset_error "array '${name}' is empty or unset"
    return 0
  fi

  for entry in "${list[@]}"; do
    preset_check "${entry}" "array '${name}' entry '${entry}'" "${message}" "${regex}"
  done
}

# Cross-field consistency for users/groups; run after the format checks.
validate_users_and_groups() {
  local -A user_names=() user_uids=() group_names=() group_gids=()
  local -a f=()
  local entry name uid gid members member bad=0

  for entry in "${users[@]}"; do
    f=()
    IFS=: read -r -a f <<<"${entry}"
    name="${f[0]:-}"
    uid="${f[2]:-}"
    gid="${f[3]:-}"

    if [[ -z "${name}" || -z "${uid}" || -z "${gid}" ]]; then
      continue
    fi

    if [[ -n ${user_names[${name}]+set} ]]; then
      preset_error "user '${name}' is declared more than once"
      bad=1
    fi
    user_names["${name}"]=1

    if [[ -n ${user_uids[${uid}]+set} ]]; then
      preset_error "uid ${uid} is used by more than one user"
      bad=1
    fi
    user_uids["${uid}"]=1
  done

  if [[ ${#users[@]} -gt 0 && "${users[0]%%:*}" != "root" ]]; then
    preset_error "users must start with a root entry, got '${users[0]%%:*}'"
    bad=1
  fi

  for entry in "${groups[@]}"; do
    f=()
    IFS=: read -r -a f <<<"${entry}"
    name="${f[0]:-}"
    gid="${f[2]:-}"
    members="${f[3]:-}"

    if [[ -z "${name}" || -z "${gid}" ]]; then
      continue
    fi

    if [[ -n ${group_names[${name}]+set} ]]; then
      preset_error "group '${name}' is declared more than once"
      bad=1
    fi
    group_names["${name}"]=1

    if [[ -n ${group_gids[${gid}]+set} ]]; then
      preset_error "gid ${gid} is used by more than one group"
      bad=1
    fi
    group_gids["${gid}"]=1

    local -a member_list=()
    IFS=, read -r -a member_list <<<"${members}"
    for member in "${member_list[@]}"; do
      if [[ -z ${member} ]]; then
        continue
      fi
      if [[ -z ${user_names[${member}]+set} ]]; then
        preset_error "group '${name}' lists member '${member}' which is not in users"
        bad=1
      fi
    done
  done

  for entry in "${users[@]}"; do
    f=()
    IFS=: read -r -a f <<<"${entry}"
    name="${f[0]:-}"
    gid="${f[3]:-}"
    if [[ -z "${name}" || -z "${gid}" ]]; then
      continue
    fi
    if [[ -z ${group_gids[${gid}]+set} ]]; then
      preset_error "user '${name}' has primary gid ${gid} which no group in groups declares"
      bad=1
    fi
  done

  return "${bad}"
}

#--- the check table ---------------------------------------------------------

validate_preset() {
  preset_var arch '^(x86_64|aarch64)$' "expected one of: x86_64, aarch64"
  #TODO: add a known list of types from diskimage
  preset_var boot_partition_type '.+' "required"
  preset_var boot_partition_size '^auto$|^[0-9]+[GMT]$' "expected auto or a size like 256M"

  # NOTE: efi is special and has a built in layout since it is so common
  if [[ "${boot_partition_type}" != "efi" ]]; then
    preset_var boot_partition_layout '.+' "required when boot_partition_type is not efi"
  fi

  preset_var image_size '^auto$|^[0-9]+[GMT]$' "expected auto or a size like 200G"
  preset_var image_format '^(raw|qcow2)$' "expected one of: raw, qcow2"
  preset_var image_inodes '^(auto|-?[0-9]+)$' "expected auto or an integer"

  preset_nonempty repositories
  preset_nonempty packages
  preset_each keys '^(https?|abuild|file)://' "unsupported key URL; use http, https, abuild or file"

  local entry
  for entry in "${local_repositories[@]}"; do
    preset_check "${entry%%::*}" "local_repositories entry '${entry}'" \
      "embed path and repo must be absolute paths without spaces" '^/[^[:space:]]*$'
    if [[ "${entry}" == *::* ]]; then
      preset_check "${entry#*::}" "local_repositories entry '${entry}'" \
        "embed path and repo must be absolute paths without spaces" '^/[^[:space:]]*$'
    fi
  done

  preset_each users '^[A-Za-z0-9._-]+:[^:]*:[0-9]+:[0-9]+:[^:]*:/:?[A-Za-z0-9._/-]*:[^:]+$' \
    "not a valid passwd entry (name:pw:uid:gid:gecos:home:shell)"
  preset_each groups '^[A-Za-z0-9._-]+:[^:]*:[0-9]+(:[A-Za-z0-9._,-]*)?$' \
    "not a valid group entry (name:pw:gid[:members])"
  if ! validate_users_and_groups; then
    preset_error "users and groups are inconsistent"
  fi

  local key service enabled
  for key in "${!openrc_confd[@]}"; do
    if [[ ! "${key}" =~ ^[A-Za-z0-9._-]+$ ]]; then
      preset_error "openrc_confd key '${key}': the service name is not a plain filename"
      continue
    fi
    enabled=false
    for service in "${openrc_services[@]}"; do
      if [[ "${service}" == "${key}" ]]; then
        enabled=true
      fi
    done
    if [[ "${enabled}" == false ]]; then
      preset_error "openrc_confd key '${key}': openrc_services does not enable it"
    fi
  done

  # file_permissions is optional: an overlay without it keeps default ownership/mode
  local path
  for path in "${!file_permissions[@]}"; do
    if [[ "${path}" != /* ]]; then
      preset_error "file_permissions key '${path}': not an absolute path"
    elif [[ "${path}" == *..* ]]; then
      preset_error "file_permissions key '${path}': must not contain '..'"
    fi
  done
  if ((${#file_permissions[@]} > 0)); then
    preset_each file_permissions '^[0-9]+:[0-9]+:[0-7]{3,4}$' \
      "not a valid permissions entry (uid:gid:octal-mode)"
  fi

  report_preset_errors
}

#--- main --------------------------------------------------------------------

if (($# != 1)); then
  usage >&2
  die "expected a PRESET directory, got $#: $*"
fi

preset_path="$(realpath -m -- "$1")" || die "cannot resolve preset path: $1"

if [[ ! -d "${preset_path}" ]]; then
  die "preset at '${preset_path}' does not exist"
elif [[ ! -e "${preset_path}/mkdistro.conf" ]]; then
  die "preset at '${preset_path}' does not contain a 'mkdistro.conf' file"
fi

cd -- "${preset_path}" || die "failed to cd to '${preset_path}'"

# shellcheck source=/dev/null
. "${preset_path}/mkdistro.conf" || die "can't source '${preset_path}/mkdistro.conf'"

# Prints every problem and exits 1 when any were collected.
validate_preset

msg "preset is valid"
