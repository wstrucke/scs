#!/bin/bash
#
# Simple Configuration [Management] System
# Manage and deploy application configuration files to multiple environments
#
# William Strucke [wstrucke@gmail.com]
# Version 1.0.0, May 2014
#
# Copyright 2014
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Configuration Storage:
#   ./app-config/
#     application                                          file
#     binary                                               directory
#     binary/<environment>/                                environment binary files
#     build                                                file
#     constant                                             constant index
#     environment                                          file
#     file                                                 file
#     file-map                                             application to file map
#     hv-environment                                       file
#     hv-network                                           file
#     hypervisor                                           file
#     location                                             file
#     network                                              file
#     net                                                  directory
#     net/a.b.c.0                                          file with IP index for IPAM component
#     resource                                             file
#     system                                               file
#     template/                                            directory containing global application templates
#     template/patch/<environment>/                        directory containing template patches for the environment
#     value/                                               directory containing constant definitions
#     value/constant                                       file (global)
#     value/<environment>/                                 directory
#     value/<environment>/constant                         file (environment)
#     value/<environment>/<application>                    file (environment application)
#     value/<location>/                                    directory
#     value/<location>/<environment>                       file (location environment)
#     <location>/                                          directory
#     <location>/network                                   file to list networks available at the location
#     <location>/<environment>                             file
#
# Locks are taken by using git branches. This should be revisited and improved - the current method cleanly avoids most merge conflicts.
#
# A constant is a variable with a static value globally, per environment, or per application in an environment. (Scope)
# A constant has a globally unique name with a fixed value in the scope it is defined in and is in only one scope (never duplicated).
#
# A resource is a pre-defined type with a globally unique value (e.g. an IP address).  That value can be assigned to either a host or an application in an environment.
#
# Use constants and resources in configuration files -- this is the whole point of scs, mind you -- with this syntax:
#  {% resource.name %}
#  {% constant.name %}
#  {% system.name %}, {% system.ip %}, {% system.location %}, {% system.environment %}
#
# Data storage format -- flat file schema:
#   Overall requirement - files are stored in CSV format and no field can have a comma because we have no concept of an escape character.
#
#   application
#   --description: application details
#   --format: name,alias,build,cluster\n
#   --storage:
#   ----name            a unique name for the application
#   ----alias           an alias for the application (currently unused)
#   ----build           the build the application is installed on
#   ----cluster         y/n - whether or not the application supports load balancing
#
#   build
#   --description: server builds
#   --format: name,role,description,os,arch,disk,ram\n
#   --storage:
#
#   constant
#   --description: variables used to generate configurations
#   --format: name,description\n
#   --storage:
#
#   environment
#   --description: 'stacks' or groups of instances of all or a subset of applications
#   --format: name,alias,description\n
#   --storage:
#
#   file
#   --description: files installed on servers
#   --format: name,path,type,owner,group,octal,target,description\n
#   --storage:
#   ----name	        a unique name to reference this entry; sometimes the actual file name but since
#                         there is only one namespace you may have to be creative.
#   ----path            the path on the system this file will be deployed to.
#   ----type            the type of entry, one of 'file', 'symlink', 'binary', 'copy', or 'download'.
#   ----owner           user name
#   ----group           group name
#   ----octal           octal representation of the file permissions
#   ----target          optional field; for type 'symlink', 'copy', or 'download' - what is the target
#   ----description     a description for this entry. this is not used anywhere except "$0 file show <entry>"
#
#   file-map
#   --description: map of files to applications
#   --format: filename,application\n
#   --storage:
#
#   hv-environment
#   --description: hypervisor/environment map
#   --format: environment,hypervisor
#   --storage:
#   ----environment     the name of the 'environment'
#   ----hypervisor      the name of the 'hypervisor'
#
#   hv-network
#   --description: hypervisor/network map
#   --format: loc-zone-alias,hv-name,interface
#   --storage:
#   ----loc-zone-alias  network 'location,zone,alias' in the usual format
#   ----hv-name         the hostname of the hypervisor
#   ----interface       the name of the interface on the hypervisor for this network
#
#   hypervisor
#   --description: virtual machine host servers
#   --format: name,management-ip,location,vm-path,vm-min-disk(mb),min-free-mem(mb),enabled
#   --storage:
#   ----name	        the hostname
#   ----management-ip   the ip the scs server will use to manage the hypervisor
#   ----location        name of the location of the hv (matches 'location')
#   ----vm-path         path on the file system to the virtual-machine images (e.g. '/usr/local/vm')
#   ----vm-min-disk     the minimum amount of disk space to leave available (in MB)
#   ----min-free-mem    the minimum amount of memory to leave available (in MB)
#   ----enabled         y/n - if 'n' do not add any virtual-machines to this host
#
#   location
#   --description: sites or locations
#   --format: code,name,description\n
#   --storage:
#
#   network
#   --description: network registry
#   --format: location,zone,alias,network,mask,cidr,gateway_ip,dns_ip,vlan,description,repo_address,repo_fs_path,repo_path_url,build,default-build,ntp_ip\n
#   --storage:
#
#   net/a.b.c.0
#   --description: subnet ip assignment registry
#   --format: octal_ip,cidr_ip,reserved,dhcp,hostname,host_interface,comment,interface_comment,owner\n
#   --storage:
#
#   resource
#   --description: arbitrary 'things' (such as IP addresses for a specific purpose) assigned to
#                    systems and used to generate configs
#   --format: type,value,assign_type,assign_to,name,description\n
#   --storage:
#
#   system
#   --description: servers
#   --format: name,build,ip,location,environment\n
#   --storage:
#
#   value/constant
#   --description: global values for constants
#   --format: constant,value\n
#   --storage:
#
#   value/<environment>/constant
#   --description: environment scoped values for constants
#   --format: constant,value\n
#   --storage:
#
#   value/<location>/<environment>
#   --description: enironment at a specific site scoped values for constants
#   --format: constant,value\n
#   --storage:
#
#   <location>/network
#   --description: network details for a specific location
#   --format: zone,alias,network/cidr,build,default-build\n
#   --storage:
#   ----zone            network zone; must be identical to the entry in 'network'
#   ----alias           network alias; must be identical to the entry in 'network'
#   ----network/        network ip address (e.g. 192.168.0.0) followed by a forward slash
#   ----cidr            the CIDR mask bits (e.g. 24)
#   ----build           'y' or 'n', is this network used to build servers
#   ----default-build   'y' or 'n', should this be the DEFAULT network at the location for builds
#
# External requirements:
#   Linux stuff - which, awk, sed, tr, echo, git, tput, head, tail, shuf, wc, nc, sort, ping, nohup, logger
#   My stuff - kvm-uuid.sh
#
# TO DO:
#   - deleting an application should also unassign resources and undefine constants
#   - finish IPAM and IP allocation components
#   - validate IP addresses using the new valid_ip function
#   - simplify IP management functions by reducing code duplication
#   - system_audit and system_deploy both delete the generated release. reconsider keeping it.
#   - add detailed help section for each function
#   - add concept of 'instance' to environments and define 'stacks'
#   - get_yn should pass options (such as --default) to get_input
#   - populate reserved IP addresses from IP-Scheme.xlsx
#   - rename operations should update map files (hv stuff specifically for net/env/loc)
#   - reduce the number of places files are read directly. eventually use an actual DB.
#   - ADD: build [<environment>] [--name <build_name>] [--assign-resource|--unassign-resource|--list-resource]
#   - overhaul scs - split into modules, put in installed path with sub-folder, dependencies, and config file
#   - add support for static routes for a network
#


 #     # ####### ### #       ### ####### #     # 
 #     #    #     #  #        #     #     #   #  
 #     #    #     #  #        #     #      # #   
 #     #    #     #  #        #     #       #    
 #     #    #     #  #        #     #       #    
 #     #    #     #  #        #     #       #    
  #####     #    ### ####### ###    #       #

# convert subnet mask bits into a network mask
#   source: https://forum.openwrt.org/viewtopic.php?pid=220781#p220781
#
# required:
#   $1    X (where X is greater than or equal to 0 and less than or equal to 32)
#
function cdr2mask {
  test $# -ne 1 && return 1
  test "$1" != "${1/[^0-9]/}" && return 1
  if [[ $1 -lt 0 || $1 -gt 32 ]]; then return 1; fi
  set -- $(( 5 - ($1 / 8) )) 255 255 255 255 $(( (255 << (8 - ($1 % 8))) & 255 )) 0 0 0
  [ $1 -gt 1 ] && shift $1 || shift
  echo ${1-0}.${2-0}.${3-0}.${4-0}
  return 0
}

# return the number of possible IPs in a network based in the cidr mask
#   this intentionally does not account for the network and broadcast address
#
# required:
#   $1   X (where X is the CIDR mask: 0 <= X <= 32 )
#
function cdr2size {
  test $# -ne 1 && return 1
  test "$1" != "${1/[^0-9]/}" && return 1
  if [[ $1 -lt 0 || $1 -gt 32 ]]; then return 1; fi
  echo $(( 1 << ( ( $1 - 32 ) * -1 ) ))
  return 0
}

function check_abort {
  if [ $# -gt 0 ]; then MSG=" $1"; else MSG=""; fi
  if [ -f $ABORTFILE ]; then errlog "ERROR - abort file appeared, halting execution.$MSG"; fi
}

# exit function called from trap
#
function cleanup_and_exit {
  local code=$?
  test -d $TMP && rm -rf $TMP
  test -f /tmp/app-config.$$ && rm -f /tmp/app-config.$$*
  exit $code
}

# convert a decimal value to an ipv4 address
#
# SOURCE: http://stackoverflow.com/questions/10768160/ip-address-converter
#
function dec2ip {
  local ip delim dec=$1
  for e in {3..0}; do
    ((octet = dec / (256 ** e) ))
    ((dec -= octet * 256 ** e))
    ip+=$delim$octet
    delim=.
  done
  printf '%s\n' "$ip"
  return 0
}

# error / exit function
#
function err {
  popd >/dev/null 2>&1
  test ! -z "$1" && echo $1 >&2 || echo "An error occurred" >&2
  test x"${BASH_SOURCE[0]}" == x"$0" && exit 1 || return 1
}

# error / exit function for daemon processes
#
function errlog {
  test ! -z "$1" && MSG="$1" || MSG="An error occurred"
  echo "$MSG" >&2
  /usr/bin/logger -t "scs" "$MSG"
  exit 1
}

# return the exit code from an arbitrary function as a string
#
function exit_status {
  test $# -gt 0 || return 1
  eval $1 ${@:2} >/dev/null 2>&1
  RC=$?
  printf -- $RC
  return $RC
}

function expand_subject_alias {
  case "$1" in
    a|ap|app) printf -- 'application';;
    b|bld) printf -- 'build';;
    ca|can) printf -- 'cancel';;
    con|cons|const) printf -- 'constant';;
    com) printf -- 'commit';;
    d|di|dif) printf -- 'diff';;
    e|en|env) printf -- 'environment';;
    f) printf -- 'file';;
    he|?) printf -- 'help';;
    hv|hy|hyp|hyper) printf -- 'hypervisor';;
    l|lo|loc) printf -- 'location';;
    n|ne|net) printf -- 'network';;
    r|re|res) printf -- 'resource';;
    st|sta|stat) printf -- 'status';;
    sy|sys|syst) printf -- 'system';;
    *) printf -- "$1";;
  esac
}

function expand_verb_alias {
  case "$1" in
    a|ap|app) printf -- 'application';;
    ca) printf -- 'cat';;
    co|con|cons|const) printf -- 'constant';;
    cr) printf -- 'create';;
    d|de|del) printf -- 'delete';;
    e|ed) printf -- 'edit';;
    f) printf -- 'file';;
    l|li|lis|ls) printf -- 'list';;
    s|sh|sho) printf -- 'show';;
    u|up|upd|updat) printf -- 'update';;
    *) printf -- "$1";;
  esac
}

# generic choose function, since they are all exactly the same
#
# required:
#  $1 name of file to search
#  $2 value to search for in the list
#  $3 variable to return
#
# optional:
#  $4 value to pass to list function
#
function generic_choose {
  printf -- $1 |grep -qE '^[aeiou]' && AN="an" || AN="a"
  [ "$1" == "resource" ] && M="," || M="^"
  test ! -z "$2" && grep -qiE "$M$2," ${CONF}/$1
  if [ $? -ne 0 ]; then
    eval $1_list \"$4\"
    printf -- "\n"
    get_input I "Please specify $AN $1"
    grep -qE "$M$I," ${CONF}/$1 || err "Unknown $1" 
    printf -- "\n"
    eval $3="$I"
    return 1
  else
    eval $3="$2"
  fi
  return 0
}

# generic delete function, since they are all exactly the same
#
function generic_delete {
  test -z "$1" && return
  start_modify
  if [ -z "$2" ]; then
    eval ${1}_list
    printf -- "\n"
    get_input C "`printf -- $1 |sed -e "s/\b\(.\)/\u\1/g"` to Delete"
  else
    C="$2"
  fi
  grep -qE "^$C," ${CONF}/$1 || err "Unknown $1"
  get_yn RL "Are you sure (y/n)? "
  if [ "$RL" != "y" ]; then return 1; fi
  sed -i '/^'$C',/d' ${CONF}/$1
  commit_file $1
  return 0
}

# input functions
#
# requires:
#  $1 variable name (no spaces)
#  $2 prompt
#
# optional:
#  --default ""    specify a default value
#  --nc            do not force lowercase
#  --null          allow null (empty) values
#  --options       comma delimited list of options to restrict selection to
#  --regex         validation regex to match against (passed to grep -E)
#  --comma         allow a comma in the input (default NO)
#
function get_input {
  test $# -lt 2 && return
  LC=1; RL=""; P="$2"; V="$1"; D=""; NUL=0; OPT=""; RE=""; COMMA=0; CL=0; shift 2
  while [ $# -gt 0 ]; do case $1 in
    --default) D="$2"; shift;;
    --nc) LC=0;;
    --null) NUL=1;;
    --options) OPT="$2"; shift;;
    --regex) RE="$2"; shift;;
    --comma) COMMA=1;;
    *) err;;
  esac; shift; done
  # get the screen size or pick a reasonable default
  local WIDTH=$( tput cols 2>/dev/null ); test -z "$WIDTH" && WIDTH=80
  # collect input until a valid entry is provided
  while [ -z "$RL" ]; do
    # output the prompt
    test $NUL -eq 0 && printf -- '*'; printf -- "$P"
    # output the list of valid options if one was provided
    if ! [ -z "$OPT" ]; then
      LEN=$( printf -- "$OPT" |wc -c )
      if [ $LEN -gt $(( $WIDTH - 30 )) ]; then
        printf -- " ( .. long list .. )"
        tput smcup; clear; CL=1
        printf -- "Select an option from the below list:\n"
        for O in ${OPT//,/ }; do printf -- " - $O\n"; done
        printf -- "\n\n"
        test $NUL -eq 0 && printf -- '*'; printf -- "$P"
      else
        printf -- " (`printf -- "$OPT" |sed 's/,/, /g'`"
        if [ $NUL -eq 1 ]; then printf -- ", null)"; else printf -- ")"; fi
      fi
    fi
    # output the default option if one was provided
    test ! -z "$D" && printf -- " [$D]: " || printf -- ": "
    # collect the input and force it to lowercase unless requested not to
    read -r RL; if [ $LC -eq 1 ]; then RL=$( printf -- "$RL" |tr 'A-Z' 'a-z' ); fi
    # if the scren was cleared, output the entered value
    if [ $CL -eq 1 ]; then tput rmcup; printf -- ": $RL\n"; fi
    # if no input was provided and there is a default value, set the input to the default
    [[ -z "$RL" && ! -z "$D" ]] && RL="$D"
    # special case to clear an existing value
    if [[ "$RL" == "null" || "$RL" == "NULL" ]]; then RL=""; fi
    # if no input was provied and null values are allowed, stop collecting input here
    [[ -z "$RL" && $NUL -eq 1 ]] && break
    # if there is a list of limited options clear the provided input unless it matches the list
    if ! [ -z "$OPT" ]; then printf -- ",$OPT," |grep -q ",$RL," || RL=""; fi
    # if a validation regex was provided, check the input against it
    if ! [ -z "$RE" ]; then printf -- "$RL" |grep -qE "$RE" || RL=""; fi
    # finally, enforce no comma rule
    if [[ ! -z "$RL" && $COMMA -eq 0 ]]; then printf -- "$RL" |grep -qE '[^,]*' || RL=""; fi
  done
  # set the provided variable value to the validated input
  eval "$V='$RL'"
}

# get the network address for a given ip and subnet mask
#
# SOURCE:
# http://stackoverflow.com/questions/15429420/given-the-ip-and-netmask-how-can-i-calculate-the-network-address-using-bash
#
# This is completely equivilent to `ipcalc -n $1 $2`, but that is not
#   necessarily available on all operating systems.
#
# required:
#   $1  ip address
#   $2  subnet mask
#
function get_network {
  test $# -eq 2 || return 1
  valid_ip $1 || return 1
  local J="$2"
  test "$2" == "${2/[^0-9]/}" && J=$( cdr2mask $2 )
  IFS=. read -r i1 i2 i3 i4 <<< "$1"
  IFS=. read -r m1 m2 m3 m4 <<< "$J"
  printf "%d.%d.%d.%d\n" "$((i1 & m1))" "$(($i2 & m2))" "$((i3 & m3))" "$((i4 & m4))"
  return 0
}

# get the user name of the administrator running this script
#
# sets the variable USERNAME
#
function get_user {
  if ! [ -z "$USERNAME" ]; then return; fi
  if ! [ -z "$SUDO_USER" ]; then U=${SUDO_USER}; else
    read -r -p "You have accessed root with a non-standard environment. What is your username? [root]? " U
    U=$( echo "$U" |tr 'A-Z' 'a-z' ); [ -z "$U" ] && U=root
  fi
  test -z "$U" && err "A user name is required to make modifications."
  USERNAME="$U"
}

# get yes or no input
#
# requires:
#  $1 variable name (no spaces)
#  $2 prompt
#
# optional:
#  $3 additional option
#
function get_yn {
  test $# -lt 2 && return
  RL=""
  if ! [ -z "$3" ]; then
    while [[ "$RL" != "y" && "$RL" != "n" && "$RL" != "$3" ]]; do get_input RL "$2"; done
  else
    while [[ "$RL" != "y" && "$RL" != "n" ]]; do get_input RL "$2"; done
  fi
  eval "$1='$RL'"
}

