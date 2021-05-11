#!/usr/bin/env bash
# https://betterdev.blog/minimal-safe-bash-script-template/

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

# Having the usage() relatively close to the top of the script, it will act in two ways:
#
#  1.  to display help for someone who does not know all the options and does not want to go
#      over the whole script to discover them,
#  2.  as a minimal documentation when someone modifies the script (for example you, 2 weeks
#      later, not even remembering writing it in the first place).
#
# I don’t argue to document every function here. But a short, nice script usage message is
# a required minimum.
usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [OPTION]... IP

Options:
-h, --help            Print this help and exit
-v, --verbose         Print script debug info
    --no-public-key   Do not install your public key
    --ignore-wifi     Do not affect existing wifi config
    --ignore-bt       Do not affect existing bluetooth config
-u, --user            The remote user (default 'ubuntu')
-k, --key       The name of the public key in your ~/.ssh directory (default 'id_rsa.pub')

Arguments: single IP address of the target server to provision

*** INCOMPLETE ***
This script will provision a fresh Raspberry Pi running Ubuntu Server 21.04 to be part of a microk8s cluster.

It will perform the following actions, each of which can be disabled:

1. Install your public key for passwordless login
2. TODO Disable wifi
3. TODO Disable bluetooth
4. TODO Configure cgroups
5. TODO more stuff...

EOF
  exit
}

# Think about the trap like of a finally block for the script. At the end of the script – normal,
# caused by an error or an external signal – the cleanup() function will be executed. This is a
# place where you can, for example, try to remove all temporary files created by the script.

# Just remember that the cleanup() can be called not only at the end but as well having the script
# done any part of the work. Not necessarily all the resources you try to cleanup will exist.
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

# If there is anything that makes sense to parametrized in the script, I usually do that.
# Even if the script is used only in a single place. It makes it easier to copy and reuse it,
# which often happens sooner than later. Also, even if something needs to be hardcoded,
# usually there is a better place for that on a higher level than the Bash script.
#
# There are three main types of CLI parameters – flags, named parameters, and positional
# arguments. The parse_params() function supports them all.
#
# The only one of the common parameter patterns, that is not handled here, is concatenated
# multiple single-letter flags. To be able to pass two flags as -ab, instead of -a -b,
# some additional code would be needed.
#
# The while loop is a manual way of parsing parameters. In every other language you should
# use one of the built-in parsers or available libraries, but, well, this is Bash.
#
# An example flag (-f) and named parameter (-p) are in the template. Just change or copy
# them to add other params. And do not forget to update the usage() afterward.
#
# The important thing here, usually missing when you just take the first google result
# for Bash arguments parsing, is throwing an error on an unknown option. The fact the script
# received an unknown option means the user wanted it to do something that the script is
# unable to fulfill. So user expectations and script behavior may be quite different.
# It’s better to prevent execution altogether before something bad will happen.
#
# There are two alternatives for parsing parameters in Bash. It’s getopt and getopts.
# There are arguments both for and against using them. I found those tools not best,
# since by default getopt on macOS is behaving completely differently, and getopts does
# not support long parameters (like --help).
parse_params() {
  # default values of variables set from params
  flag=0
  user='ubuntu'
  noPublicKey=0
  ignoreWifi=0
  ignoreBt=0
  key='id_rsa.pub'

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    --no-color) NO_COLOR=1 ;;
    --no-public-key) noPublicKey=1 ;; # don't copy your ssh public key to the server
    --ignore-wifi) ignoreWifi=1 ;; # do not affect the wifi config
    --ignore-bt) ignoreBt=1 ;; # do not affect the bluetooth config
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

parse_params "$@"
setup_colors

msg "${GREEN}Read parameters:${NOFORMAT}"
msg "- no-public-key: ${noPublicKey}"
msg "- ignore-wifi: ${ignoreWifi}"
msg "- ignore-bluetooth: ${ignoreBt}"
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

# date
# hostname
# cat /etc/resolv.conf

