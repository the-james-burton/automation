#!/usr/bin/env bash
# https://betterdev.blog/minimal-safe-bash-script-template/

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [OPTION]... IP

Options:
-h, --help            Print this help and exit
-v, --verbose         Print script debug info
    --no-public-key   Do not install your public key
    --ignore-wifi     Do not affect existing wifi config
    --ignore-bt       Do not affect existing bluetooth config
    --ignore-cgroups  Do not affect existing cgroups config
-u, --user            The remote user (default 'ubuntu')
-k, --key       The name of the public key in your ~/.ssh directory (default 'id_rsa.pub')

Arguments: single IP address of the target server to provision

*** INCOMPLETE ***
This script will provision a fresh Raspberry Pi running Ubuntu Server 21.04 to be part of a microk8s cluster.

It will perform the following actions, each of which can be disabled:

1. Install your public key for passwordless login
2. TODO first time forced password change
2. Disable wifi
3. Disable bluetooth
4. Configure cgroups
5. TODO install microk8s

EOF
  exit
}

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  # script cleanup here
}

setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}

# The msg() function is meant to be used to print everything that is not a script output.
# This includes all logs and messages, not only the errors.
msg() {
  echo >&2 -e "${1-}"
}

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg "$msg"
  exit "$code"
}

parse_params() {
  # default values of variables set from params
  flag=0
  user='ubuntu'
  noPublicKey=0
  ignoreWifi=0
  ignoreBt=0
  ignoreCGroups=0
  key='id_rsa.pub'

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    --no-color) NO_COLOR=1 ;;
    --no-public-key) noPublicKey=1 ;; # don't copy your ssh public key to the server
    --ignore-wifi) ignoreWifi=1 ;; # do not affect the wifi config
    --ignore-bt) ignoreBt=1 ;; # do not affect the bluetooth config
    --ignore-cgroups) ignoreCGroups=1 ;; # do not affect the cgroups setting
    -u | --user) # remote user
      user="${2-}"
      shift
      ;;
    -k | --key) # name of the public key in your ~/.ssh directory
      key="${2-}"
      shift
      ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  # check required params and arguments
  # [[ -z "${ip-}" ]] && die "Missing required parameter: ip"
  [[ ${#args[@]} -eq 0 ]] && die "Missing IP address"

  return 0
}

# appends the given line to the end of the given file if it is not already present in the file
# parameters
#  1: the line to add to a file
#  2: absolute path to a file
append_line_if_not_exists() {
  msg "${CYAN}line: ${1}, file: ${2}${NOFORMAT}"
     ssh ${user}@${args[0]} <<APPEND
     if [ ! -f "${2}" ]
     then
       touch ${2}
     fi
     grep -qF "${1}" "${2}"  || echo "${1}" | sudo tee --append "${2}"
APPEND
}

# appends the given text to the start of the given file if it is not already present in the file
# parameters
#  1: the text to add to a file
#  2: absolute path to a file
prefix_text_if_not_exists() {
  msg "${CYAN}text: ${1}, file: ${2}${NOFORMAT}"
     ssh ${user}@${args[0]} <<PREFIX
     if [ ! -f "${2}" ]
     then
       touch "${2}"
     fi
     grep -qF "${1}" "${2}" && exit
     echo adding text: "${1}", file: "${2}"
     mapfile <"${2}"
     echo "${1}""\${MAPFILE[@]}" | sudo tee "${2}"
PREFIX
}

parse_params "$@"
setup_colors

msg "${GREEN}Read parameters:${NOFORMAT}"
msg "- no-public-key: ${noPublicKey}"
msg "- ignore-wifi: ${ignoreWifi}"
msg "- ignore-bt: ${ignoreBt}"
msg "- ignore-cgroups: ${ignoreCGroups}"
msg "- user: ${user}"
msg "- key: ${key}"
msg "- ip: ${args[*]-}"

# install public key for passwordless login...
if [ ${noPublicKey} -eq 0 ]
then
 msg "Installing your public key..."
 ssh-copy-id  -i ~/.ssh/${key} ${user}@${args[0]}
fi

# disable wifi...
if [ ${ignoreWifi} -eq 0 ]
then
 msg "${GREEN}Disabling wifi...${NOFORMAT}"
   append_line_if_not_exists 'dtoverlay=disable-wifi' '/boot/firmware/config.txt'
fi

# disable bluetooth...
if [ ${ignoreBt} -eq 0 ]
then
 msg "${GREEN}Disabling bluetooth...${NOFORMAT}"
   append_line_if_not_exists 'dtoverlay=disable-bt' '/boot/firmware/config.txt'
fi

# enable c-groups...
if [ ${ignoreCGroups} -eq 0 ]
then
 msg "${GREEN}Enabling c-groups...${NOFORMAT}"
   prefix_text_if_not_exists 'cgroup_enable=memory cgroup_memory=1 ' '/boot/firmware/cmdline.txt'
fi

# end of script...
msg "${GREEN}Completed!${NOFORMAT}"