# help wrapper
#
function help {
  local SUBJ="$( expand_subject_alias "$( echo "$1" |sed 's/\?//' |tr 'A-Z' 'a-z' )")"; shift
  local VERB=""
  if [ $# -gt 0 ]; then
    VERB="$( expand_verb_alias "$( echo "$1" |sed 's/\?//' |tr 'A-Z' 'a-z' )")"; shift
  fi
  test -z "$VERB" && local HELPER="${SUBJ}_help" || local HELPER="${SUBJ}_${VERB}_help"
  {
    eval ${HELPER} $@ 2>/dev/null
  } || {
    echo "Help section not available for '$SUBJ'."; echo
    usage
  }
  exit 0
}

# first run function to init the configuration store
#
function initialize_configuration {
  test -d $CONF && exit 2
  mkdir -p $CONF/template/patch $CONF/{binary,net,value}
  git init --quiet $CONF
  touch $CONF/{application,constant,environment,file{,-map},hv-{environment,network},hypervisor,location,network,resource,system}
  cd $CONF || err
  printf -- "*\\.swp\nbinary\n" >.gitignore
  git add *
  git commit -a -m'initial commit' >/dev/null 2>&1
  cd - >/dev/null 2>&1
  return 0
}

# convert an ip address to decimal value
#
# SOURCE: http://stackoverflow.com/questions/10768160/ip-address-converter
#
# requires:
#   $1  ip address
#
function ip2dec {
  local a b c d ip=$1
  IFS=. read -r a b c d <<< "$ip"
  printf '%d\n' "$((a * 256 ** 3 + b * 256 ** 2 + c * 256 + d))"
  return 0
}

# add or subtract an arbitrary number of addresses
#   from an ip address
#
# this is explictely designed to ignore subnet boundaries
#   but will always return a valid ip address
#
# requires:
#   $1  ip address
#   $2  integer value (+/- X)
#
function ipadd {
  test $# -eq 2 || return 1
  echo $( dec2ip $(( $( ip2dec $1 ) + $2 )) )
  return 0
}

# convert subnet mask into subnet mask bits
#   source: https://forum.openwrt.org/viewtopic.php?pid=220781#p220781
#
# required
#   $1    W.X.Y.Z (a valid subnet mask)
#
function mask2cdr {
  valid_mask "$1" || return 1
  # Assumes there's no "255." after a non-255 byte in the mask
  local x=${1##*255.}
  set -- 0^^^128^192^224^240^248^252^254^ $(( (${#1} - ${#x})*2 )) ${x%%.*}
  x=${1%%$3*}
  echo $(( $2 + (${#x}/4) ))
  return 0
}

function octal2perm {
  local N="$1" R=r W=w X=x
  if ! [ -z "$2" ]; then local R=s W=s X=t; fi
  if [ $(( $N - 4 )) -ge 0 ]; then N=$(( $N - 4 )); printf -- $R; else printf -- '-'; fi
  if [ $(( $N - 2 )) -ge 0 ]; then N=$(( $N - 2 )); printf -- $W; else printf -- '-'; fi
  if [ $(( $N - 1 )) -ge 0 ]; then N=$(( $N - 1 )); printf -- $X; else printf -- '-'; fi
}

function octal2text {
  if [ -z "$1" ]; then local N="0000"; else local N="$1"; fi
  printf -- "$N" |grep -qE '^[0-7]{3,4}$' || exit 1
  printf -- "$N" |grep -qE '^[0-7]{4}$' || N="0$N"
  octal2perm ${N:0:1} sticky
  octal2perm ${N:1:1}
  octal2perm ${N:2:1}
  octal2perm ${N:3:1}
}

function usage {
  echo "Simple Configuration [Management] System
Manage application/server configurations and base templates across all environments.

Usage $0 (options) component (sub-component|verb) [--option1] [--option2] [...]
              $0 commit [-m 'commit message']
              $0 cancel [--force]
              $0 diff | status

Run commit when complete to finalize changes.

HINT - Follow any command with '?' for more detailed usage information.

Component:
  application
    file [--add|--remove|--list]
  build
  constant
  environment
    application [<environment>] [--list] [<location>]
    application [<environment>] [--name <app_name>] [--add|--remove|--assign-resource|--unassign-resource|--list-resource] [<location>]
    application [<environment>] [--name <app_name>] [--define|--undefine|--list-constant] [<application>]
    constant [--define|--undefine|--list] [<environment>] [<constant>]
  file
    cat [<name>] [--environment <name>] [--vars <system>] [--silent] [--verbose]
    edit [<name>] [--environment <name>]
  help
  hypervisor
    [<name>] [--add-network|--remove-network|--add-environment|--remove-environment|--poll]
  location
    [<name>] [--assign|--unassign|--list]
    [<name>] constant [--define|--undefine|--list] [<environment>] [<constant>]
  network
    <name> ip [--assign|--unassign|--list|--list-available|--list-assigned|--scan]
    <name> ipam [--add-range|--remove-range|--reserve-range|--free-range]
  resource
    <value> [--assign] [<system>]
    <value> [--unassign|--list]
  system
    <value> [--audit|--check|--deploy|--deprovision|--provision|--push-build-scripts|--release|--start-remote-build|--vars]

Verbs - all top level components:
  create
  delete [<name>]
  list
  show [<name>]
  update [<name>]

Options:
  --config <string>   Specify an alternative configuration directory
" >&2
  exit 1
}

# Test an IP address for validity:
# Usage:
#      valid_ip IP_ADDRESS
#      if [[ $? -eq 0 ]]; then echo good; else echo bad; fi
#   OR
#      if valid_ip IP_ADDRESS; then echo good; else echo bad; fi
#
# SOURCE: http://www.linuxjournal.com/content/validating-ip-address-bash-script
#
function valid_ip() {
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS; IFS='.'; ip=($ip); IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

# Test a Network Mask for validity:
# Usage:
#      valid_mask NETMASK
#      if [[ $? -et 0 ]]; then echo good; else echo bad; fi
#   OR
#      if valid_mask NETMASK; then echo good; else echo bad; fi
#
function valid_mask() {
  test $# -eq 1 || return 1
  # extract mask into four numbers
  IFS=. read -r i1 i2 i3 i4 <<< "$1"
  # verify each number is not null
  [[ -z "$i1" || -z "$i2" || -z "$i3" || -z "$i4" ]] && return 1
  # verify each value is numeric only and a positive integer
  test "${1//[^0-9]/}" != "${i1}${i2}${i3}${i4}" && return 1
  # verify any number less than 255 has 255s preceding and 0 following
  [[ $i4 -gt 0 && $i4 -lt 255 && "$i1$i2$i3" != "255255255" ]] && return 1
  [[ $i3 -gt 0 && $i3 -lt 255 && "$i1$i2$i4" != "2552550" ]] && return 1
  [[ $i2 -gt 0 && $i2 -lt 255 && "$i1$i3$i4" != "25500" ]] && return 1
  [[ $i1 -gt 0 && $i1 -lt 255 && "$i2$i3$i4" != "000" ]] && return 1
  # verify each component of the mask is a valid mask
  #   !!FIXME!! i am certain there is a much better way to do this but i could not
  #             come up with it in the time allocated to developing this function
  printf -- " 0 128 192 224 240 248 252 254 255 " |grep -q " $i1 " || return 1
  printf -- " 0 128 192 224 240 248 252 254 255 " |grep -q " $i2 " || return 1
  printf -- " 0 128 192 224 240 248 252 254 255 " |grep -q " $i3 " || return 1
  printf -- " 0 128 192 224 240 248 252 254 255 " |grep -q " $i4 " || return 1
  return 0
}


  #####  ### #######       # #     #  #####   #####  
 #     #  #     #         #  #     # #     # #     # 
 #        #     #        #   #     # #       #       
 #  ####  #     #       #    #     # #        #####  
 #     #  #     #      #      #   #  #             # 
 #     #  #     #     #        # #   #     # #     # 
  #####  ###    #    #          #     #####   ##### 

# cancel changes and switch back to master
#
# optional:
#   --force  force the cancel even if this isn't your branch
#
function cancel_modify {
  # get the running user
  get_user
  # switch directories
  pushd $CONF >/dev/null 2>&1 || err
  # get change count
  L=`git status -s |wc -l 2>/dev/null`
  # make sure we are not on master
  git branch |grep -E '^\*' |grep -q master; M=$?
  if [[ $M -eq 0 && $L -gt 0 ]]; then err "Error -- changes on master branch must be resolved manually."; elif [ $M -eq 0 ]; then return; fi
  # make sure we are on the correct branch...
  git branch |grep -E '^\*' |grep -q $USERNAME
  if [ $? -ne 0 ]; then test "$1" == "--force" && echo "WARNING: These are not your outstanding changes!" || err "Error -- this is not your branch."; fi
  # confirm
  get_yn DF "Are you sure you want to discard outstanding changes (y/n)? "
  if [ "$DF" == "y" ]; then
    git clean -f >/dev/null 2>&1
    git reset --hard >/dev/null 2>&1
    git checkout master >/dev/null 2>&1
    git branch -D $USERNAME >/dev/null 2>&1
  fi
  popd >/dev/null 2>&1
}

# use this for anything that modifies a configuration file to keep changes committed
#
function commit_file {
  test -z "$1" && return
  pushd $CONF >/dev/null 2>&1 || err "Unable to change to '${CONF}' directory"
  while [ $# -gt 0 ]; do git add "$1" >/dev/null 2>&1; shift; done
  if [ `git status -s |wc -l` -ne 0 ]; then
    git commit -m"committing change" >/dev/null 2>&1 || err "Error committing file to repository"
  fi
  popd >/dev/null 2>&1
}

function diff_master {
  pushd $CONF >/dev/null 2>&1
  git diff master
  popd >/dev/null 2>&1
}

# output the status (modified, added, deleted files list)
#
function git_status {
  pushd $CONF >/dev/null 2>&1
  git status
  popd >/dev/null 2>&1
}

# manage changes and locking with branches
#
function start_modify {
  # get the running user
  get_user
  # the current branch must either be master or the name of this user to continue
  cd $CONF || err
  git branch |grep -E '^\*' |grep -q master
  if [ $? -eq 0 ]; then
    git branch $USERNAME >/dev/null 2>&1
    git checkout $USERNAME >/dev/null 2>&1
  else
    git branch |grep -E '^\*' |grep -q $USERNAME || err "Another change is in progress, aborting."
  fi
  return 0
}

# merge changes back into master and remove the branch
#
# optional:
#  -m   commit message
#
function stop_modify {
  # optional commit message
  if [[ "$1" == "-m" && ! -z "$2" ]]; then MSG="${@:2}"; shift 2; else MSG="$USERNAME completed modifications at `date`"; fi
  if [[ "$1" =~ ^-m ]]; then MSG=$( echo $@ |sed 's/^..//g' ); shift; fi
  # get the running user
  get_user
  # switch directories
  pushd $CONF >/dev/null 2>&1 || err
  # check for modifications
  L=`git status -s |wc -l 2>/dev/null`
  # check if the current branch is master
  git branch |grep -E '^\*' |grep -q master
  test $? -eq 0 && M=1 || M=0
  # return if there are no modifications and we are on the master branch
  if [[ $L -eq 0 && $M -eq 1 ]]; then popd >/dev/null 2>&1; return 0; fi
  # error if master was modified
  if [[ $L -ne 0 && $M -eq 1 ]]; then err "The master branch was modified outside of this script.  Please switch to '$CONF' and manually commit or resolve the changes."; fi
  if [ $L -gt 0 ]; then
    # there are modifictions on a branch
    get_yn DF "$L files have been modified. Do you want to review the changes (y/n)? "
    test "$DF" == "y" && git diff
    get_yn DF "Do you want to commit the changes (y/n)? "
    if [ "$DF" != "y" ]; then return 0; fi
    git commit -a -m'final branch commit' >/dev/null 2>&1 || err "Error committing outstanding changes"
  else
    get_yn DF "Do you want to review the changes from master (y/n)? "
    test "$DF" == "y" && git diff master
    get_yn DF "Do you want to commit the changes (y/n)? "
    if [ "$DF" != "y" ]; then return 0; fi
  fi
  if [ `git status -s |wc -l 2>/dev/null` -ne 0 ]; then
    git commit -a -m'final rebase' >/dev/null 2>&1 || err "Error committing rebase"
  fi
  git checkout master >/dev/null 2>&1 || err "Error switching to master"
  git merge --squash $USERNAME >/dev/null 2>&1
  if [ $? -ne 0 ]; then git stash >/dev/null 2>&1; git checkout $USERNAME >/dev/null 2>&1; err "Error merging changes into master."; fi
  git commit -a -m"$MSG" >/dev/null 2>&1
  git branch -D $USERNAME >/dev/null 2>&1
  popd >/dev/null 2>&1
}


    #    ######  ######  #       ###  #####     #    ####### ### ####### #     # 
   # #   #     # #     # #        #  #     #   # #      #     #  #     # ##    # 
  #   #  #     # #     # #        #  #        #   #     #     #  #     # # #   # 
 #     # ######  ######  #        #  #       #     #    #     #  #     # #  #  # 
 ####### #       #       #        #  #       #######    #     #  #     # #   # # 
 #     # #       #       #        #  #     # #     #    #     #  #     # #    ## 
 #     # #       #       ####### ###  #####  #     #    #    ### ####### #     #

function application_create {
  start_modify
  # get user input and validate
  get_input NAME "Name"
  get_input ALIAS "Alias"
  get_input BUILD "Build" --null --options "$( build_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  get_yn CLUSTER "LVS Support (y/n)"
  # validate unique name
  grep -qE "^$NAME," $CONF/application && err "Application already defined."
  grep -qE ",$ALIAS," $CONF/application && err "Alias invalid or already defined."
  # confirm before adding
  printf -- "\nDefining a new application named '$NAME', alias '$ALIAS', installed on the '$BUILD' build"
  [ "$CLUSTER" == "y" ] && printf -- " with " || printf -- " without "
  printf -- "cluster support.\n"
  while [[ "$ACK" != "y" && "$ACK" != "n" ]]; do read -r -p "Is this correct (y/n): " ACK; ACK=$( printf "$ACK" |tr 'A-Z' 'a-z' ); done
  # add
  [ "$ACK" == "y" ] && printf -- "${NAME},${ALIAS},${BUILD},${CLUSTER}\n" >>$CONF/application
  commit_file application
}
function application_create_help { cat <<_EOF
Add a new application to SCS.

Usage: $0 application create

Fields:
  Name - a unique name for the application, such as 'purchase'.
  Alias - a common alias for the application.  this field is not currently utilized.
  Build - the name of the system build this application is installed to.
  LVS Support - whether or not this application can sit behind a load balancer with more than one node.

_EOF
}

function application_delete {
  generic_delete application $1 || return
  # delete from file-map as well
  sed -i "/^[^,]*,$APP\$/d" $CONF/file-map
  commit_file file-map
# !!FIXME!! should also unassign resources
# !!FIXME!! should also undefine constants
}
function application_delete_help { cat <<_EOF
Delete an application and its references from SCS.

Usage: $0 application delete [name]

If the name of the application is not provided as an argument you will be prompted to select it from a list.

_EOF
}

# file [--add|--remove|--list]
#
function application_file {
  APP=""; C="$1"; shift
  while ! [ -z "$C" ]; do case "$C" in
    --add) application_file_add "$APP" $@; break;;
    --remove) application_file_remove "$APP" $@; break;;
    --list) application_file_list "$APP" $@; break;;
    *) if [ -z "$APP" ]; then generic_choose application "$C" APP; else application_file_list "$APP" $@; break; fi;;
  esac; C="$1"; shift; done
}

function application_file_add {
  start_modify
  test -z "$1" && shift
  generic_choose application "$1" APP && shift
  # get the requested file or abort
  generic_choose file "$1" F && shift
  # add the mapping if it does not already exist
  grep -qE "^$F,$APP\$" $CONF/file-map && return
  echo "$F,$APP" >>$CONF/file-map
  commit_file file-map
}

function application_file_list {
  test -z "$1" && shift
  generic_choose application "$1" APP
  NUM=$( grep -E ",$APP\$" $CONF/file-map |wc -l |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} file${S} linked to $APP."
  test $NUM -eq 0 && return
  ( for F in $( grep -E ",$APP\$" $CONF/file-map |awk 'BEGIN{FS=","}{print $1}' ); do
    grep -E "^$F," $CONF/file |awk 'BEGIN{FS=","}{print $1,$2}'
  done ) |sort |column -t |sed 's/^/   /'
}

function application_file_remove {
  start_modify
  test -z "$1" && shift
  generic_choose application "$1" APP && shift
  # get the requested file or abort
  generic_choose file "$1" F && shift
  # confirm
  get_yn RL "Are you sure (y/n)? "
  if [ "$RL" != "y" ]; then return; fi
  # remove the mapping if it exists
  grep -qE "^$F,$APP\$" $CONF/file-map || err "Error - requested file is not associated with $APP."
  sed -i "/^$F,$APP/d" $CONF/file-map
  commit_file file-map
}

function application_list {
  NUM=$( wc -l $CONF/application |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined application${S}."
  test $NUM -eq 0 && return
  awk 'BEGIN{FS=","}{print $1}' $CONF/application |sort |sed 's/^/   /'
}

function application_show {
  test $# -eq 1 || err "Provide the application name"
  APP="$1"
  grep -qE "^$APP," $CONF/application || err "Invalid application"
  IFS="," read -r APP ALIAS BUILD CLUSTER <<< "$( grep -E "^$APP," ${CONF}/application )"
  printf -- "Name: $APP\nAlias: $ALIAS\nBuild: $BUILD\nCluster Support: $CLUSTER\n"
  # retrieve file list
  FILES=( `grep -E ",${APP}\$" ${CONF}/file-map |awk 'BEGIN{FS=","}{print $1}'` )
  # output linked configuration file list
  if [ ${#FILES[*]} -gt 0 ]; then
    printf -- "\nManaged configuration files:\n"
    for ((i=0;i<${#FILES[*]};i++)); do
      grep -E "^${FILES[i]}," $CONF/file |awk 'BEGIN{FS=","}{print $1,$2}'
    done |sort |uniq |column -t |sed 's/^/   /'
  else
    printf -- "\nNo managed configuration files."
  fi
  printf -- '\n'
}

function application_update {
  start_modify
  generic_choose application "$1" APP && shift
  IFS="," read -r APP ALIAS BUILD CLUSTER <<< "$( grep -E "^$APP," ${CONF}/application )"
  get_input NAME "Name" --default "$APP"
  get_input ALIAS "Alias" --default "$ALIAS"
  get_input BUILD "Build" --default "$BUILD" --null --options "$( build_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  get_yn CLUSTER "LVS Support (y/n)"
  sed -i 's/^'$APP',.*/'${NAME}','${ALIAS}','${BUILD}','${CLUSTER}'/' ${CONF}/application
  commit_file application
}


 ######  #     # ### #       ######  
 #     # #     #  #  #       #     # 
 #     # #     #  #  #       #     # 
 ######  #     #  #  #       #     # 
 #     # #     #  #  #       #     # 
 #     # #     #  #  #       #     # 
 ######   #####  ### ####### ######  

# return all applications linked to a build
#
function build_application_list {
  generic_choose build "$1" C 
  grep -E ",$1," ${CONF}/application |awk 'BEGIN{FS=","}{print $1}'
}

function build_create {
  start_modify
  # get user input and validate
  get_input NAME "Build"
  get_input ROLE "Role" --null
  get_input OS "Operating System" --null --options $OSLIST
  get_input ARCH "Architecture" --null --options $OSARCH
  get_input DISK "Disk Size (in GB, Default ${DEF_HDD})" --null --regex '^[1-9][0-9]*$'
  get_input RAM "Memory Size (in MB, Default ${DEF_MEM})" --null --regex '^[1-9][0-9]*$'
  get_input DESC "Description" --nc --null
  # validate unique name
  grep -qE "^$NAME," $CONF/build && err "Build already defined."
  # add
  printf -- "${NAME},${ROLE},${DESC//,/},${OS},${ARCH},${DISK},${RAM}\n" >>$CONF/build
  commit_file build
}

function build_delete {
  generic_delete build $1
}

function build_list {
  NUM=$( wc -l ${CONF}/build |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined build${S}."
  test $NUM -eq 0 && return
  build_list_unformatted |sed 's/^/   /'
}

function build_list_unformatted {
  awk 'BEGIN{FS=","}{print $1}' ${CONF}/build |sort
}

function build_show {
  test $# -eq 1 || err "Provide the build name"
  grep -qE "^$1," ${CONF}/build || err "Unknown build"
  IFS="," read -r NAME ROLE DESC OS ARCH DISK RAM <<< "$( grep -E "^$1," ${CONF}/build )"
  printf -- "Build: $NAME\nRole: $ROLE\nOperating System: $OS-$ARCH\nDisk Size (GB): $DISK\nMemory (MB): $RAM\nDescription: $DESC\n"
  # look up the applications configured for this build
  NUM=$( build_application_list "$1" |wc -l )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo -e "\nThere ${A} ${NUM} linked application${S}."
  if [ $NUM -gt 0 ]; then build_application_list "$1" |sed 's/^/   /'; fi
}

function build_update {
  start_modify
  generic_choose build "$1" C && shift
  IFS="," read -r NAME ROLE DESC OS ARCH DISK RAM <<< "$( grep -E "^$C," ${CONF}/build )"
  get_input NAME "Build" --default "$NAME"
  get_input ROLE "Role" --default "$ROLE" --null
  get_input OS "Operating System" --default "$OS" --null --options $OSLIST
  get_input ARCH "Architecture" --default "$ARCH" --null --options $OSARCH
  get_input DISK "Disk Size (in GB, Default ${DEF_HDD})" --null --regex '^[1-9][0-9]*$' --default "$DISK"
  get_input RAM "Memory Size (in MB, Default ${DEF_MEM})" --null --regex '^[1-9][0-9]*$' --default "$RAM"
  get_input DESC "Description" --default "$DESC" --nc --null
  sed -i 's/^'$C',.*/'${NAME}','${ROLE}','"${DESC//,/}"','${OS}','${ARCH}','${DISK}','${RAM}'/' ${CONF}/build
  commit_file build
}


  #####  ####### #     #  #####  #######    #    #     # ####### 
 #     # #     # ##    # #     #    #      # #   ##    #    #    
 #       #     # # #   # #          #     #   #  # #   #    #    
 #       #     # #  #  #  #####     #    #     # #  #  #    #    
 #       #     # #   # #       #    #    ####### #   # #    #    
 #     # #     # #    ## #     #    #    #     # #    ##    #    
  #####  ####### #     #  #####     #    #     # #     #    #

function constant_create {
  start_modify
  # get user input and validate
  get_input NAME "Name" --nc
  get_input DESC "Description" --nc --null
  # force lowercase for constants
  NAME=$( printf -- "$NAME" |tr 'A-Z' 'a-z' )
  # validate unique name
  grep -qE "^$NAME," $CONF/constant && err "Constant already defined."
  # add
  printf -- "${NAME},${DESC}\n" >>$CONF/constant
  commit_file constant
}

function constant_delete {
  generic_delete constant $1
}

function constant_list {
  NUM=$( wc -l ${CONF}/constant |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined constant${S}."
  test $NUM -eq 0 && return
  awk 'BEGIN{FS=","}{print $1}' ${CONF}/constant |sort |sed 's/^/   /'
}

# combine two sets of variables and values, only including the first instance of duplicates
#
# example on including duplicates from first file only:
#   join -a1 -a2 -t',' <(sort -t',' -k1 1) <(sort -t',' -k1 2) |sed -r 's/^([^,]*,[^,]*),.*/\1/'
#
function constant_list_dedupe {
  if ! [ -f $1 ]; then cat $2; return; fi
  if ! [ -f $2 ]; then cat $1; return; fi
  join -a1 -a2 -t',' <(sort -t',' -k1,1 $1) <(sort -t',' -k1,1 $2) |sed -r 's/^([^,]*,[^,]*),.*/\1/'
}

function constant_show {
  test $# -eq 1 || err "Provide the constant name"
  C="$( printf -- "$1" |tr 'A-Z' 'a-z' )"
  grep -qiE "^$C," ${CONF}/constant || err "Unknown constant"
  IFS="," read -r NAME DESC <<< "$( grep -E "^$C," ${CONF}/constant )"
  printf -- "Name: $NAME\nDescription: $DESC\n"
}

function constant_update {
  start_modify
  generic_choose constant "$1" C && shift
  IFS="," read -r NAME DESC <<< "$( grep -E "^$C," ${CONF}/constant )"
  get_input NAME "Name" --default "$NAME"
  # force lowercase for constants
  NAME=$( printf -- "$NAME" |tr 'A-Z' 'a-z' )
  get_input DESC "Description" --default "$DESC" --null --nc
  sed -i 's/^'$C',.*/'${NAME}','"${DESC}"'/' ${CONF}/constant
  commit_file constant
}


 ####### #     # #     # ### ######  ####### #     # #     # ####### #     # ####### 
 #       ##    # #     #  #  #     # #     # ##    # ##   ## #       ##    #    #    
 #       # #   # #     #  #  #     # #     # # #   # # # # # #       # #   #    #    
 #####   #  #  # #     #  #  ######  #     # #  #  # #  #  # #####   #  #  #    #    
 #       #   # #  #   #   #  #   #   #     # #   # # #     # #       #   # #    #    
 #       #    ##   # #    #  #    #  #     # #    ## #     # #       #    ##    #    
 ####### #     #    #    ### #     # ####### #     # #     # ####### #     #    #

# manipulate applications at a specific environment at a specific location
#
# application [<environment>] [--list] [<location>]
# application [<environment>] [--name <name>] [--add|--remove|--assign-resource|--unassign-resource|--list-resource] [<application>] [<location>]
# application [<environment>] [--name <name>] [--define|--undefine|--list-constant] [<application>]
#
function environment_application {
  # get the requested environment or abort
  generic_choose environment "$1" ENV && shift
  # optionally set the application
  if [ "$1" == "--name" ]; then generic_choose application "$2" APP; shift 2; fi
  C="$1"; shift
  case "$C" in
    --add) environment_application_add $ENV $APP $@;;
    --define) environment_application_define_constant $ENV $APP $@;;
    --undefine) environment_application_undefine_constant $ENV $APP $@;;
    --list-constant) environment_application_list_constant $ENV $APP $@;;
    --assign-resource) environment_application_byname_assign $ENV $APP $@;;
    --unassign-resource) environment_application_byname_unassign $ENV $APP $@;;
    --list-resource) environment_application_byname_list_resource $ENV $APP $@;;
    --remove) environment_application_remove $ENV $APP $@;;
    *) environment_application_list $ENV $@;;
  esac
}

function environment_application_add {
  start_modify
  ENV=$1; shift
  # get the requested application or abort
  generic_choose application "$1" APP && shift
  # get the requested location or abort
  generic_choose location "$1" LOC && shift
  test -f ${CONF}/${LOC}/${ENV} || err "Error - please create $ENV at $LOC first."
  # assign the application
  echo "$APP" >>${CONF}/${LOC}/${ENV}
  touch $CONF/value/$ENV/$APP
  commit_file "${LOC}/${ENV}" $CONF/value/$ENV/$APP
}

function environment_application_define_constant {
  start_modify
  ENV=$1; shift
  # get the requested application or abort
  generic_choose application "$1" APP && shift
  generic_choose constant "$1" C && shift
  # get the value
  if [ -z "$1" ]; then get_input VAL "Value" --nc --null; else VAL="$1"; fi
  # check if constant is already defined
  grep -qE "^$C," ${CONF}/value/$ENV/$APP 2>/dev/null
  if [ $? -eq 0 ]; then
    # already define, update value
    sed -i 's/^'"$C"',.*/'"$C"','"$VAL"'/' ${CONF}/value/$ENV/$APP
  else
    # not defined, add
    printf -- "$C,$VAL\n" >>${CONF}/value/$ENV/$APP
  fi
  commit_file ${CONF}/value/$ENV/$APP
}

function environment_application_undefine_constant {
  start_modify
  ENV=$1; shift
  # get the requested application or abort
  generic_choose application "$1" APP && shift
  generic_choose constant "$1" C
  sed -i '/^'"$C"',.*/d' ${CONF}/value/$ENV/$APP 2>/dev/null
  commit_file ${CONF}/value/$ENV/$APP
}

function environment_application_list_constant {
  ENV=$1; shift
  # get the requested application or abort
  generic_choose application "$1" APP && shift
  test -f $CONF/value/$ENV/$APP && NUM=$( wc -l $CONF/value/$ENV/$APP |awk '{print $1}' ) || NUM=0
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There $A $NUM defined constant$S for $ENV $APP."
  test $NUM -eq 0 && return
  awk 'BEGIN{FS=","}{print $1}' $CONF/value/$ENV/$APP |sort |sed 's/^/   /'
}

function environment_application_byname_assign {
  start_modify
  ENV=$1; shift
  # get the requested application or abort
  generic_choose application "$1" APP && shift
  # get the requested location or abort
  generic_choose location "$1" LOC && shift
  test -f ${CONF}/${LOC}/${ENV} || err "Error - please create $ENV at $LOC first."
  grep -qE "^$APP$" ${CONF}/${LOC}/${ENV} || err "Error - please add $APP to $LOC $ENV before managing it."
  # select an available resource to assign
  generic_choose resource "$1" RES "^(cluster|ha)_ip,.*,not assigned," && shift
  # verify the resource is available for this purpose
  grep -E ",${RES//,/}," $CONF/resource |grep -qE '^(cluster|ha)_ip,.*,not assigned,' || err "Error - invalid or unavailable resource."
  # assign resource, update index
  IFS="," read -r TYPE VAL ASSIGN_TYPE ASSIGN_TO DESC <<< "$( grep -E ",$RES," ${CONF}/resource )"
  sed -i 's/.*,'$RES',.*/'$TYPE','$VAL',application,'$LOC':'$ENV':'$APP','"$DESC"'/' ${CONF}/resource
  commit_file resource
}

function environment_application_byname_unassign {
  start_modify
  ENV=$1; shift
  # get the requested application or abort
  generic_choose application "$1" APP && shift
  # get the requested location or abort
  generic_choose location "$1" LOC && shift
  test -f ${CONF}/${LOC}/${ENV} || err "Error - please create $ENV at $LOC first."
  grep -qE "^$APP$" ${CONF}/${LOC}/${ENV} || err "Error - please add $APP to $LOC $ENV before managing it."
  # select an available resource to unassign
  generic_choose resource "$1" RES ",application,$LOC:$ENV:$APP," && shift
  # verify the resource is available for this purpose
  grep -E ",${RES//,/}," $CONF/resource |grep -qE ",application,$LOC:$ENV:$APP," || err "Error - the provided resource is not assigned to this application."
  # confirm
  get_yn RL "Are you sure (y/n)? "
  if [ "$RL" != "y" ]; then return; fi
  # assign resource, update index
  IFS="," read -r TYPE VAL ASSIGN_TYPE ASSIGN_TO DESC <<< "$( grep -E ",$RES," ${CONF}/resource )"
  sed -i 's/.*,'$RES',.*/'$TYPE','$VAL',,not assigned,'"$DESC"'/' ${CONF}/resource
  commit_file resource
}

function environment_application_byname_list_resource {
  ENV=$1; shift
  # get the requested application or abort
  generic_choose application "$1" APP && shift
  # get the requested location or abort
  generic_choose location "$1" LOC && shift
  test -f ${CONF}/${LOC}/${ENV} || err "Error - please create $ENV at $LOC first."
  grep -qE "^$APP$" ${CONF}/${LOC}/${ENV} || err "Error - please add $APP to $LOC $ENV before managing it."
  resource_list ",application,$LOC:$ENV:$APP,"
}

# list applications at an environment
#
# required:
#  $1  environment
#
function environment_application_list {
  ENV=$1; shift
  # get the requested location or abort
  generic_choose location "$1" LOC && shift
  test -f ${CONF}/${LOC}/${ENV} && NUM=$( wc -l ${CONF}/${LOC}/${ENV} |awk '{print $1}' ) || NUM=0
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined application${S} at $LOC $ENV."
  test $NUM -eq 0 && return
  sort ${CONF}/${LOC}/${ENV} |sed 's/^/   /'
}

function environment_application_remove {
  start_modify
  ENV=$1; shift
  generic_choose application "$1" APP && shift
  # get the requested location or abort
  generic_choose location "$1" LOC && shift
  test -f ${CONF}/${LOC}/${ENV} && NUM=$( wc -l ${CONF}/${LOC}/${ENV} |awk '{print $1}' ) || NUM=0
  printf -- "Removing $APP from $LOC $ENV, deleting all configurations, files, resources, constants, et cetera...\n"
  get_yn RL "Are you sure (y/n)? "; test "$RL" != "y" && return
  # unassign the application
  sed -i "/^$APP\$/d" $CONF/$LOC/$ENV
  # so... this says it's going to unassign resources and whatnot.  we should actually do that here...
  commit_file $LOC/$ENV
}

# manage environment constants
#
# constant [--define|--undefine|--list]
function environment_constant {
  case "$1" in
    --define) environment_constant_define ${@:2};;
    --undefine) environment_constant_undefine ${@:2};;
    *) environment_constant_list ${@:2};;
  esac
}

# define a constant for an environment
#
function environment_constant_define {
  start_modify
  generic_choose environment "$1" ENV && shift
  generic_choose constant "$1" C && shift
  if [ -z "$1" ]; then get_input VAL "Value" --nc --null; else VAL="$1"; fi
  # check if constant is already defined
  grep -qE "^$C," ${CONF}/value/$ENV/constant
  if [ $? -eq 0 ]; then
    # already define, update value
    sed -i s$'\001''^'"$C"',.*'$'\001'"$C"','"${VAL//&/\&}"$'\001' ${CONF}/value/$ENV/constant
  else
    # not defined, add
    printf -- "$C,$VAL\n" >>${CONF}/value/$ENV/constant
  fi
  commit_file ${CONF}/value/$ENV/constant
}

# undefine a constant for an environment
#
function environment_constant_undefine {
  start_modify
  generic_choose environment "$1" ENV && shift
  generic_choose constant "$1" C
  sed -i '/^'"$C"',.*/d' ${CONF}/value/$ENV/constant
  commit_file ${CONF}/value/$ENV/constant
}

function environment_constant_list {
  generic_choose environment "$1" ENV && shift
  NUM=$( wc -l ${CONF}/value/$ENV/constant |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined constant${S} for $ENV."
  test $NUM -eq 0 && return
  awk 'BEGIN{FS=","}{print $1}' ${CONF}/value/$ENV/constant |sed 's/^/   /'
}

function environment_create {
  start_modify
  # get user input and validate
  get_input NAME "Name"
  get_input ALIAS "Alias (One Letter, Unique)"
  get_input DESC "Description" --nc --null
  # force uppercase for site alias
  ALIAS=$( printf -- "$ALIAS" | tr 'a-z' 'A-Z' )
  # validate unique name and alias
  grep -qE "^$NAME," ${CONF}/environment && err "Environment already defined."
  grep -qE ",$ALIAS," ${CONF}/environment && err "Environment alias already in use."
  # add
  mkdir -p $CONF/template/patch/${NAME} $CONF/{binary,value}/${NAME} >/dev/null 2>&1
  printf -- "${NAME},${ALIAS},${DESC}\n" >>${CONF}/environment
  touch $CONF/value/${NAME}/constant
  commit_file environment
}

function environment_delete {
  generic_delete environment $1 || return
  cd $CONF >/dev/null 2>&1 || return
  test -d binary/$1 && git rm -r binary/$1
  test -d value/$1 && git rm -r value/$1
  sed -i "/^$1,/d" $CONF/hv-environment
  commit_file hv-environment
}

function environment_list {
  NUM=$( wc -l ${CONF}/environment |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined environment${S}."
  test $NUM -eq 0 && return
  environment_list_unformatted |sed 's/^/   /'
}

function environment_list_unformatted {
  awk 'BEGIN{FS=","}{print $1}' ${CONF}/environment |sort
}

function environment_show {
  test $# -eq 1 || err "Provide the environment name"
  grep -qE "^$1," ${CONF}/environment || err "Unknown environment" 
  IFS="," read -r NAME ALIAS DESC <<< "$( grep -E "^$1," ${CONF}/environment )"
  printf -- "Name: $NAME\nAlias: $ALIAS\nDescription: $DESC"
  # also show installed locations
  NUM=$( find $CONF -name $NAME -type f |grep -vE '(binary|template|value)' |wc -l )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo -e "\n\nThere ${A} ${NUM} linked location${S}."
  if [ $NUM -gt 0 ]; then
    find $CONF -name $NAME -type f |grep -vE '(binary|template|value)' |sed -r 's%'$CONF'/(.{3}).*%   \1%'
  fi
  printf -- '\n'
}

function environment_update {
  start_modify
  generic_choose environment "$1" C && shift
  IFS="," read -r NAME ALIAS DESC <<< "$( grep -E "^$C," ${CONF}/environment )"
  get_input NAME "Name" --default "$NAME"
  get_input ALIAS "Alias (One Letter, Unique)" --default "$ALIAS"
  get_input DESC "Description" --default "$DESC" --null --nc
  # force uppercase for site alias
  ALIAS=$( printf -- "$ALIAS" | tr 'a-z' 'A-Z' )
  sed -i 's/^'$C',.*/'${NAME}','${ALIAS}','"${DESC}"'/' ${CONF}/environment
  # handle rename
  if [ "$NAME" != "$C" ]; then
    pushd ${CONF} >/dev/null 2>&1
    test -d template/patch/$C && git mv template/patch/$C template/patch/$NAME >/dev/null 2>&1
    test -d value/$C && git mv value/$C value/$NAME >/dev/null 2>&1
    for L in $( awk 'BEGIN{FS=","}{print $1}' ${CONF}/location ); do
      test -d $L/$C && git mv $L/$C $L/$NAME >/dev/null 2>&1
    done
    popd >/dev/null 2>&1
  fi
  commit_file environment
}


 ####### ### #       ####### 
 #        #  #       #       
 #        #  #       #       
 #####    #  #       #####   
 #        #  #       #       
 #        #  #       #       
 #       ### ####### ####### 

# output a (text) file contents to stdout
#
# cat [<name>] [--environment <name>] [--vars <system>] [--silent] [--verbose]
#
function file_cat {
  # get file name to show
  generic_choose file "$1" C && shift
  # set defaults
  local EN="" PARSE="" SILENT=0 VERBOSE=0
  # get any other provided options
  while [ $# -gt 0 ]; do case $1 in
    --environment) EN="$2"; shift;;
    --vars) PARSE="$2"; shift;;
    --silent) SILENT=1;;
    --verbose) VERBOSE=1;;
    *) usage;;
  esac; shift; done
  # validate system name
  if ! [ -z "$PARSE" ]; then grep -qE "^$PARSE," ${CONF}/system || err "Unknown system"; fi
  # load file data
  IFS="," read -r NAME PTH TYPE OWNER GROUP OCTAL TARGET DESC <<< "$( grep -E "^$C," ${CONF}/file )"
  # only handle plain text files here
  if [ "$TYPE" != "file" ]; then err "Invalid type for cat: $TYPE"; fi
  # create the temporary directory
  mkdir -p $TMP
  # copy the base template to the path
  cat $CONF/template/$C >$TMP/$C
  # optionally patch the file for the environment
  if ! [ -z "$EN" ]; then
    # apply environment patch for this file if one exists
    if [ -f $CONF/template/$EN/$C ]; then
      patch -p0 $TMP/$C <$CONF/template/$EN/$C >/dev/null 2>&1
      test $? -eq 0 || err "Error applying $EN patch to $C."
    fi
  fi
  # optionally replace variables
  if ! [ -z "$PARSE" ]; then
    # generate the system variables
    system_vars $PARSE >$TMP/systemvars.$$
    # process template variables
    parse_template $TMP/$C $TMP/systemvars.$$ $SILENT $VERBOSE
    if [ $? -ne 0 ]; then test $SILENT -ne 1 && echo "Error parsing template" >&2; return 1; fi
  fi
  # output the file and remove it
  cat $TMP/$C
  rm -f $TMP/$C $TMP/systemvars.$$
}
function file_cat_help {
  echo "help tbd"
}

# create a new file definition
#
# file types:
#   file          a regular text file
#   symlink       a symbolic link
#   binary        a non-text file
#   copy          a regular file that is not stored here. it will be copied by this application from
#                   another location when it is deployed.  when auditing a remote system files of type
#                   'copy' will only be audited for permissions and existence.
#   delete        ensure a file or directory DOES NOT EXIST on the target system.
#   download      a regular file that is not stored here. it will be retrieved by the remote system
#                   when it is deployed.  when auditing a remote system files of type 'download' will
#                   only be audited for permissions and existence.
#   directory     a directory (useful for enforcing permissions)
#
function file_create {
  start_modify
  # initialize optional values
  TARGET=""
  # get user input and validate
  get_input NAME "Name (for reference)"
  get_input TYPE "Type" --options file,directory,symlink,binary,copy,delete,download --default file
  if [ "$TYPE" == "symlink" ]; then
    get_input TARGET "Link Target" --nc
  elif [ "$TYPE" == "copy" ]; then
    get_input TARGET "Local or Remote Path" --nc
  elif [ "$TYPE" == "download" ]; then
    get_input TARGET "Remote Path/URL" --nc
  fi
  if [ "$TYPE" == "delete" ]; then
    get_input PTH "Exact path to delete on target system" --nc
  else
    get_input PTH "Full Path (for deployment)" --nc
  fi
  get_input DESC "Description" --nc --null
  if [ "$TYPE" == "delete" ]; then
    OWNER=root; GROUP=root; OCTAL=644
  else
    get_input OWNER "Permissions - Owner" --default root
    get_input GROUP "Permissions - Group" --default root
    get_input OCTAL "Permissions - Octal (e.g. 0755)" --default 0644 --regex '^[0-7]{3,4}$'
  fi
  # validate unique name
  grep -qE "^$NAME," ${CONF}/file && err "File already defined."
  # add
  printf -- "${NAME},${PTH},${TYPE},${OWNER},${GROUP},${OCTAL},${TARGET},${DESC}\n" >>${CONF}/file
  # create base file
  if [ "$TYPE" == "file" ]; then
    pushd $CONF >/dev/null 2>&1 || err "Unable to change to '${CONF}' directory"
    test -d template || mkdir template >/dev/null 2>&1
    touch template/${NAME}
    git add template/${NAME} >/dev/null 2>&1
    git commit -m"template created by ${USERNAME}" file template/${NAME} >/dev/null 2>&1 || err "Error committing new template to repository"
    popd >/dev/null 2>&1
  elif [ "$TYPE" == "binary" ]; then
    printf -- "\nPlease copy the binary file to: $CONF/binary/<environment>/$NAME\n"
  else
    commit_file file
  fi
}

function file_delete {
  start_modify
  generic_choose file "$1" C && shift
  printf -- "WARNING: This will remove any templates and stored configurations in all environments for this file!\n"
  get_yn RL "Are you sure (y/n)? "
  if [ "$RL" == "y" ]; then
    sed -i '/^'$C',/d' ${CONF}/file
    sed -i '/^'$C',/d' ${CONF}/file-map
    pushd $CONF >/dev/null 2>&1
    find template/ -type f -name $C -exec git rm -f {} \; >/dev/null 2>&1
    git add file file-map >/dev/null 2>&1
    git commit -m"template removed by ${USERNAME}" >/dev/null 2>&1 || err "Error committing removal to repository"
    find binary/ -type f -name $C -exec rm -f {} \; >/dev/null 2>&1
    popd >/dev/null 2>&1
  fi
}

# general file editing function for both templates and applied template instances
#
# optional:
#   $1                     name of the template to edit
#   --environment <name>   edit or create an instance of a template for an environment
#
function file_edit {
  start_modify
  generic_choose file "$1" C && shift
  # load file data
  IFS="," read -r NAME PTH TYPE OWNER GROUP OCTAL TARGET DESC <<< "$( grep -E "^$C," ${CONF}/file )"
  # only generic files can actually be edited
  if [ "$TYPE" != "file" ]; then err "Can not edit file of type '$TYPE'"; fi
  if [[ ! -z "$1" && "$1" == "--environment" ]]; then
    generic_choose environment "$2" ENV
    # put the template in a temporary folder and patch it, if a patch exists already
    mkdir -m0700 -p $TMP
    cat $CONF/template/$C >$TMP/$C
    mkdir -p $CONF/template/$ENV >/dev/null 2>&1
    if [ -s $CONF/template/$ENV/$C ]; then
      patch -p0 $TMP/$C <$CONF/template/$ENV/$C || err "Unable to patch template!"
      cat $TMP/$C >$TMP/${C}.ORIG
      sleep 1
    else
      cat $CONF/template/$C >$TMP/$C.ORIG
    fi
    # open the patched file for editing
    vim $TMP/$C
    wait
    # do nothing further if there were no changes made
    if [ `md5sum $TMP/$C{.ORIG,} 2>/dev/null |cut -d' ' -f1 |uniq |wc -l` -eq 1 ]; then
      echo "No changes were made."; exit 0
    fi
    # generate a new patch file against the original template
    diff -c $CONF/template/$C $TMP/$C >$TMP/$C.patch
    # ensure the original patch exists
    test ! -f $CONF/template/$ENV/$C && touch $CONF/template/$ENV/$C
    # confirm changes if this isn't a new patch
    echo -e "Please confirm the change to the patch:\n"
    diff -c $CONF/template/$ENV/$C $TMP/$C.patch
    echo -e "\n\n"
    get_yn Q "Look OK? (y/n)" 
    test "$Q" != "y" && err "Aborted!"
    # write the new patch file
    cat $TMP/$C.patch >$CONF/template/$ENV/$C
    echo "Wrote $( wc -c $CONF/template/$ENV/$C |cut -d' ' -f1 ) bytes to $ENV/$C."
    # commit
    pushd $CONF >/dev/null 2>&1
    git add template/$ENV/$C >/dev/null 2>&1
    popd >/dev/null 2>&1
    commit_file template/$ENV/$C
  else
    # create a copy of the template to edit
    cat $CONF/template/$C >/tmp/app-config.$$
    vim /tmp/app-config.$$
    wait
    # prompt for verification
    echo -e "Please review the change:\n"
    diff -c $CONF/template/$C /tmp/app-config.$$
    echo
    get_yn RL "Proceed with change (y/n)? "
    if [ "$RL" != "y" ]; then rm -f /tmp/app-config.$$; return; fi
    # apply patches to the template for each environment with a patch and verify the apply successfully
    echo "Validating template instances..."
    NEWPATCHES=(); NEWENVIRON=()
    pushd $CONF/template >/dev/null 2>&1
    for E in $( find . -mindepth 2 -type f -name $C -printf '%h\n' |sed 's/^\.\///' ); do
      echo -n "${E}... "
      cat /tmp/app-config.$$ >/tmp/app-config.$$.1
      patch -p0 /tmp/app-config.$$.1 <$E/$C >/dev/null 2>&1
      if [ $? -ne 0 ]; then
        echo -e "FAILED\n\nThis patch will not apply successfully to $E."
        get_yn RL "Would you like to try to resolve the patch manually (y/n)? "
        if [ "$RL" != "y" ]; then rm -f /tmp/app-config.$${,.1,.rej}; return; fi
        # patch the original file with the environment patch and launch vimdiff
        echo -e "\nThe LEFT file is your updated template. The RIGHT file is the previous environment configuration. Edit the RIGHT file."
        echo "The LEFT file is your updated template. The RIGHT file is the previous environment configuration. Edit the RIGHT file."
        echo "The LEFT file is your updated template. The RIGHT file is the previous environment configuration. Edit the RIGHT file."
        cat /tmp/app-config.$$ >/tmp/app-config.$$.1
        cat $CONF/template/$C >/tmp/app-config.$$.2
        patch -p0 /tmp/app-config.$$.2 <$E/$C >/dev/null 2>&1
        test $? -ne 0 && err "ERROR -- THE ORIGINAL PATCH IS INVALID!"
        sleep 3
        vimdiff /tmp/app-config.$$.1 /tmp/app-config.$$.2
        wait
        echo -e "Please review the change:\n"
        diff -c $CONF/template/$C /tmp/app-config.$$.2
        echo; get_yn RL "Proceed with change (y/n)? "
        if [ "$RL" != "y" ]; then rm -f /tmp/app-config.$$*; return; fi
        # stage the new environment patch file
        diff -c /tmp/app-config.$$ /tmp/app-config.$$.2 >/tmp/app-config.$$.$E
        NEWENVIRON[${#NEWENVIRON[*]}]="$E"
        NEWPATCHES[${#NEWPATCHES[*]}]="/tmp/app-config.$$.$E"
      fi
      echo "OK"
    done
    # everything checks out, apply change
    cat /tmp/app-config.$$ >$CONF/template/$C
    # process any staged environment patch updates
    for ((i=0;i<${#NEWPATCHES[*]};i++)); do
      cat ${NEWPATCHES[i]} >${NEWENVIRON[i]}/$C
    done
    popd >/dev/null 2>&1
    pushd ${CONF} >/dev/null 2>&1
    if [ `git status -s template/${C} |wc -l` -ne 0 ]; then
      git commit -m"template updated by ${USERNAME}" template/${C} >/dev/null 2>&1 || err "Error committing template change"
    fi
    popd >/dev/null 2>&1
  fi
}
function file_edit_help {
  echo "HELP NOT AVAILABLE -- YOU ARE ON YOUR OWN"
}

function file_list {
  NUM=$( wc -l ${CONF}/file |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined file${S}."
  test $NUM -eq 0 && return
  awk 'BEGIN{FS=","}{print $1,$2}' ${CONF}/file |sort |column -t |sed 's/^/   /'
}

# show file details
#
# storage format (brief):
#   name,path,type,owner,group,octal,target,description
#
function file_show {
  test $# -eq 1 || err "Provide the file name"
  grep -qE "^$1," ${CONF}/file || err "Unknown file" 
  IFS="," read -r NAME PTH TYPE OWNER GROUP OCTAL TARGET DESC <<< "$( grep -E "^$1," ${CONF}/file )"
  if [ "$TYPE" == "symlink" ]; then
    printf -- "Name: $NAME\nType: $TYPE\nPath: $PTH -> $TARGET\nPermissions: $( octal2text $OCTAL ) $OWNER $GROUP\nDescription: $DESC"
  elif [ "$TYPE" == "copy" ]; then
    printf -- "Name: $NAME\nType: $TYPE\nPath: $PTH copy of $TARGET\nPermissions: $( octal2text $OCTAL ) $OWNER $GROUP\nDescription: $DESC"
  elif [ "$TYPE" == "download" ]; then
    printf -- "Name: $NAME\nType: $TYPE\nPath: $PTH download from $TARGET\nPermissions: $( octal2text $OCTAL ) $OWNER $GROUP\nDescription: $DESC"
  elif [ "$TYPE" == "delete" ]; then
    printf -- "Name: $NAME\nType: $TYPE\nRemove: $PTH\nDescription: $DESC"
  else
    printf -- "Name: $NAME\nType: $TYPE\nPath: $PTH\nPermissions: $( octal2text $OCTAL ) $OWNER $GROUP\nDescription: $DESC"
    [ "$TYPE" == "file" ] && printf -- "\nSize: `stat -c%s $CONF/template/$NAME` bytes"
#    [ "$TYPE" == "binary" ] && printf -- "\nSize: `stat -c%s $CONF/binary/$NAME` bytes"
  fi
  printf -- '\n'
}

function file_update {
  start_modify
  generic_choose file "$1" C && shift
  IFS="," read -r NAME PTH T OWNER GROUP OCTAL TARGET DESC <<< "$( grep -E "^$C," ${CONF}/file )"
  get_input NAME "Name (for reference)" --default "$NAME"
  get_input TYPE "Type" --options file,directory,symlink,binary,copy,delete,download --default "$T"
  if [ "$TYPE" == "symlink" ]; then
    get_input TARGET "Link Target" --nc --default "$TARGET"
  elif [ "$TYPE" == "copy" ]; then
    get_input TARGET "Local or Remote Path" --nc --default "$TARGET"
  elif [ "$TYPE" == "download" ]; then
    get_input TARGET "Remote Path/URL" --nc --default "$TARGET"
  fi
  if [ "$TYPE" == "delete" ]; then
    get_input PTH "Exact path to delete on target system" --default "$PTH" --nc
  else
    get_input PTH "Full Path (for deployment)" --default "$PTH" --nc
  fi
  get_input DESC "Description" --default "$DESC" --null --nc
  if [ "$TYPE" != "delete" ]; then
    get_input OWNER "Permissions - Owner" --default "$OWNER"
    get_input GROUP "Permissions - Group" --default "$GROUP"
    get_input OCTAL "Permissions - Octal (e.g. 0755)" --default "$OCTAL" --regex '^[0-7]{3,4}$'
  fi
  if [ "$NAME" != "$C" ]; then
    # validate unique name
    grep -qE "^$NAME," ${CONF}/file && err "File already defined."
    # move file
    pushd ${CONF} >/dev/null 2>&1
    if [ "$TYPE" == "file" ]; then
      for DIR in `find template/ -type f -name $C -exec dirname {} \\;`; do
        git mv $DIR/$C $DIR/$NAME >/dev/null 2>&1
      done
    elif [ "$TYPE" == "binary" ]; then
      for DIR in `find binary/ -type f -name $C -exec dirname {} \\;`; do
        mv $DIR/$C $DIR/$NAME >/dev/null 2>&1
      done
    fi
    popd >/dev/null 2>&1
    # update map
    sed -ri 's%^'$C',(.*)%'${NAME}',\1%' ${CONF}/file-map
  fi
  sed -i "s%^$C,.*%$NAME,$PTH,$TYPE,$OWNER,$GROUP,$OCTAL,$TARGET,$DESC%" $CONF/file
  # if type changed from "file" to something else, delete the template
  if [[ "$T" == "file" && "$TYPE" != "file" ]]; then
    pushd $CONF >/dev/null 2>&1
    find template/ -type f -name $C -exec git rm {} \; >/dev/null 2>&1
    git commit -m"template removed by ${USERNAME}" >/dev/null 2>&1
    popd >/dev/null 2>&1
  fi
  commit_file file file-map
}


 #       #######  #####     #    ####### ### ####### #     # 
 #       #     # #     #   # #      #     #  #     # ##    # 
 #       #     # #        #   #     #     #  #     # # #   # 
 #       #     # #       #     #    #     #  #     # #  #  # 
 #       #     # #       #######    #     #  #     # #   # # 
 #       #     # #     # #     #    #     #  #     # #    ## 
 ####### #######  #####  #     #    #    ### ####### #     #

function location_create {
  start_modify
  # get user input and validate
  get_input CODE "Location Code (three characters)"
  test `printf -- "$CODE" |wc -c` -eq 3 || err "Error - the location code must be exactly three characters."
  get_input NAME "Name" --nc
  get_input DESC "Description" --nc --null
  # validate unique name
  grep -qE "^$CODE," $CONF/location && err "Location already defined."
  # add
  printf -- "${CODE},${NAME},${DESC}\n" >>$CONF/location
  commit_file location
}

function location_delete {
  generic_delete location $1
}

#  [<name>] [--assign|--unassign|--list]
#  [<name>] constant [--define|--undefine|--list] [<environment>] [<constant>]
#
function location_environment {
  # get the requested location or abort
  generic_choose location "$1" LOC && shift
  # get the command to process
  C="$1"; shift
  case "$C" in
    --assign) location_environment_assign $LOC $@;;
    --unassign) location_environment_unassign $LOC $@;;
    constant) location_environment_constant $LOC $@;;
    *) location_environment_list $LOC $@;;
  esac
}

function location_environment_assign {
  start_modify
  LOC=$1; shift
  # get the requested environment or abort
  generic_choose environment "$1" ENV && shift
  # assign the environment
  pushd $CONF >/dev/null 2>&1
  touch ${LOC}/$ENV
  git add ${LOC}/$ENV >/dev/null 2>&1
  git commit -m"${USERNAME} added $ENV to $LOC" ${LOC}/$ENV >/dev/null 2>&1 || err "Error committing change to the repository"
  popd >/dev/null 2>&1
}

function location_environment_constant {
  LOC=$1; shift
  # get the command to process
  C="$1"; shift
  # get the requested environment or abort
  generic_choose environment "$1" ENV && shift
  case "$C" in
    --define) location_environment_constant_define "$LOC" "$ENV" $@;;
    --undefine) location_environment_constant_undefine "$LOC" "$ENV" $@;;
    *) location_environment_constant_list "$LOC" "$ENV";; 
  esac
}

function location_environment_constant_define {
  LOC="$1"; ENV="$2"; shift 2
  start_modify
  if ! [ -f $CONF/value/$LOC/$ENV ]; then mkdir -p $CONF/value/$LOC; touch $CONF/value/$LOC/$ENV; fi
  generic_choose constant "$1" C && shift
  if [ -z "$1" ]; then get_input VAL "Value" --nc --null; else VAL="$1"; fi
  # check if constant is already defined
  grep -qE "^$C," $CONF/value/$LOC/$ENV
  if [ $? -eq 0 ]; then
    # already define, update value
    sed -i s$'\001''^'"$C"',.*'$'\001'"$C"','"${VAL//&/\&}"$'\001' $CONF/value/$LOC/$ENV
  else
    # not defined, add
    printf -- "$C,$VAL\n" >>$CONF/value/$LOC/$ENV
  fi
  commit_file $CONF/value/$LOC/$ENV
}

function location_environment_constant_undefine {
  start_modify
  generic_choose constant "$1" C
  sed -i '/^'"$C"',.*/d' $CONF/value/$1/$2
  commit_file $CONF/value/$1/$2
}

function location_environment_constant_list {
  LOC="$1"; ENV="$2"; shift 2
  test -f $CONF/value/$LOC/$ENV && NUM=$( wc -l $CONF/value/$LOC/$ENV |awk '{print $1}' ) || NUM=0
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined constant${S} for $LOC $ENV."
  test $NUM -eq 0 && return
  awk 'BEGIN{FS=","}{print $1}' $CONF/value/$LOC/$ENV |sort |sed 's/^/   /'
}

# list environments at a location
#
# required:
#  $1 location
#
function location_environment_list {
  test -d ${CONF}/$1 && NUM=$( find ${CONF}/$1/ -type f |sed 's%'"${CONF}/$1"'/%%' |grep -vE '^(\.|template|network|$)' |wc -l ) || NUM=0
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined environment${S} at $1."
  test $NUM -eq 0 && return
  find ${CONF}/$1/ -type f |sed 's%'"${CONF}/$1"'/%%' |grep -vE '^(\.|template|network|$)' |sort |sed 's/^/   /'
}

function location_environment_unassign {
  start_modify
  LOC=$1; shift
  # get the requested environment or abort
  generic_choose environment "$1" ENV && shift
  printf -- "Removing $ENV from location $LOC, deleting all configurations, files, resources, constants, et cetera...\n"
  get_yn RL "Are you sure (y/n)? "; test "$RL" != "y" && return
  # unassign the environment
  pushd $CONF >/dev/null 2>&1
  test -f ${LOC}/$ENV && git rm -rf ${LOC}/$ENV >/dev/null 2>&1
  git commit -m"${USERNAME} removed $ENV from $LOC" >/dev/null 2>&1 || err "Error committing change to the repository"
  popd >/dev/null 2>&1
}

function location_list {
  NUM=$( wc -l ${CONF}/location |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined location${S}."
  test $NUM -eq 0 && return
  location_list_unformatted |sed 's/^/   /'
}

function location_list_unformatted {
  awk 'BEGIN{FS=","}{print $1}' ${CONF}/location |sort
}

function location_show {
  test $# -eq 1 || err "Provide the location name"
  grep -qE "^$1," ${CONF}/location || err "Unknown location" 
  IFS="," read -r CODE NAME DESC <<< "$( grep -E "^$1," ${CONF}/location )"
  printf -- "Code: $CODE\nName: $NAME\nDescription: $DESC\n"
}

function location_update {
  start_modify
  generic_choose location "$1" C && shift
  IFS="," read -r CODE NAME DESC <<< "$( grep -E "^$C," ${CONF}/location )"
  get_input CODE "Location Code (three characters)" --default "$CODE"
  test `printf -- "$CODE" |wc -c` -eq 3 || err "Error - the location code must be exactly three characters."
  get_input NAME "Name" --nc --default "$NAME"
  get_input DESC "Description" --nc --null --default "$DESC"
  sed -i 's/^'$C',.*/'${CODE}','"${NAME}"','"${DESC}"'/' ${CONF}/location
  # handle rename
  if [ "$CODE" != "$C" ]; then
    pushd $CONF >/dev/null 2>&1
    test -d $C && git mv $C $CODE >/dev/null 2>&1
    sed -i 's/^'$C',/'$CODE',/' network
    popd >/dev/null 2>&1
  fi
  commit_file location
}


 #     # ####### ####### #     # ####### ######  #    # 
 ##    # #          #    #  #  # #     # #     # #   #  
 # #   # #          #    #  #  # #     # #     # #  #   
 #  #  # #####      #    #  #  # #     # ######  ###    
 #   # # #          #    #  #  # #     # #   #   #  #   
 #    ## #          #    #  #  # #     # #    #  #   #  
 #     # #######    #     ## ##  ####### #     # #    #

# network functions
#
# <name> ip [--assign|--unassign|--list|--list-available|--list-assigned]
# <name> ipam [--add-range|--remove-range|--reserve-range|--free-range]
function network_byname {
  # input validation
  test $# -gt 0 || err "Provide the network name (loc-zone-alias)"
  test `printf -- "$1" |sed 's/[^-]*//g' |wc -c` -eq 2 || err "Invalid format. Please ensure you are entering 'location-zone-alias'."
  grep -qE "^${1//-/,}," ${CONF}/network || err "Unknown network"
  # function
  case "$2" in
    ip) network_ip $1 ${@:3};;
    ipam) network_ipam $1 ${@:3};;
    *) network_show $1;;
  esac
}

function network_create {
  start_modify
  # get user input and validate
  get_input LOC "Location Code" --options "$( location_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  get_input ZONE "Network Zone" --options core,edge
  get_input ALIAS "Site Alias"
  # validate unique name
  grep -qE "^$LOC,$ZONE,$ALIAS," $CONF/network && err "Network already defined."
  get_input DESC "Description" --nc --null
  while ! $(valid_ip "$NET"); do get_input NET "Network"; done
  get_input BITS "CIDR Mask (Bits)" --regex '^[0-9]+$'
  while ! $(valid_mask "$MASK"); do get_input MASK "Subnet Mask" --default $(cdr2mask $BITS); done
  get_input GW "Gateway Address" --null
  get_input DNS "DNS Server Address" --null
  get_input NTP "NTP Server Address" --null
  get_input VLAN "VLAN Tag/Number" --null
  get_yn BUILD "Use network for system builds (y/n)? "
  if [ "$BUILD" == "y" ]; then
    get_yn DEFAULT_BUILD "Should this be the *default* build network at the location (y/n)? "
    # when adding a new default build network make sure we prompt if another exists, since it will be replaced
    if [[ "$DEFAULT_BUILD" == "y" && `grep -E ',y$' ${CONF}/${LOC}/network |grep -vE "^${ZONE},${ALIAS}," |wc -l` -ne 0 ]]; then
      get_yn RL "WARNING: Another default build network exists at this site. Are you sure you want to replace it (y/n)? "
      if [ "$RL" != "y" ]; then echo "...aborted!"; return; fi
    fi
    get_input REPO_ADDR "Repository IP or Host Name" --nc
    get_input REPO_PATH "Repository Local Path" --nc
    get_input REPO_URL "Repository URL" --nc
  else
    DEFAULT_BUILD="n"
    REPO_ADDR=""
    REPO_PATH=""
    REPO_URL=""
  fi
  # add
  #   --format: location,zone,alias,network,mask,cidr,gateway_ip,dns_ip,vlan,description,repo_address,repo_fs_path,repo_path_url,build,default-build,ntp_ip\n
  printf -- "${LOC},${ZONE},${ALIAS},${NET},${MASK},${BITS},${GW},${DNS},${VLAN},${DESC},${REPO_ADDR},${REPO_PATH},${REPO_URL},${BUILD},${DEFAULT_BUILD},${NTP}\n" >>$CONF/network
  test ! -d ${CONF}/${LOC} && mkdir ${CONF}/${LOC}
  #   --format: zone,alias,network/cidr,build,default-build\n
  if [[ "$DEFAULT_BUILD" == "y" && `grep -E ',y$' ${CONF}/${LOC}/network |grep -vE "^${ZONE},${ALIAS}," |wc -l` -gt 0 ]]; then
    # get the current default network (if any) and update it
    IFS="," read -r Z A DISC <<< "$( grep -E ',y$' ${CONF}/${LOC}/network |grep -vE "^${ZONE},${ALIAS}," )"
    sed -ri 's%^('${LOC}','${Z}','${A}',.*),y,y$%\1,y,n%' ${CONF}/network
    sed -i 's/,y$/,n/' ${CONF}/${LOC}/network
  fi
  printf -- "${ZONE},${ALIAS},${NET}/${BITS},${BUILD},${DEFAULT_BUILD}\n" >>${CONF}/${LOC}/network
  commit_file network ${CONF}/${LOC}/network
}

function network_delete {
  start_modify
  if [ -z "$1" ]; then
    network_list
    printf -- "\n"
    get_input C "Network to Delete (loc-zone-alias)"
  else
    C="$1"
  fi
  test `printf -- "$C" |sed 's/[^-]*//g' |wc -c` -eq 2 || err "Invalid format. Please ensure you are entering 'location-zone-alias'."
  grep -qE "^${C//-/,}," ${CONF}/network || err "Unknown network"
  get_yn RL "Are you sure (y/n)? "
  if [ "$RL" == "y" ]; then
    IFS="," read -r LOC ZONE ALIAS DISC <<< "$( grep -E "^${C//-/,}," ${CONF}/network )"
    sed -i '/^'${C//-/,}',/d' ${CONF}/network
    sed -i '/^'${ZONE}','${ALIAS}',/d' ${CONF}/${LOC}/network
    sed -i '/^'${C//-/,}',/d' ${CONF}/hv-network
  fi
  commit_file network ${CONF}/${LOC}/network ${CONF}/hv-network
}

# <name> ip [--assign|--unassign|--list|--list-available|--list-assigned]
function network_ip {
  # input validation
  test $# -gt 0 || err "Provide the network name (loc-zone-alias)"
  test `printf -- "$1" |sed 's/[^-]*//g' |wc -c` -eq 2 || err "Invalid format. Please ensure you are entering 'location-zone-alias'."
  grep -qE "^${1//-/,}," ${CONF}/network || err "Unknown network"
  # function
  case "$2" in
    --assign) network_ip_assign ${@:3};;
    --unassign) network_ip_unassign ${@:3};;
    --list) echo "Not implemented: $@";;
    --list-available) network_ip_list_available $1 ${@:3};;
    --list-assigned) echo "Not implemented";;
    --scan) network_ip_scan $1;;
    *) echo "Not implemented: $@";;
  esac
}

