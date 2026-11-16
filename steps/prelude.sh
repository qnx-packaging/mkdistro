#!/usr/bin/env bash
#
# Shared function library for mkdistro and the step scripts in this directory.
# Sourced, never executed: this file only defines functions.
#
# Callers set PROG before sourcing to pick their message prefix.

PROG="${PROG:-mkdistro}"

#--- logging -----------------------------------------------------------------

msg() {
  printf '[%s] %s\n' "${PROG}" "${1}"
}

warning() {
  printf '[%s] WARNING: %s\n' "${PROG}" "${1}" >&2
}

# Leave the program with a status. Drops the ERR trap first.
quit() {
  trap - ERR
  exit "${1}"
}

die() {
  printf '[%s] ERROR: %s\n' "${PROG}" "${*}" >&2
  quit 1
}

#--- sizes -------------------------------------------------------------------

to_bytes() {
  numfmt --from=iec "${1}"
}

from_bytes() {
  numfmt --to=iec "${1}" --format="%.2f" | sed -E 's/0+([A-Z]*)$/\1/; s/\.([A-Z]*)$/\1/'
}

to_bytes_checked() {
  local what="${1}"
  local value="${2}"
  local bytes

  if ! bytes="$(to_bytes "${value}")"; then
    die "unable to parse ${what} = '${value}' as a size"
  fi

  printf '%s\n' "${bytes}"
}

#--- fakeroot ----------------------------------------------------------------

# Run a command inside the staged build's fakeroot session.
# shellcheck disable=SC2154 # fakeroot_save is set by the sourcing script
in_fakeroot() {
  fakeroot -i "${fakeroot_save}" -s "${fakeroot_save}" -- "$@"
}