# assign an ip address to a system
#
# required:
#   $1  IP
#   $2  hostname
#   --force to assign the address and ignore checks
#
function network_ip_assign {
  start_modify
  test $# -ge 2 || err "An IP and hostname are required."
  valid_ip $1 || err "Invalid IP."
  local RET FILENAME=$( get_network $1 24 ) FORCE=0 ASSN
  if [[ $# -ge 3 && "$3" == "--force" ]]; then FORCE=1; fi
  # validate address
  grep -q "^$( ip2dec $1 )," ${CONF}/net/${FILENAME} 2>/dev/null || err "The requested IP is not available."
  [ "$( grep "^$( ip2dec $1 )," ${CONF}/net/${FILENAME} |awk 'BEGIN{FS=","}{print $3}' )" == "y" ] && err "The requested IP is reserved."
  ASSN="$( grep "^$( ip2dec $1 )," ${CONF}/net/${FILENAME} |awk 'BEGIN{FS=","}{print $5}' )"
  if [[ "$ASSN" != "" && "$ASSN" != "$2" ]]; then err "The requested IP is already assigned."; fi
  # load the ip data
  IFS="," read -r A B C D E F G H I <<<"$( grep "^$( ip2dec $1 )," ${CONF}/net/${FILENAME} )"
  # check if the ip is in use (last ditch effort)
  if [[ $FORCE -eq 0 && "$ASSN" == "" && $( /bin/ping -c4 -n -s8 -w4 -q $1 |/bin/grep "0 received" |/usr/bin/wc -l ) -eq 0 ]]; then
    # mark the address as reserved
    sed -i "s/^$( ip2dec $1 ),.*/$A,$B,y,$D,$E,$F,auto-reserved: address in use,$H,$I/" ${CONF}/net/${FILENAME}
    echo "The requested IP is in use."
    RET=1
  else
    # assign
    sed -i "s/^$( ip2dec $1 ),.*/$A,$B,$C,$D,$2,$F,$G,$H,$I/" ${CONF}/net/${FILENAME}
    RET=0
  fi
  # commit changes
  git add ${CONF}/net/${FILENAME}
  commit_file ${CONF}/net/${FILENAME}
  return $RET
}

# list unassigned and unreserved ip addresses in a network
#
# optional arguments:
#   --limit X   limit to X number of randomized results
#
function network_ip_list_available {
  # input validation
  test $# -gt 0 || err "Provide the network name (loc-zone-alias)"
  test `printf -- "$1" |sed 's/[^-]*//g' |wc -c` -eq 2 || err "Invalid format. Please ensure you are entering 'location-zone-alias'."
  grep -qE "^${1//-/,}," ${CONF}/network || err "Unknown network"
  if [[ "$2" == "--limit" && "${3//[^0-9]/}" == "$3" && $3 -gt 0 ]]; then
    network_ip_list_available $1 |shuf |head -n $3
    return
  fi
  # load the network
  read -r NETIP NETCIDR <<< "$( grep -E "^${1//-/,}," ${CONF}/network |awk 'BEGIN{FS=","}{print $4,$6}' )"
  # networks are stored as /24s so adjust the netmask if it's smaller than that
  test $NETCIDR -gt 24 && NETCIDR=24
  # look at each /24 in the network
  for ((i=0;i<$(( 2**(24 - $NETCIDR) ));i++)); do
    FILENAME=$( get_network $( dec2ip $(( $( ip2dec $NETIP ) + ( $i * 256 ) )) ) 24 )
    # skip this address if the entire subnet is not configured
    test -f ${CONF}/net/${FILENAME} || continue
    # 'free' IPs are those with 'n' in the third column and an empty fifth column
    grep -E '^[^,]*,[^,]*,n,' ${CONF}/net/${FILENAME} |grep -E '^[^,]*,[^,]*,[yn],[yn],,' |awk 'BEGIN{FS=","}{print $2}'
  done
}

# scan a subnet for used addresses and reserve them
#
function network_ip_scan {
  start_modify
  # input validation
  test $# -gt 0 || err "Provide the network name (loc-zone-alias)"
  test `printf -- "$1" |sed 's/[^-]*//g' |wc -c` -eq 2 || err "Invalid format. Please ensure you are entering 'location-zone-alias'."
  grep -qE "^${1//-/,}," ${CONF}/network || err "Unknown network"
  # declare variables
  local NETIP NETCIDR FILENAME
  # load the network
  read -r NETIP NETCIDR <<< "$( grep -E "^${1//-/,}," ${CONF}/network |awk 'BEGIN{FS=","}{print $4,$6}' )"
  # loop through the ip range and check each address
  for ((i=$( ip2dec $NETIP );i<$( ip2dec $( ipadd $NETIP $( cdr2size $NETCIDR ) ) );i++)); do
    FILENAME=$( get_network $( dec2ip $i ) 24 )
    # skip this address if the entire subnet is not configured
    test -f ${CONF}/net/${FILENAME} || continue
    # skip the address if it is registered
    grep -q "^$i," ${CONF}/net/${FILENAME} || continue
    # skip the address if it is already marked reserved
    grep "^$i," ${CONF}/net/${FILENAME} |grep -qE '^[^,]*,[^,]*,y,' && continue
    if [ $( /bin/ping -c4 -n -s8 -w3 -q $( dec2ip $i ) |/bin/grep "0 received" |/usr/bin/wc -l ) -eq 0 ]; then
      # mark the address as reserved
      IFS="," read -r A B C D E F G H I <<<"$( grep "^$i," ${CONF}/net/${FILENAME} )"
      sed -i "s/^$i,.*/$A,$B,y,$D,$E,$F,auto-reserved: address in use,$H,$I/" ${CONF}/net/${FILENAME}
      echo "Found device at $( dec2ip $i )"
    fi
  done
  git add ${CONF}/net/${FILENAME} >/dev/null 2>&1
  commit_file ${CONF}/net/${FILENAME}
}

# unassign an ip address
#
# required:
#   $1  IP
#
function network_ip_unassign {
  start_modify
  test $# -eq 1 || err "An IP is required."
  valid_ip $1 || err "Invalid IP."
  local FILENAME=$( get_network $1 24 )
  # validate address
  grep -q "^$( ip2dec $1 )," ${CONF}/net/${FILENAME} 2>/dev/null || err "The requested IP is not available."
  # unassign
  IFS="," read -r A B C D E F G H I <<<"$( grep "^$( ip2dec $1 )," ${CONF}/net/${FILENAME} )"
  sed -i "s/^$( ip2dec $1 ),.*/$A,$B,n,$D,,,,,/" ${CONF}/net/${FILENAME}
  git add ${CONF}/net/${FILENAME}
  commit_file ${CONF}/net/${FILENAME}
}

# network ipam component
#
# file storage net/a.b.c.0
# format: octal,a.b.c.d,reserved,dhcp,hostname,interface,comment,interface-comment,owner
#
# <name> ipam [--add-range|--remove-range|--reserve-range|--free-range]
function network_ipam {
  # input validation
  test $# -gt 0 || err "Provide the network name (loc-zone-alias)"
  test `printf -- "$1" |sed 's/[^-]*//g' |wc -c` -eq 2 || err "Invalid format. Please ensure you are entering 'location-zone-alias'."
  grep -qE "^${1//-/,}," ${CONF}/network || err "Unknown network"
  # function
  case "$2" in
    --add-range) network_ipam_add_range $1 ${@:3};;
    --remove-range) network_ipam_remove_range $1 ${@:3};;
    --reserve-range) echo "Not implemented";;
    --free-range) echo "Not implemented";;
    *) echo "Not implemented: $@";;
  esac
}

# add an available range of IPs
#   can not exceed the size of the network
#
# arguments:
#   loc-zone-alias  required
#   start-ip/mask   optional ip and optional mask (or bits)
#   end-ip          optional end ip
#
function network_ipam_add_range {
  start_modify
  # input validation
  test $# -gt 0 || err "Provide the network name (loc-zone-alias)"
  test `printf -- "$1" |sed 's/[^-]*//g' |wc -c` -eq 2 || err "Invalid format. Please ensure you are entering 'location-zone-alias'."
  grep -qE "^${1//-/,}," ${CONF}/network || err "Unknown network"
  test $# -gt 1 || err "An IP and mask or IP Range is required"
  # initialize variables
  local NETNAME=$1 FIRST_IP LAST_IP CIDR; shift
  local NETIP NETLAST NETCIDR
  # first check if a mask was provided in the first address
  printf -- "$1" |grep -q "/"
  if [ $? -eq 0 ]; then
    FIRST_IP=$( printf -- "$1" |sed 's%/.*%%' )
    CIDR=$( printf -- "$1" |sed 's%.*/%%' )
  else
    FIRST_IP=$1
  fi
  # make sure the provided IP is legit
  valid_ip $FIRST_IP || err "An invalid IP address was provided"
  if [ ! -z "$2" ]; then LAST_IP=$2; fi
  if [ ! -z "$CIDR" ]; then
    # verify the first IP is the same as the network IP if a CIDR was provided
    test "$( get_network $FIRST_IP $CIDR )" != "$FIRST_IP" && err "The provided address was not the first in the specified subnet. Use a range instead."
    # get or override the last IP if a CIDR was provided
    LAST_IP=$( ipadd $FIRST_IP $(( $( cdr2size $CIDR ) - 1 )) )
  fi
  # make sure the last IP is legit too
  valid_ip $LAST_IP || err "An invalid IP address was provided"
  # make sure both first and last are in the range for the provided network
  read -r NETIP NETCIDR <<< "$( grep -E "^${NETNAME//-/,}," ${CONF}/network |awk 'BEGIN{FS=","}{print $4,$6}' )"
  # get the expected last ip in the network
  NETLAST=$( ipadd $NETIP $(( $( cdr2size $NETCIDR ) - 1 )) )
  [[ $( ip2dec $FIRST_IP ) -lt $( ip2dec $NETIP ) || $( ip2dec $FIRST_IP ) -gt $( ip2dec $NETLAST) ]] && err "Starting address is outside expected range."
  [[ $( ip2dec $LAST_IP ) -lt $( ip2dec $NETIP ) || $( ip2dec $LAST_IP ) -gt $( ip2dec $NETLAST) ]] && err "Ending address is outside expected range."
  # special case where first IP is the actual network address and the last ip is the broadcast
  if [ $( ip2dec $FIRST_IP ) -eq $( ip2dec $NETIP ) ]; then FIRST_IP=$( dec2ip $(( $( ip2dec $FIRST_IP ) + 1 )) ); fi
  if [ $( ip2dec $LAST_IP ) -eq $( ip2dec $NETLAST ) ]; then LAST_IP=$( dec2ip $(( $( ip2dec $LAST_IP ) - 1 )) ); fi
  # make the directory if needed
  test ! -d ${CONF}/net && mkdir ${CONF}/net
  # loop through the ip range and add each address to the appropriate file
  for ((i=$( ip2dec $FIRST_IP );i<=$( ip2dec $LAST_IP );i++)); do
    # get the file name
    FILENAME=$( get_network $( dec2ip $i ) 24 )
    grep -qE "^$i," ${CONF}/net/$FILENAME 2>/dev/null
    if [ $? -eq 0 ]; then echo "Error: entry already exists for $( dec2ip $i ). Skipping..." >&2; continue; fi
    printf -- "${i},$( dec2ip $i ),n,n,,,,,\n" >>${CONF}/net/$FILENAME
  done
  git add ${CONF}/net/$FILENAME >/dev/null 2>&1
  commit_file ${CONF}/net/$FILENAME
}

# remove a range of IPs and 'forget' the assignments
#
# arguments:
#   loc-zone-alias  required
#   start-ip/mask   optional ip and optional mask (or bits)
#   end-ip          optional end ip
#
function network_ipam_remove_range {
  start_modify
  # input validation
  test $# -gt 0 || err "Provide the network name (loc-zone-alias)"
  test `printf -- "$1" |sed 's/[^-]*//g' |wc -c` -eq 2 || err "Invalid format. Please ensure you are entering 'location-zone-alias'."
  grep -qE "^${1//-/,}," ${CONF}/network || err "Unknown network"
  test $# -gt 1 || err "An IP and mask or IP Range is required"
  # initialize variables
  local NETNAME=$1 FIRST_IP LAST_IP CIDR; shift
  local NETIP NETLAST NETCIDR
  # first check if a mask was provided in the first address
  printf -- "$1" |grep -q "/"
  if [ $? -eq 0 ]; then
    FIRST_IP=$( printf -- "$1" |sed 's%/.*%%' )
    CIDR=$( printf -- "$1" |sed 's%.*/%%' )
  else
    FIRST_IP=$1
  fi
  # make sure the provided IP is legit
  valid_ip $FIRST_IP || err "An invalid IP address was provided"
  if [ ! -z "$2" ]; then LAST_IP=$2; fi
  if [ ! -z "$CIDR" ]; then
    # verify the first IP is the same as the network IP if a CIDR was provided
    test "$( get_network $FIRST_IP $CIDR )" != "$FIRST_IP" && err "The provided address was not the first in the specified subnet. Use a range instead."
    # get or override the last IP if a CIDR was provided
    LAST_IP=$( ipadd $FIRST_IP $(( $( cdr2size $CIDR ) - 1 )) )
  fi
  # make sure the last IP is legit too
  valid_ip $LAST_IP || err "An invalid IP address was provided"
  # make sure both first and last are in the range for the provided network
  read -r NETIP NETCIDR <<< "$( grep -E "^${NETNAME//-/,}," ${CONF}/network |awk 'BEGIN{FS=","}{print $4,$6}' )"
  # get the expected last ip in the network
  NETLAST=$( ipadd $NETIP $(( $( cdr2size $NETCIDR ) - 1 )) )
  [[ $( ip2dec $FIRST_IP ) -lt $( ip2dec $NETIP ) || $( ip2dec $FIRST_IP ) -gt $( ip2dec $NETLAST) ]] && err "Starting address is outside expected range."
  [[ $( ip2dec $LAST_IP ) -lt $( ip2dec $NETIP ) || $( ip2dec $LAST_IP ) -gt $( ip2dec $NETLAST) ]] && err "Ending address is outside expected range."
  # confirm
  echo "This operation will remove records for $(( $( ip2dec $LAST_IP ) - $( ip2dec $FIRST_IP ) + 1 )) ip address(es)!"
  get_yn RL "Are you sure (y/n)? "
  if [ "$RL" == "y" ]; then
    # loop through the ip range and remove each address from the appropriate file
    for ((i=$( ip2dec $FIRST_IP );i<=$( ip2dec $LAST_IP );i++)); do
      # get the file name
      FILENAME=$( get_network $( dec2ip $i ) 24 )
      sed -i "/^$i,/d" ${CONF}/net/$FILENAME 2>/dev/null
    done
    git add ${CONF}/net/$FILENAME >/dev/null 2>&1
    commit_file ${CONF}/net/$FILENAME
  fi
}

# list configured networks
#
# optional:
#   --build <loc>  output a list of available build networks at the specified location
#   --match <ip>   output the configured network that includes the specific IP, if any
#
function network_list {
  if [ $# -gt 0 ]; then
    case "$1" in
      --build)
        test -z "$2" && return
        DEFAULT=$( grep -E "^$2," ${CONF}/network |grep -E ',y,y$' |awk 'BEGIN{FS=","}{print $1"-"$2"-"$3}' )
        ALL=$( grep -E "^$2," ${CONF}/network |grep -E ',y,[yn]$' |awk 'BEGIN{FS=","}{print $1"-"$2"-"$3}' |tr '\n' ' ' )
        test ! -z "$DEFAULT" && printf -- "default: $DEFAULT\n"
        test ! -z "$ALL" && printf -- "available: $ALL\n"
        ;;
      --match)
        $( valid_ip $2 ) || err "Invalid IP"
        DEC=$( ip2dec $2 )
        printf -- "$( awk 'BEGIN{FS=","}{print $1"-"$2"-"$3,$4,$6}' ${CONF}/network )" | while read -r NAME IP CIDR; do
          FIRST_IP=$( ip2dec $IP )
          LAST_IP=$(( $FIRST_IP + $( cdr2size $CIDR ) - 1 ))
          if [[ $FIRST_IP -le $DEC && $LAST_IP -ge $DEC ]]; then printf -- "$NAME\n"; break; fi
        done
        ;;
      *) err "Invalid argument";;
    esac
  else
    NUM=$( wc -l ${CONF}/network |awk '{print $1}' )
    if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
    echo "There ${A} ${NUM} defined network${S}."
    test $NUM -eq 0 && return
    ( printf -- "Site Alias Network\n"; network_list_unformatted ) |column -t |sed 's/^/   /'
  fi
}

function network_list_unformatted {
  awk 'BEGIN{FS=","}{print $1"-"$2,$3,$4"/"$6}' ${CONF}/network |sort
}

function network_show {
  test $# -eq 1 || err "Provide the network name (loc-zone-alias)"
  test `printf -- "$1" |sed 's/[^-]*//g' |wc -c` -eq 2 || err "Invalid format. Please ensure you are entering 'location-zone-alias'."
  grep -qE "^${1//-/,}," ${CONF}/network || err "Unknown network"
  #   --format: location,zone,alias,network,mask,cidr,gateway_ip,dns_ip,vlan,description,repo_address,repo_fs_path,repo_path_url,build,default-build\n
  IFS="," read -r LOC ZONE ALIAS NET MASK BITS GW DNS VLAN DESC REPO_ADDR REPO_PATH REPO_URL BUILD DEFAULT_BUILD NTP <<< "$( grep -E "^${1//-/,}," ${CONF}/network )"
  printf -- "Location Code: $LOC\nNetwork Zone: $ZONE\nSite Alias: $ALIAS\nDescription: $DESC\nNetwork: $NET\nSubnet Mask: $MASK\nSubnet Bits: $BITS\nGateway Address: $GW\nDNS Server: $DNS\nNTP Server: $NTP\nVLAN Tag/Number: $VLAN\nBuild Network: $BUILD\nDefault Build Network: $DEFAULT_BUILD\nRepository Address: $REPO_ADDR\nRepository Path: $REPO_PATH\nRepository URL: $REPO_URL\n"
}

function network_update {
  start_modify
  if [ -z "$1" ]; then
    network_list
    printf -- "\n"
    get_input C "Network to Modify (loc-zone-alias)"
  else
    C="$1"
  fi
  # validate string
  test `printf -- "$C" |sed 's/[^-]*//g' |wc -c` -eq 2 || err "Invalid format. Please ensure you are entering 'location-zone-alias'."
  grep -qE "^${C//-/,}," ${CONF}/network || err "Unknown network"
  printf -- "\n"
  IFS="," read -r L Z A NETORIG MASKORIG BITS GW DNS VLAN DESC REPO_ADDR REPO_PATH REPO_URL BUILD DEFAULT_BUILD NTP <<< "$( grep -E "^${C//-/,}," ${CONF}/network )"
  get_input LOC "Location Code" --default "$L" --options "$( location_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  get_input ZONE "Network Zone" --options core,edge --default "$Z"
  get_input ALIAS "Site Alias" --default "$A"
  # validate unique name if it is changing
  if [ "$LOC-$ZONE-$ALIAS" != "$C" ]; then
    grep -qE "^$LOC,$ZONE,$ALIAS," $CONF/network && err "Network already defined."
  fi
  get_input DESC "Description" --nc --null --default "$DESC"
  while ! $(valid_ip "$NET"); do get_input NET "Network" --default "$NETORIG"; done
  get_input BITS "CIDR Mask (Bits)" --regex '^[0-9]+$' --default "$BITS"
  while ! $(valid_mask "$MASK"); do get_input MASK "Subnet Mask" --default $(cdr2mask $BITS); done
  get_input GW "Gateway Address" --default "$GW" --null
  get_input DNS "DNS Server Address" --null --default "$DNS"
  get_input NTP "NTP Server Address" --null --default "$NTP"
  get_input VLAN "VLAN Tag/Number" --default "$VLAN" --null
  get_yn BUILD "Use network for system builds (y/n)? " --default "$BUILD"
  if [ "$BUILD" == "y" ]; then
    get_yn DEFAULT_BUILD "Should this be the *default* build network at the location (y/n)? " --default "$DEFAULT_BUILD"
    # when adding a new default build network make sure we prompt if another exists, since it will be replaced
    if [[ "$DEFAULT_BUILD" == "y" && `grep -E ',y$' ${CONF}/${LOC}/network |grep -vE "^${ZONE},${ALIAS}," |wc -l` -ne 0 ]]; then
      get_yn RL "WARNING: Another default build network exists at this site. Are you sure you want to replace it (y/n)? "
      if [ "$RL" != "y" ]; then echo "...aborted!"; return; fi
    fi
    get_input REPO_ADDR "Repository IP or Host Name" --default "$REPO_ADDR" --nc
    get_input REPO_PATH "Repository Local Path" --default "$REPO_PATH" --nc
    get_input REPO_URL "Repository URL" --default "$REPO_URL" --nc
  else
    DEFAULT_BUILD="n"
    REPO_ADDR=""
    REPO_PATH=""
    REPO_URL=""
  fi
  # make sure to remove any other default build network
  if [[ "$DEFAULT_BUILD" == "y" && `grep -E ',y$' ${CONF}/${LOC}/network |grep -vE "^${ZONE},${ALIAS}," |wc -l` -gt 0 ]]; then
    # get the current default network (if any) and update it
    IFS="," read -r ZP AP DISC <<< "$( grep -E ',y$' ${CONF}/${LOC}/network |grep -vE "^${ZONE},${ALIAS}," )"
    sed -ri 's%^('${LOC}','${ZP}','${AP}',.*),y,y$%\1,y,n%' ${CONF}/network
    sed -i 's/,y$/,n/' ${CONF}/${LOC}/network
  fi
  #   --format: location,zone,alias,network,mask,cidr,gateway_ip,dns_ip,vlan,description,repo_address,repo_fs_path,repo_path_url,build,default-build,ntp_ip\n
  sed -i 's%^'${C//-/,}',.*%'${LOC}','${ZONE}','${ALIAS}','${NET}','${MASK}','${BITS}','${GW}','${DNS}','${VLAN}','"${DESC}"','${REPO_ADDR}','"${REPO_PATH}"','"${REPO_URL}"','${BUILD}','${DEFAULT_BUILD}','${NTP}'%' ${CONF}/network
  #   --format: zone,alias,network/cidr,build,default-build\n
  if [ "$LOC" == "$L" ]; then
    # location is not changing, safe to update in place
    sed -i 's%^'${Z}','${A}',.*%'${ZONE}','${ALIAS}','${NET}'\/'${BITS}','${BUILD}','${DEFAULT_BUILD}'%' ${CONF}/${LOC}/network
    commit_file network ${CONF}/${LOC}/network
  else
    # location changed, remove from old location and add to new
    sed -i '/^'${ZONE}','${ALIAS}',/d' ${CONF}/${L}/network
    test ! -d ${CONF}/${LOC} && mkdir ${CONF}/${LOC}
    printf -- "${ZONE},${ALIAS},${NET}/${BITS},${BUILD},${DEFAULT_BUILD}\n" >>${CONF}/${LOC}/network
    commit_file network ${CONF}/${LOC}/network ${CONF}/${L}/network
  fi
}


 ####### ####### #     # ######  #          #    ####### ####### 
    #    #       ##   ## #     # #         # #      #    #       
    #    #       # # # # #     # #        #   #     #    #       
    #    #####   #  #  # ######  #       #     #    #    #####   
    #    #       #     # #       #       #######    #    #       
    #    #       #     # #       #       #     #    #    #       
    #    ####### #     # #       ####### #     #    #    #######

# locate template variables and replace with actual data
#
# the template file WILL be modified!
#
# required:
#  $1 /path/to/template
#  $2 file with space seperated variables and values
#
# optional:
#  $3 value of "1" means output errors
#  $4 value of "1" means output verbose info on missing variables
#
# syntax:
#  {% resource.name %}
#  {% constant.name %}
#  {% system.name %}, {% system.ip %}, {% system.location %}, {% system.environment %}
#
function parse_template {
  [[ $# -lt 2 || ! -f $1 || ! -f $2 ]] && return
  [[ $# -ge 3 && ! -z "$3" && "$3" == "1" ]] && local SHOWERROR=1 || local SHOWERROR=0
  [[ $# -ge 4 && ! -z "$4" && "$4" == "1" ]] && local VERBOSE=1 || local VERBOSE=0
  local RETVAL=0
  while [ `grep -cE '{% (resource|constant|system)\.[^ ,]+ %}' $1` -gt 0 ]; do
    local NAME=$( grep -Em 1 '{% (resource|constant|system)\.[^ ,]+ %}' $1 |sed -r 's/.*\{% (resource|constant|system)\.([^ ,]+) %\}.*/\1.\2/' )
    grep -qE "^$NAME " $2
    if [ $? -ne 0 ]; then
      if [ $SHOWERROR -eq 1 ]; then printf -- "Error: Undefined variable $NAME\n" >&2; fi
      if [ $VERBOSE -eq 1 ]; then
        printf -- "  Missing Variable: '$NAME'\n"
        sed -i s$'\001'"{% $NAME %}"$'\001'""$'\001' $1
        RETVAL=1
        continue
       else
         return 1
       fi
    fi
    local VAL=$( grep -E "^$NAME " $2 |sed "s/^$NAME //" )
    sed -i s$'\001'"{% $NAME %}"$'\001'"${VAL//&/\&}"$'\001' $1
  done
  return $RETVAL
}


 ######  #######  #####  ####### #     # ######   #####  ####### 
 #     # #       #     # #     # #     # #     # #     # #       
 #     # #       #       #     # #     # #     # #       #       
 ######  #####    #####  #     # #     # ######  #       #####   
 #   #   #             # #     # #     # #   #   #       #       
 #    #  #       #     # #     # #     # #    #  #     # #       
 #     # #######  #####  #######  #####  #     #  #####  #######

# manage or list resource assignments
#
# <value> [--assign|--unassign|--list] [<host>]
#
function resource_byval {
  case "$2" in
    --assign) resource_byval_assign $1 ${@:3};;
    --list) resource_list ",host,$1,";;
    --unassign) resource_byval_unassign $1;;
  esac
}

# assign a resource to a host
# - it only makes sense to assign an ip to a host, ha/cluster ips should
#   be assigned to an application and environment or build and environment
#
# requires:
#   $1  resource
# 
# optional:
#   $2  system
#
function resource_byval_assign {
  start_modify
  # input validation
  test $# -gt 0 || err
  grep -qE "^ip,$1,,not assigned," ${CONF}/resource || err "Invalid or unavailable resource"
  # get the system name
  generic_choose system "$2" HOST
  # update the assignment in the resource file
  sed -ri 's/^(ip,'$1'),,not assigned,(.*)$/\1,host,'$HOST',\2/' ${CONF}/resource
  commit_file resource
}

# unassign a resource
#
# requires:
#   $1  resource
# 
function resource_byval_unassign {
  start_modify
  # input validation
  test $# -gt 0 || err
  grep -qE "^(cluster_|ha_)?ip,$1,(host|application)," ${CONF}/resource || err "Invalid or unassigned resource"
  # confirm
  get_yn RL "Are you sure (y/n)? "
  test "$RL" != "y" && return
  # update the assignment in the resource file
  sed -ri 's/^(.*ip,'$1'),(host|application),[^,]*,(.*)$/\1,,not assigned,\2/' ${CONF}/resource
  commit_file resource
}

# resource field format:
#   type,value,assignment_type(application,host),assigned_to,description
#
function resource_create {
  start_modify
  # get user input and validate
  get_input NAME "Name" --null
  get_input TYPE "Type" --options ip,cluster_ip,ha_ip
  get_input VAL "Value" --nc
  get_input DESC "Description" --nc --null
  # validate unique value
  grep -qE ",${VAL//,/}," $CONF/resource && err "Error - not a unique resource value."
  # add
  printf -- "${TYPE},${VAL//,/},,not assigned,${NAME//,/},${DESC}\n" >>$CONF/resource
  commit_file resource
}

function resource_delete {
  start_modify
  generic_choose resource "$1" C && shift
  get_yn RL "Are you sure (y/n)? "
  if [ "$RL" == "y" ]; then
    sed -i '/,'${C}',/d' ${CONF}/resource
  fi
  commit_file resource
}

# show available resources
#
# optional:
#  $1  regex to filter list on
#
function resource_list {
  if ! [ -z "$1" ]; then
    NUM=$( grep -E "$1" ${CONF}/resource |wc -l |awk '{print $1}' ); N="matching"
  else
    NUM=$( wc -l ${CONF}/resource |awk '{print $1}' ); N="defined"
  fi
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} $N resource${S}."
  test $NUM -eq 0 && return
  # include assignment status in output
  for R in $( resource_list_unformatted "$1" |tr ' ' ',' ); do
    IFS="," read -r NAME TYPE VAL <<< "$R"
    test -z "$NAME" && NAME="-"
    printf -- "$NAME $TYPE $VAL"
    grep -E "^$TYPE,$VAL," ${CONF}/resource |grep -qE ',(host|application),'
    if [ $? -eq 0 ]; then
      # ok... load the resource so we can tell Chelsea what it's assigned to
      IFS="," read -r TYPE VAL ASSIGN_TYPE ASSIGN_TO NAME DESC <<< "$( grep -E "^$TYPE,$VAL," ${CONF}/resource )"
      printf -- " $ASSIGN_TYPE:$ASSIGN_TO" |sed 's/^ host/ system/'
    else
      printf -- " [unassigned]"
    fi
    printf -- "\n"
  done |column -t |sed 's/^/   /'
}

# show available resources
#
# optional:
#  $1  regex to filter list on
#
function resource_list_unformatted {
  if ! [ -z "$1" ]; then
    grep -E "$1" ${CONF}/resource |awk 'BEGIN{FS=","}{print $5,$1,$2}' |sort
  else
    awk 'BEGIN{FS=","}{print $5,$1,$2}' ${CONF}/resource |sort
  fi
}

function resource_show {
  test $# -eq 1 || err "Provide the resource value"
  grep -qE ",$1," ${CONF}/resource || err "Unknown resource" 
  IFS="," read -r TYPE VAL ASSIGN_TYPE ASSIGN_TO NAME DESC <<< "$( grep -E ",$1," ${CONF}/resource )"
  printf -- "Name: $NAME\nType: $TYPE\nValue: $VAL\nDescription: $DESC\nAssigned to $ASSIGN_TYPE: $ASSIGN_TO\n"
}

function resource_update {
  start_modify
  generic_choose resource "$1" C && shift
  IFS="," read -r TYPE VAL ASSIGN_TYPE ASSIGN_TO NAME DESC <<< "$( grep -E ",$C," ${CONF}/resource )"
  get_input NAME "Name" --default "$NAME" --null
  get_input TYPE "Type" --options ip,cluster_ip,ha_ip --default "$TYPE"
  get_input VAL "Value" --nc --default "$VAL"
  # validate unique value
  if [ "$VAL" != "$C" ]; then
    grep -qE ",${VAL//,/}," $CONF/resource && err "Error - not a unique resource value."
  fi
  get_input DESC "Description" --nc --null --default "$DESC"
  sed -i 's/.*,'$C',.*/'${TYPE}','${VAL//,/}','"$ASSIGN_TYPE"','"$ASSIGN_TO"','"${NAME//,/}"','"${DESC}"'/' ${CONF}/resource
  commit_file resource
}


 #     # #     # ######  ####### ######  #     # ###  #####  ####### ######
 #     #  #   #  #     # #       #     # #     #  #  #     # #     # #     #
 #     #   # #   #     # #       #     # #     #  #  #       #     # #     #
 #######    #    ######  #####   ######  #     #  #   #####  #     # ######
 #     #    #    #       #       #   #    #   #   #        # #     # #   #
 #     #    #    #       #       #    #    # #    #  #     # #     # #    #
 #     #    #    #       ####### #     #    #    ###  #####  ####### #     #

#   --format: environment,hypervisor
function hypervisor_add_environment {
  start_modify
  test $# -ge 1 || err "Provide the hypervisor name"
  grep -qE "^$1," ${CONF}/hypervisor || err "Unknown hypervisor"
  # get the environment
  generic_choose environment "$2" ENV
  # verify this mapping does not already exist
  grep -qE "^$ENV,$1\$" ${CONF}/hv-environment && err "That environment is already linked"
  # add mapping
  printf -- "$ENV,$1\n" >>${CONF}/hv-environment
  commit_file hv-environment
}

#   --format: loc-zone-alias,hv-name,interface
function hypervisor_add_network {
  start_modify
  test $# -ge 1 || err "Provide the hypervisor name"
  grep -qE "^$1," ${CONF}/hypervisor || err "Unknown hypervisor"
  # get the network
  if [ -z "$2" ]; then
    network_list
    printf -- "\n"
    get_input C "Network to Modify (loc-zone-alias)"
  else
    test `printf -- "$2" |sed 's/[^-]*//g' |wc -c` -eq 2 || err "Invalid format. Please ensure you are entering 'location-zone-alias'."
    C="$2"
  fi
  grep -qE "^${C//-/,}," ${CONF}/network || err "Unknown network"
  # verify this mapping does not already exists
  grep -qE "^$C,$1," ${CONF}/hv-network && err "That network is already linked"
  # get the interface
  if [ -z "$3" ]; then get_input IFACE "Network Interface"; else IFACE="$3"; fi
  # add mapping
  printf -- "$C,$1,$IFACE\n" >>${CONF}/hv-network
  commit_file hv-network
}

#   [<name>] [--add-network|--remove-network|--add-environment|--remove-environment|--poll]
function hypervisor_byname {
  # input validation
  test $# -gt 1 || err "Provide the hypervisor name"
  grep -qE "^$1," ${CONF}/hypervisor || err "Unknown hypervisor"
  case "$2" in
    --add-environment) hypervisor_add_environment $1 ${@:3};;
    --add-network) hypervisor_add_network $1 ${@:3};;
    --poll) hypervisor_poll $1 ${@:3};;
    --remove-environment) hypervisor_remove_environment $1 ${@:3};;
    --remove-network) hypervisor_remove_network $1 ${@:3};;
  esac
}

#   --format: name,management-ip,location,vm-path,vm-min-disk(mb),min-free-mem(mb),enabled
function hypervisor_create {
  start_modify
  # get user input and validate
  get_input NAME "Hostname"
  # validate unique name
  grep -qE "^$NAME," $CONF/hypervisor && err "Hypervisor already defined."
  while ! $(valid_ip "$IP"); do get_input IP "Management IP"; done
  get_input LOC "Location" --options "$( location_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  get_input VMPATH "VM Storage Path"
  get_input MINDISK "Disk Space Minimum (MB)" --regex '^[0-9]*$'
  get_input MINMEM "Memory Minimum (MB)" --regex '^[0-9]*$'
  get_yn ENABLED "Enabled (y/n): "
  # add
  printf -- "${NAME},${IP},${LOC},${VMPATH},${MINDISK},${MINMEM},${ENABLED}\n" >>$CONF/hypervisor
  commit_file hypervisor
}

function hypervisor_delete {
  generic_delete hypervisor $1 || return
  # also delete from hv-environment and hv-network
  sed -i "/^[^,]*,$1\$/d" $CONF/hv-environment
  sed -i "/^[^,]*,$1,/d" $CONF/hv-network
  commit_file hv-environment hv-network
}

# show the configured hypervisors
#
# optional:
#   --location <string>     limit to the specified location
#   --environment <string>  limit to the specified environment
#   --network <string>      limit to the specified network (may be specified up to two times)
#
function hypervisor_list {
 NUM=$( wc -l ${CONF}/hypervisor |awk '{print $1}' )
  if [ $# -eq 0 ]; then
    if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
    echo "There ${A} ${NUM} defined hypervisor${S}."
    test $NUM -eq 0 && return
    awk 'BEGIN{FS=","}{print $1}' ${CONF}/hypervisor |sort |sed 's/^/   /'
  else
    if [ $NUM -eq 0 ]; then return; fi
    LIST="$( awk 'BEGIN{FS=","}{print $1}' ${CONF}/hypervisor |tr '\n' ' ' )"
    while [ $# -gt 0 ]; do case "$1" in
      --location)
        NL=""
        for N in $LIST; do
          grep -qE '^'$N',[^,]*,'$2',' ${CONF}/hypervisor && NL="$NL $N"
        done
        LIST="$NL"
        shift
        ;;
      --environment)
        NL=""
        for N in $LIST; do
          grep -qE '^'$2','$N'$' ${CONF}/hv-environment && NL="$NL $N"
        done
        LIST="$NL"
        shift
        ;;
      --network)
        NL=""
        for N in $LIST; do
          grep -qE '^'$2','$N',' ${CONF}/hv-network && NL="$NL $N"
        done
        LIST="$NL"
        shift
        ;;
      *) err "Invalid argument";;
    esac; shift; done
    for N in $LIST; do printf -- "$N\n"; done
  fi
}

# poll the hypervisor for current system status
#   --format: name,management-ip,location,vm-path,vm-min-disk(mb),min-free-mem(mb),enabled
#
# optional:
#   --disk   only display free disk in MB
#   --mem    only display free memory in MB
#
function hypervisor_poll {
  # input validation
  test $# -ge 1 || err "Provide the hypervisor name"
  grep -qE "^$1," ${CONF}/hypervisor || err "Unknown hypervisor"
  # load the host
  IFS="," read -r NAME IP LOC VMPATH MINDISK MINMEM ENABLED <<< "$( grep -E "^$1," ${CONF}/hypervisor )"
  # test the connection
  nc -z -w 2 $IP 22 >/dev/null 2>&1 || err "Hypervisor is not accessible at this time"
  # collect memory usage
  FREEMEM=$( ssh $IP "free -m |head -n3 |tail -n1 |awk '{print \$NF}'" )
  MEMPCT=$( echo "scale=2;($FREEMEM / $MINMEM)*100" |bc |sed 's/\..*//' )
  # optionally only return memory
  if [ "$2" == "--mem" ]; then
    # if memory is at or below minimum mask it as 0
    if [ $(( $FREEMEM - $MINMEM )) -le 0 ]; then printf -- "0"; else printf -- "$FREEMEM"; fi
    return 0
  fi
  # collect disk usage
  N=$( ssh $IP "df -h $VMPATH |tail -n1 |awk '{print \$3}'" )
  case "${N: -1}" in
    T) M="* 1024 * 1024";;
    G) M="* 1024";;
    M) M="* 1";;
    k) M="/ 1024";;
    b) M="/ 1024 / 1024";;
    *) err "Unknown size qualifer in '$N'";;
  esac
  FREEDISK=$( echo "${N%?} $M" |bc |sed 's/\..*//' ) 
  DISKPCT=$( echo "scale=2;($FREEDISK / $MINDISK)*100" |bc |sed 's/\..*//' )
  # optionally only return disk space
  if [ "$2" == "--disk" ]; then
    # if disk is at or below minimum mask it as 0
    if [ $(( $FREEDISK - $MINDISK )) -le 0 ]; then printf -- "0"; else printf -- "$FREEDISK"; fi
    return 0
  fi
  # collect load data
  IFS="," read -r ONE FIVE FIFTEEN <<< "$( ssh $IP "uptime |sed 's/.* load average: //'" )"
  # output results
  printf -- "Name: $NAME\nAvailable Disk (MB): $FREEDISK (${DISKPCT}%% of minimum)\nAvailable Memory (MB): $FREEMEM (${MEMPCT}%% of minimum)\n1-minute Load Avg: $ONE\n5-minute Load Ave: $FIVE\n15-minute Load Avg: $FIFTEEN\n"
}

# given a list of one or more hypervisors return the top ranked system based on
#   available resources
#
function hypervisor_rank {
  test -z "$1" && return 1
  # create an array from the input list of hosts
  LIST=( $@ )
  # special case where only one host is provided
  if [ ${#LIST[@]} -eq 1 ]; then printf -- ${LIST[0]}; return 0; fi
  # start comparing at zero so first result is always the first best
  local DISK=0 MEM=0 D=0 M=0 SEL=""
  for ((i=0;i<${#LIST[@]};i++)); do
    # get the stats from the host
    D=$( hypervisor_poll ${LIST[$i]} --disk 2>/dev/null )
    test -z "$D" && continue
    M=$( hypervisor_poll ${LIST[$i]} --mem 2>/dev/null )
    # this is the tricky part -- how to we determine which is 'better' ?
    # what if one host has lots of free disk space but no memory?
    # I am going to rank free memory higher than CPU -- the host with the most memory unless they are very close
    C=$( echo "scale=2; (($M + 1) - ($MEM + 1)) / ($MEM + 1) * 100" |bc |sed 's/\..*//' )
    if [ $C -gt 5 ]; then
      # greater than 5% more memory on this hypervisor, set it as preferred
      MEM=$M; DISK=$D
      SEL=${LIST[$i]}
    fi
  done
  if [ -z "$SEL" ]; then err "Error ranking hypervisors"; fi
  printf -- $SEL
}

function hypervisor_remove_environment {
  start_modify
  test $# -ge 1 || err "Provide the hypervisor name"
  grep -qE "^$1," ${CONF}/hypervisor || err "Unknown hypervisor"
  # get the environment
  generic_choose environment "$2" ENV
  # verify this mapping exists
  grep -qE "^$ENV,$1\$" ${CONF}/hv-environment || return
  # remove mapping
  sed -i '/^'$ENV','$1'/d' ${CONF}/hv-environment
  commit_file hv-environment
}

function hypervisor_remove_network {
  start_modify
  test $# -ge 1 || err "Provide the hypervisor name"
  grep -qE "^$1," ${CONF}/hypervisor || err "Unknown hypervisor"
  # get the network
  if [ -z "$2" ]; then
    network_list
    printf -- "\n"
    get_input C "Network to Modify (loc-zone-alias)"
  else
    test `printf -- "$2" |sed 's/[^-]*//g' |wc -c` -eq 2 || err "Invalid format. Please ensure you are entering 'location-zone-alias'."
    C="$2"
  fi
  grep -qE "^${C//-/,}," ${CONF}/network || err "Unknown network"
  # verify this mapping already exists
  grep -qE "^$C,$1," ${CONF}/hv-network || return
  # remove mapping
  sed -i '/^'$C','$1',/d' ${CONF}/hv-network
  commit_file hv-network
}

#   --format: name,management-ip,location,vm-path,vm-min-disk(mb),min-free-mem(mb),enabled
function hypervisor_show {
  # input validation
  test $# -gt 0 || err "Provide the hypervisor name"
  grep -qE "^$1," ${CONF}/hypervisor || err "Unknown hypervisor"
  # load the host
  IFS="," read -r NAME IP LOC VMPATH MINDISK MINMEM ENABLED <<< "$( grep -E "^$1," ${CONF}/hypervisor )"
  # output the status/summary
  printf -- "Name: $NAME\nManagement Address: $IP\nLocation: $LOC\nVM Storage: $VMPATH\nReserved Disk (MB): $MINDISK\nReserved Memory (MB): $MINMEM\nEnabled: $ENABLED\n"
  # get networks
  printf -- "\nNetwork Interfaces:\n"
  grep -E ",$1," ${CONF}/hv-network |awk 'BEGIN{FS=","}{print $3":",$1}' |sed 's/^/  /' |sort
  # get environments
  printf -- "\nLinked Environments:\n"
  grep -E ",$1\$" ${CONF}/hv-environment |sed 's/^/  /; s/,.*//' |sort
  echo
}

#   --format: name,management-ip,location,vm-path,vm-min-disk(mb),min-free-mem(mb),enabled
function hypervisor_update {
  start_modify
  generic_choose hypervisor "$1" C && shift
  IFS="," read -r NAME ORIGIP LOC VMPATH MINDISK MINMEM ENABLED <<< "$( grep -E "^$C," ${CONF}/hypervisor )"
  get_input NAME "Hostname" --default "$NAME"
  # validate unique name if it is changed
  test "$NAME" != "$C" && grep -qE "^$NAME," $CONF/hypervisor && err "Hypervisor already defined."
  while ! $(valid_ip "$IP"); do get_input IP "Management IP" --default "$ORIGIP" ; done
  get_input LOC "Location" --options "$( location_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )" --default "$LOC"
  get_input VMPATH "VM Storage Path" --default "$VMPATH"
  get_input MINDISK "Disk Space Minimum (MB)" --regex '^[0-9]*$' --default "$MINDISK"
  get_input MINMEM "Memory Minimum (MB)" --regex '^[0-9]*$' --default "$MINMEM"
  get_yn ENABLED "Enabled (y/n): " --default "$ENABLED"
  sed -i 's%^'$C',.*%'${NAME}','${IP}','${LOC}','${VMPATH}','${MINDISK}','${MINMEM}','${ENABLED}'%' ${CONF}/hypervisor
  if [ "$NAME" != "$C" ]; then
    sed -i "s/,$C\$/,$NAME/" ${CONF}/hv-environment
    sed -ri 's%^([^,]*),'$C',(.*)$%\1,'$NAME',\2%' ${CONF}/hv-network
  fi
  commit_file hypervisor hv-environment hv-network
}


  #####  #     #  #####  ####### ####### #     # 
 #     #  #   #  #     #    #    #       ##   ## 
 #         # #   #          #    #       # # # # 
  #####     #     #####     #    #####   #  #  # 
       #    #          #    #    #       #     # 
 #     #    #    #     #    #    #       #     # 
  #####     #     #####     #    ####### #     #

# system functions
#
# <value> [--audit|--check|--deploy|--release|--vars]
function system_byname {
  # input validation
  test $# -gt 1 || err "Provide the system name"
  grep -qE "^$1," ${CONF}/system || err "Unknown system"
  # function
  case "$2" in
    --audit) system_audit $1;;
    --check) system_check $1;;
    --deploy) system_deploy $1;;
    --deprovision) system_deprovision $1;;
    --provision) system_provision $1 ${@:3};;
    --push-build-scripts) system_push_build_scripts $1 ${@:3};;
    --release) system_release $1;;
    --start-remote-build) system_start_remote_build $1 ${@:3};;
    --vars) system_vars $1;;
  esac
}

function system_audit {
  test $# -gt 0 || err
  VALID=0
  # load the system
  IFS="," read -r NAME BUILD IP LOC EN <<< "$( grep -E "^$1," ${CONF}/system )"
  # test connectivity
  nc -z -w 2 $1 22 >/dev/null 2>&1 || err "System $1 is not accessible at this time"
  # generate the release
  echo "Generating release..."
  FILE=$( system_release $1 |tail -n1 )
  test -s "$FILE" || err "Error generating release"
  # extract release to local directory
  echo "Extracting..."
  mkdir -p $TMP/{REFERENCE,ACTUAL}
  tar xzf $FILE -C $TMP/REFERENCE/ || err "Error extracting release to local directory"
  # clean up temporary release archive
  rm -f $FILE
  # switch to the release root
  pushd $TMP/REFERENCE >/dev/null 2>&1
  # move the stat file out of the way
  mv scs-stat ../
  # remove scs deployment scripts for audit
  rm -f scs-*
  # pull down the files to audit
  echo "Retrieving current system configuration..."
  for F in $( find . -type f |sed 's%^\./%%' ); do
    mkdir -p $TMP/ACTUAL/`dirname $F`
    scp -p $1:/$F $TMP/ACTUAL/$F >/dev/null 2>&1
  done
  ssh $1 "stat -c '%N %U %G %a %F' $( awk '{print $1}' $TMP/scs-stat |tr '\n' ' ' ) 2>/dev/null |sed 's/regular file/file/; s/symbolic link/symlink/'" |sed 's/[`'"'"']*//g' >$TMP/scs-actual
  # review differences
  echo "Analyzing configuration..."
  for F in $( find . -type f |sed 's%^\./%%' ); do
    if [ -f $TMP/ACTUAL/$F ]; then
      if [ `md5sum $TMP/{REFERENCE,ACTUAL}/$F |awk '{print $1}' |sort |uniq |wc -l` -gt 1 ]; then
        VALID=1
        echo "Deployed file and reference do not match: $F"
        get_yn DF "Do you want to review the differences (y/n/d) [Enter 'd' for diff only]? " d
        test "$DF" == "y" && vimdiff $TMP/{REFERENCE,ACTUAL}/$F
        test "$DF" == "d" && diff -c $TMP/{REFERENCE,ACTUAL}/$F
      fi
    elif [ `stat -c%s $TMP/REFERENCE/$F` -eq 0 ]; then
      echo "Ignoring empty file $F"
    else
      echo "WARNING: Remote system is missing file: $F"
      VALID=1
    fi
  done
  echo "Analyzing permissions..."
  diff $TMP/scs-stat $TMP/scs-actual
  if [ $? -ne 0 ]; then VALID=1; fi
  test $VALID -eq 0 && echo -e "\nSystem audit PASSED" || echo -e "\nSystem audit FAILED"
  exit $VALID
}

# check system configuration for validity (does it look like it will deploy OK?)
#
function system_check {
  test $# -gt 0 || err
  VALID=0
  # load the system
  IFS="," read -r NAME BUILD IP LOC EN <<< "$( grep -E "^$1," ${CONF}/system )"
  # look up the applications configured for the build assigned to this system
  if ! [ -z "$BUILD" ]; then
    # retrieve application related data
    for APP in $( build_application_list "$BUILD" ); do
      # get the file list per application
      FILES=( ${FILES[@]} `grep -E ",${APP}\$" ${CONF}/file-map |awk 'BEGIN{FS=","}{print $1}'` )
    done
  fi
  if [ ${#FILES[*]} -gt 0 ]; then
    for ((i=0;i<${#FILES[*]};i++)); do
      # get the file path based on the unique name
      IFS="," read -r FNAME FPTH FTYPE FOWNER FGROUP FOCTAL FTARGET FDESC <<< "$( grep -E "^${FILES[i]}," ${CONF}/file )"
      # remove leading '/' to make path relative
      FPTH=$( printf -- "$FPTH" |sed 's%^/%%' )
      # missing file
      if [ -z "$FNAME" ]; then printf -- "Error: '${FILES[i]}' is invalid. Critical error.\n"; VALID=1; continue; fi
      # skip if path is null (implies an error occurred)
      if [ -z "$FPTH" ]; then printf -- "Error: '$FNAME' has no path (index $i). Critical error.\n"; VALID=1; continue; fi
      # ensure the relative path (directory) exists
      mkdir -p $TMP/`dirname $FPTH`
      # how the file is created differs by type
      if [ "$FTYPE" == "file" ]; then
        # generate the file for this environment
        file_cat ${FILES[i]} --environment $EN --vars $NAME >$TMP/$FPTH
        if [ $? -ne 0 ]; then printf -- "Error generating file or replacing template variables, constants, and resources for ${FILES[i]}.\n"; VALID=1; continue; fi
      elif [ "$FTYPE" == "binary" ]; then
        # simply copy the file, if it exists
        test -f $CONF/binary/$EN/$FNAME
        if [ $? -ne 0 ]; then printf -- "Error: $FNAME does not exist for $EN.\n"; VALID=1; fi
      elif [ "$FTYPE" == "copy" ]; then
        # copy the file using scp or fail
        scp $FTARGET $TMP/ >/dev/null 2>&1
        if [ $? -ne 0 ]; then printf -- "Error: $FNAME is not available at '$FTARGET'\n"; VALID=1; fi
      fi
    done
  fi
  test $VALID -eq 0 && printf -- "System check PASSED\n" || printf -- "\nSystem check FAILED\n"
  exit $VALID
}

# output a list of constants and values assigned to a system
#
function system_constant_list {
  generic_choose system "$1" C && shift
  # load the system
  IFS="," read -r NAME BUILD IP LOC EN <<< "$( grep -E "^$C," ${CONF}/system )"
  mkdir -p $TMP; test -f $TMP/clist && :>$TMP/clist || touch $TMP/clist
  for APP in $( build_application_list "$BUILD" ); do
    constant_list_dedupe $TMP/clist $CONF/value/$EN/$APP >$TMP/clist.1
    cat $TMP/clist.1 >$TMP/clist
  done
  constant_list_dedupe $TMP/clist $CONF/value/$LOC/$EN >$TMP/clist.1; cat $TMP/clist.1 >$TMP/clist
  constant_list_dedupe $TMP/clist $CONF/value/$EN/constant >$TMP/clist.1; cat $TMP/clist.1 >$TMP/clist
  constant_list_dedupe $TMP/clist $CONF/value/constant >$TMP/clist.1; cat $TMP/clist.1 >$TMP/clist
  cat $TMP/clist
  rm -f $TMP/clist{,.1}
}

function system_create {
  start_modify
  # get user input and validate
  get_input NAME "Hostname"
  get_input BUILD "Build" --null --options "$( build_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  get_input LOC "Location" --options "$( location_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  get_input EN "Environment" --options "$( environment_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  while [[ "$IP" != "auto" && $( exit_status valid_ip "$IP" ) -ne 0 ]]; do get_input IP "Primary IP (auto to auto-select)"; done
  # automatic IP selection
  if [ "$IP" == "auto" ]; then
    get_input NETNAME "Network (loc-zone-alias)" --options "$( network_list_unformatted |grep -E "^${LOC}-" |awk '{print $1"-"$2 }' |sed ':a;N;$!ba;s/\n/,/g' )"
    IP=$( network_ip_list_available $NETNAME --limit 1 )
    valid_ip $IP || err "Automatic IP selection failed"
  fi
  # validate unique name
  grep -qE "^$NAME," $CONF/system && err "System already defined."
  # assign/reserve IP
  network_ip_assign $IP $NAME || err "Unable to assign IP address"
  # add
  printf -- "${NAME},${BUILD},${IP},${LOC},${EN}\n" >>$CONF/system
  commit_file system
}

function system_delete {
  # load the system
  IFS="," read -r NAME BUILD IP LOC EN <<< "$( grep -E "^$1," ${CONF}/system )"
  generic_delete system $1 || return
  # free IP address assignment
  network_ip_unassign $IP
}

# deploy release to system
#
function system_deploy {
  test $# -gt 0 || err
  nc -z -w 2 $1 22 >/dev/null 2>&1
  if [ $? -ne 0 ]; then printf -- "Unable to connect to remote system '$1'\n"; exit 1; fi
  printf -- "Generating release...\n"
  FILE=$( system_release $1 2>/dev/null |tail -n1 )
  if [ -z "$FILE" ]; then printf -- "Error generating release for '$1'\n"; exit 1; fi
  if ! [ -f "$FILE" ]; then printf -- "Unable to read release file\n"; exit 1; fi
  printf -- "Copying release to remote system...\n"
  scp $FILE $1: >/dev/null 2>&1
  if [ $? -ne 0 ]; then printf -- "Error copying release to '$1'\n"; exit 1; fi
  printf -- "Cleaning up...\n"
  rm -f $FILE
  printf -- "\nInstall like this:\n  ssh $1 \"tar xzf /root/`basename $FILE` -C /; cd /; ./scs-install.sh\"\n\n"
}

# destroy and permantantly delete a system
#
function system_deprovision {
  # !!FIXME!!
  echo "Not implemented"
}

# create a system
#
function system_provision {
  # abort handler
  test -f $ABORTFILE && err "Abort file in place - please remove $ABORTFILE to continue."
  # phase handler
  if [ $# -gt 1 ]; then
    case "$2" in
      --phase-2) system_provision_phase2 $1 ${@:3};;
      *) err "Invalid argument"
    esac
  fi
  # select and validate the system
  generic_choose system "$1" C && shift
  IFS="," read -r NAME BUILD IP LOC EN <<< "$( grep -E "^$C," ${CONF}/system )"
  #  - verify system is not already deployed
  nc -z -w 2 $IP 22 >/dev/null 2>&1 && err "System is alive; will not redeploy."
  if [ $( /bin/ping -c4 -n -s8 -w4 -q $IP |/bin/grep "0 received" |/usr/bin/wc -l ) -eq 0 ]; then err "System is alive; will not redeploy."; fi
  grep -qE '^'$( echo $IP |sed 's/\./\\./g' )'[ \t]' /etc/hosts
  if [ $? -eq 0 ]; then
    grep -E '^'$( echo $IP |sed 's/\./\\./g' )'[ \t]' /etc/hosts |grep -q "$NAME" || err "Another system with this IP is already configured in /etc/hosts."
  fi
  #  - look up the network for this IP
  NETNAME=$( network_list --match $IP )
  test -z "$NETNAME" && err "No network was found matching this system's IP address"
  #  - lookup the build network for this system
  network_list --build $LOC |grep -E '^available' | grep -qE " $NETNAME( |\$)"
  if [ $? -eq 0 ]; then
    BUILDNET=$NETNAME
  else
    BUILDNET=$( network_list --build $LOC |grep -E '^default' |awk '{print $2}' )
  fi
  #  - lookup network details for the build network (used in the kickstart configuration)
  #   --format: location,zone,alias,network,mask,cidr,gateway_ip,dns_ip,vlan,description,repo_address,repo_fs_path,repo_path_url,build,default-build\n
  read -r NETMASK GATEWAY DNS REPO_ADDR REPO_PATH REPO_URL <<< "$( grep -E "^${BUILDNET//-/,}," ${CONF}/network |awk 'BEGIN{FS=","}{print $5,$7,$8,$11,$12,$13}' )"
  valid_ip $GATEWAY || err "Build network does not have a defined gateway address"
  valid_ip $DNS || err "Build network does not have a defined DNS server"
  #  - locate available HVs
  LIST=$( hypervisor_list --network $NETNAME --network $BUILDNET --location $LOC --environment $EN | tr '\n' ' ' )
  test -z "$LIST" && err "There are no configured hypervisors capable of building this system"
  #  - poll list of HVs for availability then rank for free storage, free mem, and load
  HV=$( hypervisor_rank $LIST )
  test -z "$HV" && err "There are no available hypervisors at this time"
  #  - get the build and dest interfaces on the hypervisor
  HV_BUILD_INT=$( grep -E "^$BUILDNET,$HV," ${CONF}/hv-network |sed 's/^[^,]*,[^,]*,//' )
  HV_FINAL_INT=$( grep -E "^$NETNAME,$HV," ${CONF}/hv-network |sed 's/^[^,]*,[^,]*,//' )
  [[ -z "$HV_BUILD_INT" || -z "$HV_FINAL_INT" ]] && err "Selected hypervisor '$HV' is missing one or more interface mappings for the selected networks."
  #  - assign a temporary IP as needed
  if [ "$NETNAME" != "$BUILDNET" ]; then
    BUILDIP=$( network_ip_list_available $BUILDNET --limit 1 )
    valid_ip $IP || err "Automatic IP selection failed"
    # assign/reserve IP
    network_ip_assign $BUILDIP $NAME || err "Unable to assign IP address"
  else
    BUILDIP=$IP
  fi
  #  - load the architecture and operating system for the build
  IFS="," read -r OS ARCH DISK RAM <<< "$( grep -E "^$BUILD," ${CONF}/build |sed 's/^[^,]*,[^,]*,[^,]*,//' )"
  test -z "$OS" && err "Error loading build"
  #  - generate KS and deploy to local build server
  mkdir -p ${TMP}
  cp ${KSTEMPLATE}/${OS}.tpl ${TMP}/${NAME}.cfg
  cat <<_EOF >${TMP}/${NAME}.const
system.name $NAME
system.ip $BUILDIP
system.netmask $NETMASK
system.gateway $GATEWAY
system.dns $DNS
system.arch $ARCH
resource.sm-web $REPO_ADDR
_EOF
  parse_template ${TMP}/${NAME}.cfg ${TMP}/${NAME}.const 
  # hotfix for centos 5 -- this is the only package difference between i386 and x86_64
  if [[ "$OS" == "centos5" && "$ARCH" == "x86_64" ]]; then sed -i 's/kernel-PAE/kernel/' ${TMP}/${NAME}.cfg; fi
  #  - send custom kickstart file over to the local sm-web repo/mirror
  ssh -n $REPO_ADDR "mkdir -p $REPO_PATH" >/dev/null 2>&1
  scp -B ${TMP}/${NAME}.cfg $REPO_ADDR:$REPO_PATH/ >/dev/null 2>&1 || err "Unable to transfer kickstart configuration to build server"
  KS="http://${REPO_ADDR}/${REPO_URL}/${NAME}.cfg"
  #  - get disk size and memory
  test -z "$DISK" && DISK=$DEF_HDD
  test -z "$RAM" && RAM=$DEF_MEM
  #  - get globally unique mac address and uuid for the new server
  read -r UUID MAC <<< "$( $KVMUUID -q |sed 's/^[^:]*: //' |tr '\n' ' ' )"
  #  - kick off provision system
  echo "Creating virtual machine..."
  ssh -n $HV "/usr/local/utils/kvm-install.sh --arch $ARCH --disk $DISK --ip $BUILDIP --no-console --no-reboot --os $OS --quiet --ram $RAM --mac $MAC --uuid $UUID --ks $KS $NAME"
  #  - background task to monitor deployment (try to connect nc, sleep until connected, max wait of 3600s)
  nohup $0 system $NAME --provision --phase-2 $HV $BUILDIP $IP $HV_BUILD_INT $HV_FINAL_INT $BUILDNET $NETNAME $BUILD $LOC $EN </dev/null >/dev/null 2>&1 &
  #  - phase 1 complete
  echo "Build for $NAME at $LOC $EN has been started successfully and will continue in the background."
  return 0
}

# build phase 2
#
function system_provision_phase2 {
  # load arguments passed in from phase1
  read -r NAME HV BUILDIP IP HV_BUILD_INT HV_FINAL_INT BUILDNET NETNAME BUILD LOC EN <<< "$@"
  # wait a few minutes before even trying to connect
  sleep 180
  /usr/bin/logger -t "scs" "starting build phase 2 for $NAME at $BUILDIP"
  # max iterations, wait 60 minutes or 4 per min x 60 = 240
  #local i=0
  # confirm with targer server that base build is complete
  #while [ "$( nc $BUILDIP 80 )" != "OK" ]; do
  #  sleep 15
  #  i=$(( $i + 1 ))
  #  if [ $i -ge 240 ]; then errlog "Unable to connect to server $NAME at $BUILDIP for build phase 2"; fi
  #  check_abort "Was waiting for server $NAME at $BUILDIP to finish CentOS install"
  #done
  #  - sleep 30 or so
  #sleep 30
  #  - connect to hypervisor, wait until vm is off, then start it up again
  ssh -n $HV "while [ \"\$( /usr/bin/virsh dominfo $NAME |/bin/grep -i state |/bin/grep -i running |/usr/bin/wc -l )\" -gt 0 ]; do sleep 5; done; sleep 5; /usr/bin/virsh start $NAME" >/dev/null 2>&1
  /usr/bin/logger -t "scs" "successfully started $NAME"
  #  - check for abort
  check_abort
  #  - wait for vm to come up
  sleep 30
  while [ "$( exit_status nc -z -w 2 $BUILDIP 22 )" -ne 0 ]; do sleep 5; check_abort; done
  /usr/bin/logger -t "scs" "ssh connection succeeded to $NAME"
  while [ "$( exit_status ssh -n -o \"StrictHostKeyChecking no\" $BUILDIP uptime )" -ne 0 ]; do sleep 5; check_abort; done
  /usr/bin/logger -t "scs" "$NAME verified UP"
  #  - load the role
  ROLE=$( grep -E "^$BUILD," ${CONF}/build |awk 'BEGIN{FS=","}{print $2}' )
  #  - install_build
  system_push_build_scripts $BUILDIP >/dev/null 2>&1 || logerr "Error pushing build scripts to remote server $NAME at $IP"
  /usr/bin/logger -t "scs" "build scripts deployed to $NAME"
  #  - sysbuild_install (do not change the IP here)
  system_start_remote_build $BUILDIP $ROLE >/dev/null 2>&1 || logerr "Error starting remote build on $NAME at $IP"
  #    - when complete launch nc -l 80 to send response back to provisioning server - install success/failure

errlog "finished base system build but phase2 is incomplete.  $NAME should be online at $BUILDIP"

  #  - clean up kickstart file
  #  - background task to monitor install
  #  - sleep 60 or so
  #  - wait for vm to come up
  #  - ship over scs configuration
  #  * - ship over latest code release
  #  - install configuration
  #  - install code
  #  - update vm network configuration for permanent address and vlan
  #    - if necessary, free temporary IP (unassign)
  #  - shut off vm
  #  - sleep 30 or so
  #  - connect to hypervisor, wait until vm is off
  #  - change VM vlan and redefine
  #  - start vm
  #  - update /etc/hosts and push-hosts (system_update_push_hosts)
  #  - fin
  #  
}

# deploy the current system build scripts to a remote server
#   this function replaces 'install_build' previously found in /root/.bashrc
#
function system_push_build_scripts {
  if [[ $# -lt 1 || $# -gt 2 ]]; then echo -e "Usage: install_build hostname|ip [path]\n"; return 1; fi
  if [ "`whoami`" != "root" ]; then echo "You must be root"; return 2; fi
  if ! [ -z "$2" ]; then
    test -d "$2" || return 3
    SRCDIR="$2"
  else
    SRCDIR=$BUILDSRC
  fi
  test -d "$SRCDIR" || return 4
  nc -z -w2 $1 22
  if [ $? -ne 0 ]; then
    echo "Remote host did not respond to initial request; attempting to force network discovery..." >&2
    ping -c 2 -q $1 >/dev/null 2>&1
    nc -z -w2 $1 22 || return 5
  fi
  cat /root/.ssh/known_hosts >/root/.ssh/known_hosts.$$
  sed -i "/$( printf -- "$1" |sed 's/\./\\./g' )/d" /root/.ssh/known_hosts
  ssh -o "StrictHostKeyChecking no" $1 mkdir ESG 2>/dev/null
  scp -p -r "$SRCDIR" $1:ESG/ >/dev/null 2>&1 || echo "Error transferring files" >&2
  cat /root/.ssh/known_hosts.$$ >/root/.ssh/known_hosts
  /bin/rm /root/.ssh/known_hosts.$$
  return 0
}

function system_list {
  NUM=$( wc -l ${CONF}/system |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined system${S}."
  test $NUM -eq 0 && return
  awk 'BEGIN{FS=","}{print $1}' ${CONF}/system |sort |sed 's/^/   /'
}

function system_release {
  test $# -gt 0 || err
  # load the system
  IFS="," read -r NAME BUILD IP LOC EN <<< "$( grep -E "^$1," ${CONF}/system )"
  # create the temporary directory to store the release files
  mkdir -p $TMP $RELEASEDIR
  AUDITSCRIPT="$TMP/scs-audit.sh"
  RELEASEFILE="$NAME-release-`date +'%Y%m%d-%H%M%S'`.tgz"
  RELEASESCRIPT="$TMP/scs-install.sh"
  STATFILE="$TMP/scs-stat"
  FILES=()
  # create the audit script
  printf -- "#!/bin/bash\n# scs audit script for $NAME, generated on `date`\n#\n\n" >$AUDITSCRIPT
  printf -- "# warn if not target host\ntest \"\`hostname\`\" == \"$NAME\" || echo \"WARNING - running on alternate system - can not reliably check ownership!\"\n\n" >>$AUDITSCRIPT
  printf -- "PASS=0\n" >>$AUDITSCRIPT
  # create the installation script
  printf -- "#!/bin/bash\n# scs installation script for $NAME, generated on `date`\n#\n\n" >$RELEASESCRIPT
  printf -- "# safety first\ntest \"\`hostname\`\" == \"$NAME\" || exit 2\n\n" >>$RELEASESCRIPT
  printf -- "logger -t scs \"starting installation for $LOC $EN $NAME, generated on `date`\"\n\n" >>$RELEASESCRIPT
  # create the stat file
  touch $STATFILE
  # look up the applications configured for the build assigned to this system
  if ! [ -z "$BUILD" ]; then
    # retrieve application related data
    for APP in $( build_application_list "$BUILD" ); do
      # get the file list per application
      FILES=( ${FILES[@]} `grep -E ",${APP}\$" ${CONF}/file-map |awk 'BEGIN{FS=","}{print $1}'` )
    done
  fi
  # generate the release configuration files
  if [ ${#FILES[*]} -gt 0 ]; then
    for ((i=0;i<${#FILES[*]};i++)); do
      # get the file path based on the unique name
      IFS="," read -r FNAME FPTH FTYPE FOWNER FGROUP FOCTAL FTARGET FDESC <<< "$( grep -E "^${FILES[i]}," ${CONF}/file )"
      # remove leading '/' to make path relative
      FPTH=$( printf -- "$FPTH" |sed 's%^/%%' )
      # alternate octal representation
      FOCT=$( printf -- $FOCTAL |sed 's%^0%%' )
      # skip if path is null (implies an error occurred)
      test -z "$FPTH" && continue
      # ensure the relative path (directory) exists
      mkdir -p $TMP/`dirname $FPTH`
      # how the file is created differs by type
      if [ "$FTYPE" == "file" ]; then
        # generate the file for this environment
        file_cat ${FILES[i]} --environment $EN --vars $NAME --silent >$TMP/$FPTH || err "Error generating $EN file for ${FILES[i]}"
      elif [ "$FTYPE" == "directory" ]; then
        mkdir -p $TMP/$FPTH
      elif [ "$FTYPE" == "symlink" ]; then
        # tar will preserve the symlink so go ahead and create it
        ln -s $FTARGET $TMP/$FPTH
      elif [ "$FTYPE" == "binary" ]; then
        # simply copy the file, if it exists
        test -f $CONF/binary/$EN/$FNAME || err "Error - binary file '$FNAME' does not exist for $EN."
        cat $CONF/binary/$EN/$FNAME >$TMP/$FPTH
      elif [ "$FTYPE" == "copy" ]; then
        # copy the file using scp or fail
        scp $FTARGET $TMP/$FPTH >/dev/null 2>&1 || err "Error - an unknown error occurred copying source file '$FTARGET'."
      elif [ "$FTYPE" == "download" ]; then
        # add download to command script
        printf -- "# download '$FNAME'\n" >>$RELEASESCRIPT
        printf -- "curl -f -k -L --retry 1 --retry-delay 10 -s --url \"$FTARGET\" -o \"/$FPTH\" >/dev/null 2>&1 || logger -t scs \"error downloading '$FNAME'\"\n" >>$RELEASESCRIPT
      elif [ "$FTYPE" == "delete" ]; then
        # add delete to command script
        printf -- "# delete '$FNAME' if it exists\n" >>$RELEASESCRIPT
        printf -- "if [[ ! -z \"$FPTH\" && \"$FPTH\" != \"/\" && -e \"/$FPTH\" ]]; then /bin/rm -rf \"/$FPTH\"; logger -t scs \"deleting path '/$FPTH'\"; fi\n" >>$RELEASESCRIPT
        # add audit check 
        printf -- "if [[ ! -z \"$FPTH\" && \"$FPTH\" != \"/\" && -e \"/$FPTH\" ]]; then PASS=1; echo \"File should not exist: '/$FPTH'\"; fi\n" >>$AUDITSCRIPT
      fi
      # stage permissions for audit and processing
      if [ "$FTYPE" != "delete" ]; then
        # audit
        printf -- "if [ -f \"$FPTH\" ]; then\n" >>$AUDITSCRIPT
        printf -- "  if [ \"\$( stat -c'%%a %%U:%%G' \"$FPTH\" )\" != \"$FOCT $FOWNER:$FGROUP\" ]; then PASS=1; echo \"'\$( stat -c'%%a %%U:%%G' \"$FPTH\" )' != '$FOCT $FOWNER:$FGROUP' on $FPTH\"; fi\n" >>$AUDITSCRIPT
        printf -- "else\n  echo \"Error: $FPTH does not exist!\"\n  PASS=1\nfi\n" >>$AUDITSCRIPT
        printf -- "# set permissions on '$FNAME'\nchown $FOWNER:$FGROUP /$FPTH\nchmod $FOCTAL /$FPTH\n" >>$RELEASESCRIPT
        # stat
        if [ "$FTYPE" == "symlink" ]; then
          printf -- "/$FPTH -> $FTARGET root root 777 $FTYPE\n" |sed 's/binary$/file/' >>$STATFILE
        else
          printf -- "/$FPTH $FOWNER $FGROUP ${FOCT//^0/} $FTYPE\n" |sed 's/binary$/file/' >>$STATFILE
        fi
      fi
    done
    # finalize audit script
    printf -- "\nif [ \$PASS -eq 0 ]; then echo \"Audit PASSED\"; else echo \"Audit FAILED\"; fi\nexit \$PASS\n" >>$AUDITSCRIPT
    chmod +x $AUDITSCRIPT
    # finalize installation script
    printf -- "\nlogger -t scs \"installation complete\"\n" >>$RELEASESCRIPT
    chmod +x $RELEASESCRIPT
    # generate the release
    pushd $TMP >/dev/null 2>&1
    tar czf $RELEASEDIR/$RELEASEFILE *
    popd >/dev/null 2>&1
    printf -- "Complete. Generated release:\n$RELEASEDIR/$RELEASEFILE\n"
  else
    err "No managed configuration files."
  fi
}

# output list of resources assigned to a system
#
function system_resource_list {
  generic_choose system "$1" C && shift
  # load the system
  IFS="," read -r NAME BUILD IP LOC EN <<< "$( grep -E "^$C," ${CONF}/system )"
  for APP in $( build_application_list "$BUILD" ); do
    # get any localized resources for the application
    grep -E ",application,$LOC:$EN:$APP," ${CONF}/resource |cut -d',' -f1,2,5
  done
  # add any host assigned resources to the list
  grep -E ",host,$NAME," ${CONF}/resource |cut -d',' -f1,2,5
}

function system_show {
  # local variables
  FILES=()
  # input validation
  test $# -eq 1 || err "Provide the system name"
  grep -qE "^$1," ${CONF}/system || err "Unknown system"
  # load the system
  IFS="," read -r NAME BUILD IP LOC EN <<< "$( grep -E "^$1," ${CONF}/system )"
  # output the status/summary
  printf -- "Name: $NAME\nBuild: $BUILD\nIP: $IP\nLocation: $LOC\nEnvironment: $EN\n"
  # look up the applications configured for the build assigned to this system
  if ! [ -z "$BUILD" ]; then
    NUM=$( build_application_list "$BUILD" |wc -l )
    if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
    echo -e "\nThere ${A} ${NUM} linked application${S}."
    if [ $NUM -gt 0 ]; then
      build_application_list "$BUILD" |sed 's/^/   /'
      # retrieve application related data
      for APP in $( grep -E ",${BUILD}," ${CONF}/application |awk 'BEGIN{FS=","}{print $1}' ); do
        # get the file list per application
        FILES=( ${FILES[@]} `grep -E ",${APP}\$" ${CONF}/file-map |awk 'BEGIN{FS=","}{print $1}'` )
      done
    fi
  fi
  # pull system resources
  RSRC=( `system_resource_list "$NAME"` )
  # show assigned resources (by host, application + environment)
  if [ ${#RSRC[*]} -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo -e "\nThere ${A} ${#RSRC[*]} linked resource${S}."
  if [ ${#RSRC[*]} -gt 0 ]; then for ((i=0;i<${#RSRC[*]};i++)); do
    printf -- "${RSRC[i]}\n" |awk 'BEGIN{FS=","}{print $2,$1,$3}'
  done; fi |column -t |sed 's/^/   /'
  # output linked configuration file list
  if [ ${#FILES[*]} -gt 0 ]; then
    printf -- "\nManaged configuration files:\n"
    for ((i=0;i<${#FILES[*]};i++)); do
      grep -E "^${FILES[i]}," $CONF/file |awk 'BEGIN{FS=","}{print $1,$2}'
    done |sort |uniq |column -t |sed 's/^/   /'
  else
    printf -- "\nNo managed configuration files."
  fi
  printf -- '\n'
}

function system_start_remote_build {
  if [[ $# -eq 0 || -z "$1" ]]; then echo -e "Usage: sysbuild_install current-ip [role]\n"; return 1; fi
  if [ "`whoami`" != "root" ]; then echo "You must be root"; return 2; fi
  valid_ip $1 || return 1
  # confirm availabilty
  nc -z -w2 $1 22
  if [ $? -ne 0 ]; then echo "Host is down. Aborted."; return 2; fi
  # remove any stored keys for the current and target IPs since this is a new build
  cat /root/.ssh/known_hosts >/root/.ssh/known_hosts.$$
  sed -i "/$( printf -- "$1" |sed 's/\./\\./g' )/d" /root/.ssh/known_hosts
  diff /root/.ssh/known_hosts{.$$,}; rm -f /root/.ssh/known_hosts.$$
  # kick-off install and return
  if [ -z "$2" ]; then
    ssh -o "StrictHostKeyChecking no" $1 "nohup ESG/system-builds/role.sh >/dev/null 2>&1 </dev/null &"
  else
    ssh -o "StrictHostKeyChecking no" $1 "nohup ESG/system-builds/role.sh $2 >/dev/null 2>&1 </dev/null &"
  fi
  return 0
}

function system_update {
  start_modify
  generic_choose system "$1" C && shift
  IFS="," read -r NAME BUILD ORIGIP LOC EN <<< "$( grep -E "^$C," ${CONF}/system )"
  get_input NAME "Hostname" --default "$NAME"
  get_input BUILD "Build" --default "$BUILD" --null --options "$( build_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  while ! $(valid_ip "$IP"); do get_input IP "Primary IP" --default "$ORIGIP"; done
  get_input LOC "Location" --default "$LOC" --options "$( location_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )" 
  get_input EN "Environment" --default "$EN" --options "$( environment_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  sed -i 's/^'$C',.*/'${NAME}','${BUILD}','${IP}','${LOC}','${EN}'/' ${CONF}/system
  # handle IP change
  if [ "$IP" != "$ORIGIP" ]; then
    network_ip_unassign $ORIGIP
    network_ip_assign $IP $NAME
  fi
  commit_file system
}

function system_update_push_hosts {
  # !!FIXME!! extracted from original sysbuild_install -- needs updated and revised
exit 1
#  if [ "`hostname`" != "hqpcore-bkup01" ]; then echo "Run from hqpcore-bkup01"; return 3; fi
#  # hostname and IP should either both be unique, or both registered together
#  ENTRY=$( grep -E '[ '$'\t'']'$1'[ '$'\t'']' /etc/hosts ); H=$?
#  echo "$ENTRY" |grep -qE '^'${2//\./\\.}'[ '$'\t'']';      I=$?
#  grep -qE '^'${2//\./\\.}'[ '$'\t'']' /etc/hosts;          J=$?
#  if [ $(( $H + $I )) -eq 0 ]; then
#    # found together; this is an existing host
#    echo "Host entry exists."
#  elif [ $(( $H + $J )) -eq 2 ]; then
#    echo "Adding host entry..."
#    cat /etc/hosts >/etc/hosts.sysbuild
#    echo -e "$2\t$1\t\t$1.example.com" >>/etc/hosts
#    diff /etc/hosts{.sysbuild,}; echo
#    # sync
#    /usr/local/etc/push-hosts.sh
#  elif [ $H -eq 0 ]; then
#    echo "The host name you provided ($1) is already registered with a different IP address in /etc/hosts. Aborted."
#    return 1
#  elif [ $J -eq 0 ]; then
#    echo "The IP address you provided ($2) is already registered with a different host name in /etc/hosts. Aborted."
#    return 1
#  fi
#  # add host to lpad as needed
#  grep -qE '^'$1':' /usr/local/etc/lpad/hosts/managed-hosts
#  if [ $? -ne 0 ]; then
#    echo "Adding lpad entry..."
#    echo "$1:linux" >>/usr/local/etc/lpad/hosts/managed-hosts
#  fi
}

# generate all system variables and settings
#
function system_vars {
  test $# -eq 1 || err "System name required"
  # load the system
  IFS="," read -r NAME BUILD IP LOC EN <<< "$( grep -E "^$1," ${CONF}/system )"
  # output system data
  echo -e "system.name $NAME\nsystem.build $BUILD\nsystem.ip $IP\nsystem.location $LOC\nsystem.environment $EN"
  # output network data, if available
  local SYSNET=$( network_list --match $IP )
  if [ ! -z "$SYSNET" ]; then
    IFS="," read -r LOC ZONE ALIAS NET MASK BITS GW DNS VLAN DESC REPO_ADDR REPO_PATH REPO_URL BUILD DEFAULT_BUILD NTP <<< "$( grep -E "^${SYSNET//-/,}," ${CONF}/network )"
    echo -e "system.zone ${ZONE}-${ALIAS}\nsystem.network $NET\nsystem.netmask $MASK\nsystem.gateway $GW"
    echo "system.broadcast $( ipadd $NET $(( $( cdr2size $BITS ) -1 )) )"
    if [ ! -z "$DNS" ]; then echo "system.dns $DNS"; fi
    if [ ! -z "$NTP" ]; then echo "system.ntp $NTP"; fi
    if [ ! -z "$VLAN" ]; then echo "system.vlan $VLAN"; fi
  fi
  # pull system resources
  for R in $( system_resource_list $NAME ); do
    IFS="," read -r TYPE VAL RN <<< "$R"
    test -z "$RN" && RN="$TYPE"
    if [ "$TYPE" == "cluster_ip" ]; then
      echo "resource.$RN $VAL"
    else
      echo "system.$RN $VAL"
    fi
  done
  # pull constants
  for CNST in $( system_constant_list $NAME ); do
    IFS="," read -r CN VAL <<< "$CNST"
    echo "constant.$( printf -- "$CN" |tr 'A-Z' 'a-z' ) $VAL"
  done
}


  #####  ####### ####### ####### ### #     #  #####   #####  
 #     # #          #       #     #  ##    # #     # #     # 
 #       #          #       #     #  # #   # #       #       
  #####  #####      #       #     #  #  #  # #  ####  #####  
       # #          #       #     #  #   # # #     #       # 
 #     # #          #       #     #  #    ## #     # #     # 
  #####  #######    #       #    ### #     #  #####   ##### 

# settings
#
# file to look for to immediately abort all background tasks
#
ABORTFILE=/tmp/scs-abort-all
#
# path to build scripts
#
BUILDSRC=/home/wstrucke/ESG/system-builds
#
# local root for scs storage files, settings, and git repository
CONF=/usr/local/etc/lpad/app-config
#
# default size of a new system's HDD in GB
DEF_HDD=40
#
# default amount of RAM for a new system in MB
#
DEF_MEM=1024
#
# path to kickstart templates (centos6-i386.tpl, etc...)
KSTEMPLATE=/home/wstrucke/ESG/system-builds/kickstart-files/templates
#
# path to kvm-uuid.sh, required for full build automation tasks
KVMUUID="`dirname $0`/kvm-uuid"
#
# list of architectures for builds -- each arch in the list must be available
#   for each OS version (below)
OSARCH="i386,x86_64"
#
# list of operating systems for builds
OSLIST="centos4,centos5,centos6"
#
# local path to store release archives
RELEASEDIR=/bkup1/scs-release
#
# path to the temp file for patching configuration files
TMP=/tmp/generate-patch.$$


 #     #    #    ### #     # 
 ##   ##   # #    #  ##    # 
 # # # #  #   #   #  # #   # 
 #  #  # #     #  #  #  #  # 
 #     # #######  #  #   # # 
 #     # #     #  #  #    ## 
 #     # #     # ### #     #

# set local variables
APP=""
ENV=""
FILE=""
USERNAME=""

trap cleanup_and_exit EXIT INT

# initialize
test "`whoami`" == "root" || err "What madness is this? Ye art not auth'riz'd to doeth that."
which git >/dev/null 2>&1 || err "Please install git or correct your PATH"
test -x $KVMUUID || err "kvm-uuid.sh was not found at the expected path and is required for some operations"
test $# -ge 1 || usage

# the path to the configuration is configurable as an argument
if [[ "$1" == "-c" || "$1" == "--config" ]]; then
  shift;
  test -d "`dirname $1`" && CONF="$1" || usage
  shift; echo "chroot: $CONF"
fi

# first run check
if ! [ -d $CONF ]; then
  read -r -p "Configuration not found - this appears to be the first time running this script.  Do you want to initialize the configuration (y/n)? " P
  P=$( echo "$P" |tr 'A-Z' 'a-z' )
  test "$P" == "y" && initialize_configuration || exit 1
fi

# special case for detailed help without a space
if [[ "${!#}" =~ \?$ ]]; then help $@; exit 0; fi

# get subject
SUBJ="$( expand_subject_alias "$( echo "$1" |tr 'A-Z' 'a-z' )")"; shift

# intercept non subject/verb commands
if [ "$SUBJ" == "commit" ]; then stop_modify $@; exit 0; fi
if [ "$SUBJ" == "cancel" ]; then cancel_modify $@; exit 0; fi
if [ "$SUBJ" == "diff" ]; then diff_master; exit 0; fi
if [ "$SUBJ" == "status" ]; then git_status; exit 0; fi
if [ "$SUBJ" == "help" ]; then help $@; exit 0; fi

# get verb
VERB="$( expand_verb_alias "$( echo "$1" |tr 'A-Z' 'a-z' )")"; shift

# if no verb is provided default to list, since it is available for all subjects
if [ -z "$VERB" ]; then VERB="list"; fi

# validate subject and verb
printf -- " application build constant environment file hypervisor location network resource system " |grep -q " $SUBJ "
[[ $? -ne 0 || -z "$SUBJ" ]] && usage
if [[ "$SUBJ" != "resource" && "$SUBJ" != "location" && "$SUBJ" != "system" && "$SUBJ" != "network" && "$SUBJ" != "hypervisor" ]]; then
  printf -- " create delete list show update edit file application constant environment cat " |grep -q " $VERB "
  [[ $? -ne 0 || -z "$VERB" ]] && usage
fi
[[ "$VERB" == "edit" && "$SUBJ" != "file" ]] && usage
[[ "$VERB" == "cat" && "$SUBJ" != "file" ]] && usage
[[ "$VERB" == "file" && "$SUBJ" != "application" ]] && usage
[[ "$VERB" == "application" && "$SUBJ" != "environment" ]] && usage
[[ "$VERB" == "constant" && "$SUBJ" != "environment" ]] && usage
[[ "$VERB" == "environment" && "$SUBJ" != "location" ]] && usage

# call function with remaining arguments
if [ "$SUBJ" == "resource" ]; then
  case "$VERB" in
    create|delete|list|show|update) eval ${SUBJ}_${VERB} $@;;
    *) resource_byval "$VERB" $@;;
  esac
elif [ "$SUBJ" == "system" ]; then
  case "$VERB" in
    create|delete|list|show|update) eval ${SUBJ}_${VERB} $@;;
    *) system_byname "$VERB" $@;;
  esac
elif [ "$SUBJ" == "location" ]; then
  case "$VERB" in
    create|delete|list|show|update) eval ${SUBJ}_${VERB} $@;;
    *) location_environment "$VERB" $@;;
  esac
elif [ "$SUBJ" == "hypervisor" ]; then
  case "$VERB" in
    create|delete|list|show|update) eval ${SUBJ}_${VERB} $@;;
    *) hypervisor_byname "$VERB" $@;;
  esac
elif [ "$SUBJ" == "network" ]; then
  case "$VERB" in
    create|delete|list|show|update) eval ${SUBJ}_${VERB} $@;;
    *) network_byname "$VERB" $@;;
  esac
else
  eval ${SUBJ}_${VERB} $@
fi
