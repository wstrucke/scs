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
#     build                                                file
#     constant                                             constant index
#     environment                                          file
#     env                                                  directory
#     env/<environment>/binary                             directory
#     env/<environment>/constant                           file
#     env/<environment>/by-app                             directory
#     env/<environment>/by-app/<application>               file
#     env/<environment>/by-loc                             directory
#     env/<environment>/by-loc/<location>                  file
#     file                                                 file
#     file-map                                             application to file map
#     hv-environment                                       file
#     hv-network                                           file
#     hv-system                                            file
#     hypervisor                                           file
#     location                                             file
#     network                                              file
#     net                                                  directory
#     net/a.b.c.0                                          file with IP index for IPAM component
#     net/a.b.c.0-routes                                   static routes for all hosts in the network
#     resource                                             file
#     schema                                               file
#     system                                               file
#     template/                                            directory containing global application templates
#.....template/cluster/<environment>/                      directory containing template patches for an environment w/clustering (proposed)
#     template/patch/<environment>/                        directory containing template patches for the environment
#     value/                                               directory containing constant definitions
#     value/by-app/                                        directory
#     value/by-app/<application>                           file (global application)
#     value/constant                                       file (global)
#     <location>/                                          directory
#     <location>/network                                   file to list networks available at the location
#     <location>/<environment>                             file
#
# A constant has a globally unique name with a fixed value in the scope it is defined in and is in only one scope (never duplicated).
#
# A resource is a pre-defined type with a globally unique value (e.g. an IP address).  That value can be assigned to either a host or an
# application in an environment.
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
#   --search: [FORMAT:application]
#   --sort: alphabetical
#   --storage:
#   ----name            a unique name for the application
#   ----alias           an alias for the application (currently unused)
#   ----build           the build the application is installed on
#   ----cluster         y/n - whether or not the application supports load balancing
#
#   build
#   --description: server builds
#   --format: name,role,description,os,arch,disk,ram,parent\n
#   --search: [FORMAT:build]
#   --sort: alphabetical
#   --storage:
#   ----name            a unique name for the build
#   ----role            name of the role provided to the system build script (role.sh) during provisioning
#   ----description     human readable description
#   ----os              operating system (passed into the kickstart/vm build script)
#   ----arch            architecture (passed into the kickstart/vm build script)
#   ----disk            default disk size in GB
#   ----ram             default memory allocated in MB
#   ----parent          optional parent build name
#
#   constant
#   --description: variables used to generate configurations
#   --format: name,description\n
#   --search: [FORMAT:constant]
#   --sort: alphabetical
#   --storage:
#   ----name            a unique name for the constant
#   ----description     human readable description
#
#   environment
#   --description: 'stacks' or groups of instances of all or a subset of applications
#   --format: name,alias,description\n
#   --search: [FORMAT:environment]
#   --sort: alphabetical
#   --storage:
#   ----name            a unique name for the environment
#   ----alias           a unique alias... so far as i know this is not used anywhere
#   ----description     human readable description
#
#   env/<environment>/constant
#   --description: environment scoped values for constants
#   --format: constant,value\n
#   --search: [FORMAT:value/env/constant]
#   --storage:
#   ----constant        name of the constant
#   ----value           value (commas and new lines are not allowed)
#
#   env/<environment>/by-app/<application>
#   --description: application in environment scoped values for constants
#   --format: constant,value\n
#   --search: [FORMAT:value/env/app]
#   --storage:
#   ----constant        name of the constant
#   ----value           value (commas and new lines are not allowed)
#
#   env/<environment>/by-loc/<location>
#   --description: enironment at a specific site scoped values for constants
#   --format: constant,value\n
#   --search: [FORMAT:value/loc/constant]
#   --storage:
#   ----constant        name of the constant
#   ----value           value (commas and new lines are not allowed)
#
#   file
#   --description: files installed on servers
#   --format: name,path,type,owner,group,octal,target,description\n
#   --search: [FORMAT:file]
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
#   --format: filename,application,environment_flags\n
#   --search: [FORMAT:file-map]
#   --storage:
#   ----filename           the name of the file
#   ----application        the name of the application
#   ----environment_flags  optional set of flags indicating which environments this file should appear in
#                            can be 'all' or 'none' with modifiers '+' (to add to none) or '-' (to
#                            subtract from all).
#                            e.g.: 'none+test+production' or 'all-beta'
#                            the '+' flag is not valid with all and '-' is not valid with none
#                            an environment with a hyphen in the name will have it translated to an underscore
#                              in the configuration for flags, i.e. "my-environment" is stored as "my_environment"
#
#   hv-environment
#   --description: hypervisor/environment map
#   --format: environment,hypervisor
#   --search: [FORMAT:hv-environment]
#   --storage:
#   ----environment     the name of the 'environment'
#   ----hypervisor      the name of the 'hypervisor'
#
#   hv-network
#   --description: hypervisor/network map
#   --format: loc-zone-alias,hv-name,interface
#   --search: [FORMAT:hv-network]
#   --storage:
#   ----loc-zone-alias  network 'location,zone,alias' in the usual format
#   ----hv-name         the hostname of the hypervisor
#   ----interface       the name of the interface on the hypervisor for this network
#
#   hv-system
#   --description: hypervisor/vm map
#   --format: system,hypervisor,preferred
#   --search: [FORMAT:hv-system]
#   --storage:
#   ----system          the name of the 'system' (or virtual machine)
#   ----hypervisor      the name of the 'hypervisor'
#   ----preferred       y/n - if 'y' this is the preferred hypervisor the system runs on
#
#   hypervisor
#   --description: virtual machine host servers
#   --format: name,management-ip,location,vm-path,vm-min-disk(mb),min-free-mem(mb),enabled
#   --search: [FORMAT:hypervisor]
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
#   --search: [FORMAT:location]
#   --storage:
#   ----code            code or alias for the location
#   ----name            name of the location/site
#   ----description     location description
#
#   network
#   --description: network registry
#   --format: location,zone,alias,network,mask,cidr,gateway_ip,static_routes,dns_ip,vlan,description,repo_address,repo_fs_path,
#             repo_path_url,build,default-build,ntp_ip,dhcp_ip\n
#   --search: [FORMAT:network]
#   --storage:
#   ----location        location code for the network (primary key part 1/3)
#   ----zone            network zone assignment (primary key part 2/3)
#   ----alias           network name or alias (primary key part 3/3)
#   ----network         network address in IP notation
#   ----mask            network mask in IP notation
#   ----cidr            network mask bits (combine with 'network' to form CIDR notation, i.e. 'network/cidr')
#   ----gateway_ip      network default gateway in IP notation
#   ----static_routes   'y' or 'n', yes if the network has static routes to deploy to each server
#   ----dns_ip          network default primary DNS in IP notation
#   ----vlan            network vlan tag/number (numeric)
#   ----description     description of the network
#   ----repo_address    ip address or hostname of the repository/mirror for installing an OS or related packages for the network
#   ----repo_fs_path    absolute path on the build server to a web accessible folder scs can place kickstart configs in
#                         (no trailing slash), e.g. /var/web/building/scs
#   ----repo_path_url   absolute path from the client web browser to the repo_fs_path, no leading or trailing slash, e.g. 'building/scs'
#   ----build           'y' or 'n', yes if this network has DHCP with PXE to boot into a network install image
#   ----default-build   'y' or 'n', yes if this network is the *default* build network at the location
#   ----ntp_ip          default ntp server in IP notation
#   ----dhcp_ip         ip of the network dhcp server (to look up leases) -- optional
#
#   net/a.b.c.0
#   --description: subnet ip assignment registry
#   --format: octal_ip,cidr_ip,reserved,dhcp,hostname,host_interface,comment,interface_comment,owner\n
#   --search: [FORMAT:net/network]
#   --storage:
#   ----octal_ip           octal representation of the ip address (e.g. 3232235521)
#   ----cidr_ip            cidr representation of the ip address (e.g. 192.168.0.1)
#   ----reserved           'y' or 'n', yes if the ip address is reserved and should not be assigned
#   ----dhcp               'y' or 'n', yes if the ip address is assigned via a dhcp server
#   ----hostname           the hostname of the system or device assigned to this address
#   ----host_interface     the interface on the host the ip is assigned on (optional)
#   ----comment            a human readable comment for the address
#   ----interface_comment  a human readable comment for the system or device interface
#   ----owner              username who allocated the IP address
#
#   net/a.b.c.0-routes
#   --description: static routes to be applied to all hosts in the network
#   --format: device net network netmask netmask gw gateway
#   --search: [FORMAT:net/routes]
#   --example: any net 10.1.12.0 netmask 255.255.255.0 gw 192.168.0.1
#
#   resource
#   --description: arbitrary 'things' (such as IP addresses for a specific purpose) assigned to
#                    systems and used to generate configs
#   --format: type,value,assign_type,assign_to,name,description\n
#   --search: [FORMAT:resource]
#   --storage:
#   ----type            one of 'ip', 'cluster_ip', or 'ha_ip': the type of resource. this should be extensible.
#   ----value           the resource value. since all types are IP addresses at this time, this is the IP address.
#   ----assign_type     type of assignment, either 'application' or 'host'. this determines what is in the next field.
#   ----assign_to       'not assigned' or the assignment string, based on the assign_type (host or application)
#                         for 'assign_type' of application, a string identifying the application with the components
#                           'location:environment:application'. e.g.: 'location1:beta:my_sweet_app'
#                         for 'assign_type' of host this is the name of the host
#   ----name            an optional alias or name for this resource. when a resource is linked to an application it is referenced
#                         by the type (e.g. system.cluster_ip) *EXCEPT* when a name is provided.  this is very useful when a
#                         system or application has multiple resources of the same type making the assignment otherwise
#                         ambiguous.
#   ----description     a comment or description about this resource for reference
#
#   schema
#   --description: the version of the configuration file schema in the repository
#   --format: version\n
#   --search: [FORMAT:schema]
#   --storage:
#   ----version         the version of the schema
#
#   system
#   --description: servers
#   --format: name,build,ip,location,environment,virtual,backing_image,overlay,locked,build_date\n
#   --search: [FORMAT:system]
#   --storage:
#   ----name            the hostname
#   ----build           build name
#   ----ip              ip address for the system in IP notation or 'dhcp'
#   ----location        location name
#   ----environment     environment name
#   ----virtual         'y' or 'n', yes if this is a virtual machine
#   ----backing_image   'y' or 'n', yes if this is a VM and is unregistered, always SHUT OFF, and read-only as a backing image for overlays
#   ----overlay         'null', 'auto', or '<name>'. null=>full system (a.k.a. single), auto=>auto-select base system/image during
#                         provisioning, or the name of the base system
#   ----locked          'y' or 'n', yes if this system is LOCKED an changes should be restricted (especially provision/deprovision)
#   ----build_date      unix timestamp of the last time this system was built (by scs of course)
#
#   value/constant
#   --description: global values for constants
#   --format: constant,value\n
#   --search: [FORMAT:value/constant]
#   --storage:
#   ----constant        name of the constant
#   ----value           value (commas and new lines are not allowed)
#
#   value/by-app/<application>
#   --description: application scoped values for constants
#   --format: constant,value\n
#   --search: [FORMAT:value/by-app/constant]
#   --storage:
#   ----constant        name of the constant
#   ----value           value (commas and new lines are not allowed)
#
#   <location>/<environment>
#   --description: list of applications assigned to a location
#   --format: name
#   --search: [FORMAT:<location></env>]
#   --storage:
#   ----name            name of the application
#
#   <location>/network
#   --description: network details for a specific location
#   --format: zone,alias,network/cidr,build,default-build\n
#   --search: [FORMAT:location/network]
#   --storage:
#   ----zone            network zone; must be identical to the entry in 'network'
#   ----alias           network alias; must be identical to the entry in 'network'
#   ----network/        network ip address (e.g. 192.168.0.0) followed by a forward slash
#   ----cidr            the CIDR mask bits (e.g. 24)
#   ----build           'y' or 'n', is this network used to build servers
#   ----default-build   'y' or 'n', should this be the DEFAULT network at the location for builds
#
# External requirements:
#   Packages: coreutils awk git iputils nc ncurses openssh perl which expect
#     NOTE - requires GNU netcat, *NOT* Nmap Ncat!!
#   Specifically:
#     coreutils: echo, head, nohup, tail, tr, shuf, sort, wc
#     iputils: ping
#     ncurses: tput
#     openssh: ssh, ssh-keygen
#   My stuff - kvm-install.sh, system-build-scripts, http server for kickstart files and mirrors, pxeboot, dhcp
#
# Code Guidelines:
#   1. Do not use sed, at all, anywhere.  The implementation is inconsistent between Linux/UNIX/BSD/etc...
#   2. Keep function names alphabetically sorted in each section to ease management.
#   3. Space out lines of code and comment appropriately.  This includes vertical alignment where appropriate.
#   4. When you see a bug or missing feature implement it right away, add a !!FIXME!!, or a TO DO (below).
#   5. Every time a configuration file is read or written include the appropriate [FORMAT:...] identifier.
#      These are located in the "Data storage" section (above) and ease "schema" changes to the storage
#      files.
#   6. Program defensively. Always assume a function will be called with bad data or invalid parameters.
#   7. Avoid code reuse; try to leverage generic functions to simplify development and improve legibility.
#   8. Use CamelCase variables to avoid conflicts with environment variables.
#   9. Always localize variables.  Assume at some point each function will be called from other functions
#      as more functionality is abstracted.
#   10. Leverage bash built-ins over external programs to improve compatibility.
#
# TO DO:
#   - bug fix:
#     - functions that validate input and are called from subshells should fail instead of prompting in the subshell
#     - system_provision_phase2 has remote while loops that will not exit on their own when abort is enabled
#     - need to be able to remove a partially built backing system
#     - correct host name when creating overlays
#     - there is no way to manage environment inclusions/exclusions for application::file mapping
#     - 'build lineage --reverse' only outputs the build name.  Is that intentional?
#     - system deprovision needs to handle snapshots (they prevent the system from being undefined)
#   - clean up:
#     - simplify IP management functions by reducing code duplication
#     - populate reserved IP addresses
#     - rename operations should update map files (hv stuff specifically for net/env/loc)
#   - enhancements:
#     - finish IPAM and IP allocation components
#     - add detailed help section for each function
#     - reduce the number of places files are read directly. eventually use an actual DB.
#     - ADD: build [<environment>] [--name <build_name>] [--assign-resource|--unassign-resource|--list-resource]
#     - overhaul scs - split into modules, put in installed path with sub-folder, dependencies, and config file
#     - rewrite modules in a proper programming language
#     - add file groups
#     - store vm uuid with system to use as a sanity check when manipulating remote vms
#     - fingerprint each system to use as a sanity check when managing them
#     - all systems should use the same backing image, and instead of a larger disk get a second disk with a unique LVM name
#     - cluster y/n for application in environment
#     - file 'patch' for cluster y/n (in addition to environment patch)
#     - file enabled y/n for cluster
#     - pre/post-flight scripts or commands (per application, per environment, per location ?)
#     - finish implementing system_convert
#     - colorize system list output (different color per build)?
#     - deprecate external kvm-install script and remove dependencies on external servers
#     - add pxe boot, mirrors, kickstart, dhcp, etc... creation of VM to scs in networks on hypervisors
#     - send a deployment report when automatic provisioning and system creation occurs
#     - ipam network service?
#     - hosts network service (or just use DNS!) ?
#     - handle more natural english for commands... and/or make the order consistent (i.e. 'scs system show X' vs 'scs show system X' vs 'scs system X --blah')
#     - flock is not available on darwin (... or would have to be built ...)
#     - need to be able to define number of processors for a build or system
#     - add support to system module to show and manage snapshots on hypervisors
#     - showing a system that is a base image should display each hypervisor it is deployed to and all overlays using it
#     - automatically register the current ssh key on a remote system when it is built (kickstart likely?)
#     - stop supporting centos 5?  mount disk images to deploy initial config and install packages?
#     - scs constant edit -> view/edit all set values for a constant (like the route tool?)
#   - environment stuff:
#     - an environment instance can force systems to 'single' or 'overlay'
#     - add concept of 'instance' to environments and define 'stacks'
#     - files that only appear for clustered environments??
#     - load balancer support ? auto-create cluster and manage nodes?
#     - applications have dependencies on other applications for environment builds
#     - how to generate and deploy database credentials for an environment? other variables?
#     - database builds/options for environments
#

#Section: UTILITY
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

# check if a host is responding on the network
#   use ssh port (tcp/22) since that is almost exclusively how we manage them
#
# requires:
#   $1	host name or ip
#
# optional:
#   $2	tcp port (default is 22)
#   $3  timeout (default is 2 seconds)
#
function check_host_alive {
  local Port Timeout Pid C=0 Result=0
  if [ $# -eq 0 ]; then return 1; fi
  if [ $# -eq 2 ]; then Port=$2; else Port=22; fi
  if [ $# -eq 3 ]; then Timeout=$3; else Timeout=2; fi
  if [ "$HostOS" == "mac" ]; then
    ( ( exec 3<>/dev/tcp/$1/$Port ) & Pid=$! ; \
      while [[ $( ps -p $Pid |wc -l ) -gt 0 && $C -lt $((Timeout*5)) ]]; do sleep .2; C=$((C+1)); done; \
      if [[ $( ps -p $Pid |wc -l ) -gt 0 ]]; then Result=1; kill $Pid; fi; \
    ) >/dev/null 2>&1
    return $Result
  else
    nc -z -w $Timeout $1 $Port &>/dev/null && return 0 || return 1
  fi
}

# check and upgrade the schema as needed
#
function check_schema {
  local Pass=0 RL SkipPrompt=0 Version List n
  if [[ $1 == "--no-prompt" ]]; then SkipPrompt=1; fi
  if [[ -s ${CONF}/schema && "$( cat ${CONF}/schema )" == "$SchemaVersion" ]]; then return 0; fi

  # file does not exist, so the repo is at <0.1
  if ! [[ -s ${CONF}/schema ]]; then echo "0" >${CONF}/schema; fi

  Version="$( cat ${CONF}/schema )"

  if [[ $Version > $SchemaVersion ]]; then
    err "Error: The configuration repository schema is newer than what is supported by this application."
  fi

  if [[ $SkipPrompt -ne 1 ]]; then
    cat <<_EOF
------------------------------------------------------------------------------------------
Error: Your version of the configuration is out of date. It is strongly recommened that
you pull and/or merge changes in from your upstream master repository before continuing.
If you are sure you are completely up to date I can automatically update the
configuration to the latest version, after which you should commit and push changes
upstream for others.
------------------------------------------------------------------------------------------

_EOF
    get_yn RL "Would you like to automatically update the repository (y/n)?"
    if [[ $RL != "y" ]]; then exit 1; fi
  fi

  # get available migrations
  pushd $( dirname $( deref $0 ) ) >/dev/null 2>&1 || err "Error changing to script directory"

  while [[ $Version < $SchemaVersion ]]; do
    if ! [[ -s migrate/${Version}.sh ]]; then err "Error accessing migration script for $Version"; fi
    echo "Upgrading configuration from version ${Version}..."
    /bin/bash migrate/${Version}.sh ${CONF}
    if [[ $? -ne 0 ]]; then err "Error executing migration for $Version"; fi
    if [[ "$( cat ${CONF}/schema )" == "$Version" ]]; then err "Error in migration script for $Version"; fi
    Version="$( cat ${CONF}/schema )"
  done

  printf -- '\nSchema successfully upgraded to version %s. Please commit and push changes to your upstream repository.\n' $SchemaVersion
  exit 0
}

# exit function called from trap
#
function cleanup_and_exit {
  local code=$?
  test -d $TMP && rm -rf $TMP
  test -f /tmp/app-config.$$ && rm -f /tmp/app-config.$$*
  exit $code
}

# compare version strings
#
# SOURCE: http://stackoverflow.com/questions/4023830/bash-how-compare-two-strings-in-version-format
#
# requires:
#  $1,$2	strings to compare
#
# returns:
#  0	if the versions match
#  1	if $1 > $2
#  2	if $2 > $1
#
function compare_version {
  if [[ $1 == $2 ]]; then return 0; fi
  local IFS=.
  local i ver1=($1) ver2=($2)
  # fill empty fields in ver1 with zeros
  for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do ver1[i]=0; done
  for ((i=0; i<${#ver1[@]}; i++)); do
    if [[ -z ${ver2[i]} ]]; then
      # fill empty fields in ver2 with zeros
      ver2[i]=0
    fi
    if ((10#${ver1[i]} > 10#${ver2[i]})); then return 1; fi
    if ((10#${ver1[i]} < 10#${ver2[i]})); then return 2; fi
  done
  return 0
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

# Dereference a symlink or directory name
#
function deref {
  test $# -eq 1 || return 1;
  if [ -d "$1" ]; then pushd $1 >/dev/null 2>&1 && pwd && popd >/dev/null 2>&1; return 0; fi
  local FILE="$1"; while [ -L "$FILE" ]; do FILE=$( readlink $FILE ); done; echo $FILE; return 0;
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
  get_user --no-prompt
  test ! -z "$1" && MSG="$@" || MSG="An error occurred"
  echo "$MSG" >&2
  printf -- '%s %s scs: [%s] %s %s\n' "$( date +'%b %_d %T' )" "$( hostname )" "$$" "$USERNAME" "$MSG" >>$SCS_Error_Log
  test x"${BASH_SOURCE[0]}" == x"$0" && exit 1 || return 1
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
    command) printf -- 'commands';;
    d|di|dif) printf -- 'diff';;
    e|en|env) printf -- 'environment';;
    f) printf -- 'file';;
    he|?) printf -- 'help';;
    hv|hy|hyp|hyper) printf -- 'hypervisor';;
    l|lo|loc) printf -- 'location';;
    n|ne|net) printf -- 'network';;
    r|re|res) printf -- 'resource';;
    st|sta|stat) printf -- 'status';;
    sy|sys|syst|sytem) printf -- 'system';;
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

# fold a list into pretty columns
#
# this is a rough attempt to approximate 'column -t' due to the "column: line too long" issue.
#  we run into trouble with 'fold' since it doesn't care about the columns.  if the output
#  looks wonky, that's why.
#
function fold_list {
  local foo food maxlen width
  while read foo; do test -z "$food" && food="$foo" || food="$food $foo"; done
  maxlen=$( printf -- "$food" |tr ' ' '\n' |awk 'length>max{max=length}END{print max}' )
  width=$(( $(tput cols) / ( $maxlen + 5 )))
  printf -- "$food" |tr ' ' '\n' |awk 'BEGIN{i=1}{printf "%-*s", '$((maxlen + 3))', $1; if ((i%'$width')==0) { printf "\n"; }; i++}END{print "\n"}'
}

# generate a new ssh keypair
#
# required:
#  $1	path to key
#
function generate_ssh_key {
  test $# -ne 1 && err "Please provide the path to store the key"
  if [[ -f "$1" || -f "$1.pub" ]]; then err "Error: the specified key pair already exists"; fi
  ssh-keygen -t rsa -b 4096 -C 'scs access key' -N '' -q -f "$1"
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
    get_input C "$( printf -- $1 |perl -pe "s/\b\(.\)/\u\1/g" ) to Delete"
  else
    C="$2"
  fi
  grep -qE "^$C," ${CONF}/$1 || err "Unknown $1"
  get_yn RL "Are you sure (y/n)?"
  if [ "$RL" != "y" ]; then return 1; fi
  perl -i -ne "print unless /^$C,/" ${CONF}/$1
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
#  --auto ""       use this value instead of prompting if it is not an empty string
#  --default ""    specify a default value
#  --nc            do not force lowercase
#  --null          allow null (empty) values
#  --options       comma delimited list of options to restrict selection to
#  --regex         validation regex to match against (passed to grep -E)
#  --comma         allow a comma in the input (default NO)
#
function get_input {
  test $# -lt 2 && return
  LC=1; RL=""; P="$2"; local V="$1"; D=""; NUL=0; OPT=""; RE=""; COMMA=0; CL=0; local AUTO=""; shift 2
  while [ $# -gt 0 ]; do case $1 in
    --auto) AUTO="$2"; shift;;
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
      LEN=$( printf -- "$OPT" |wc -c |awk '{print $1}' )
      if [ $LEN -gt $(( $WIDTH - 25 )) ]; then
        printf -- " ( .. long list .. )"
        tput smcup; clear; CL=1
        printf -- "Select an option from the below list:\n"
        printf -- "$OPT\n" |tr ',' '\n' |fold_list |perl -pe 's/^/ /'
        test $NUL -eq 0 && printf -- '*'; printf -- "$P"
      else
        printf -- " ($( printf -- "$OPT" |perl -pe 's/,/, /g' )"
        if [ $NUL -eq 1 ]; then printf -- ", null)"; else printf -- ")"; fi
      fi
    fi
    # output the default option if one was provided
    test ! -z "$D" && printf -- " [$D]: " || printf -- ": "
    # collect the input unless an auto value was provided
    if [ -z "$AUTO" ]; then read -r RL; else RL="$AUTO"; AUTO=""; printf -- "$RL\n"; fi
    # force it to lowercase unless requested not to
    if [ $LC -eq 1 ]; then RL=$( printf -- "$RL" |tr 'A-Z' 'a-z' ); fi
    # if the screen was cleared, output the entered value
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
# optional:
#   --no-prompt
#
function get_user {
  [ -n "$USERNAME" ] && return
  if [ -n "$SUDO_USER" ]; then U=${SUDO_USER}; else U="$( whoami )"; fi
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
#  --extra <string>    additional option to accept besides 'y' or 'n': case sensitive
#
function get_yn {
  test $# -lt 2 && return
  local YNRL="" P RETVAR EXTRA PLUSARGS
  RETVAR="$1"; P="$2"; shift 2
  while [ $# -gt 0 ]; do case $1 in
    --extra) EXTRA="$2"; shift;;
    *) PLUSARGS="$PLUSARGS $1";;
  esac; shift; done
  PLUSARGS=${PLUSARGS# }
  if ! [ -z "$EXTRA" ]; then
    while [[ "$YNRL" != "y" && "$YNRL" != "n" && "$YNRL" != "$EXTRA" ]]; do eval "get_input YNRL \"$P\" $PLUSARGS"; done
  else
    while [[ "$YNRL" != "y" && "$YNRL" != "n" ]]; do eval "get_input YNRL \"$P\" $PLUSARGS"; done
  fi
  eval "$RETVAR='$YNRL'"
  if [ "$YNRL" == "y" ]; then return 0; elif [ "$YNRL" == "$EXTRA" ]; then return 2; else return 1; fi
}

# first run function to init the configuration store
#
function initialize_configuration {
  test -d $CONF && exit 2
  mkdir -p $CONF/template/patch $CONF/{env,net,value/by-app}
  git init --quiet $CONF
  touch $CONF/{application,constant,environment,file{,-map},hv-{environment,network,system},hypervisor,location,network,resource,system}
  cd $CONF || err
  printf -- "*\\.sw[op]\n\\.DS_Store\nscs_activity\\.log\nscs_bg\\.log\nscs_error\\.log\n\\.scs_lock\n" >.gitignore
  printf -- "${SchemaVersion}\n" >schema
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

# md5sum (linux) is not necessarily available
#
# required:
#   $1 file1
#   $2 file2
#   etc...
#
function md5s {
  local RetCode=0
  if [[ -x /usr/bin/md5sum ]]; then
    /usr/bin/md5sum $@ 2>/dev/null |cut -d' ' -f1
  elif [[ -x /sbin/md5 ]]; then
    /sbin/md5 -q $@ 2>/dev/null
  else
    echo "md5sum not available" >&2; RetCode=1
  fi
  return $RetCode
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

# purge entries for host and/or ip from ssh known_hosts
#
# optional:
#   --name <string>
#   --ip <string>
#
function purge_known_hosts {
  if [ $# -eq 0 ]; then return; fi

  local name ipaddy kh
  kh=~/.ssh/known_hosts

  while [ $# -gt 0 ]; do case $1 in
    --name) grep -q "$2" $kh && name=$2; shift;;
    --ip) valid_ip $2 && grep -q "$2" $kh && ipaddy=$2; shift;;
  esac; shift; done

  scslog "purge_known_hosts: '$name' '$ipaddy'"
  test -z "${name}${ipaddy}" && return

  (
  flock -x -w 30 200
  if [ $? -ne 0 ]; then err "Unable to obtain lock on $kh"; return; fi
  printf -- "updating local known hosts\n" >>$SCS_Background_Log
  cat $kh >$kh.$$
  if [[ -n "$name" ]]; then perl -i -ne "print unless /$( printf -- "$name" |perl -pe 's/\./\\./g' )[, ]/" $kh; fi
  if [[ -n "$ipaddy" ]]; then perl -i -ne "print unless /$( printf -- "$ipaddy" |perl -pe 's/\./\\./g' )[, ]/" $kh; fi
  diff $kh{.$$,} >>$SCS_Background_Log; rm -f $kh.$$
  ) 200>>$kh

  return 0
}

# read xml data
#
# SOURCE: http://stackoverflow.com/questions/893585/how-to-parse-xml-in-bash
#
function read_dom () {
  local IFS=\>
  read -d \< ENTITY CONTENT
  local RET=$?
  TAG_NAME=${ENTITY%% *}
  ATTRIBUTES=${ENTITY#* }
  if [ "$ATTRIBUTES" == "$TAG_NAME" ]; then ATTRIBUTES=""; fi
  TYPE=OPEN
  if [[ "${TAG_NAME: -1}" == "/" || "${ATTRIBUTES: -1}" == "/" || "${CONTENT: -1}" == "/" ]]; then TYPE=CLOSE; fi
  TAG_NAME=${TAG_NAME/%\//}
  ATTRIBUTES=${ATTRIBUTES/%\//}
  CONTENT=${CONTENT/%\//}
  return $RET
}

# register ssh public key on a remote host
#
# requires:
#  --host <name>         remote host name or ip
#  --user <name>         remote user name
#  --key </path/to/key>  local path to ssh private key
#
# optional:
#  --sudo <name>         user to access server and elevate privileges
#
function register_ssh_key {
  local PrivateKey PublicKey Pass System RemoteUser SudoUser AccessUser Debug=0

  # process arguments
  while [ $# -gt 0 ]; do case $1 in
    --debug) Debug=1;;
    --host) System="$2";;
    --key) PrivateKey="$2";;
    --sudo) SudoUser="$2";;
    --user) RemoteUser="$2";;
    *) err "Invalid argument provided to register_ssh_key";;
  esac; shift 2; done

  if [[ -z "$PrivateKey" || -z "$System" || -z "$RemoteUser" ]]; then err "Invalid arguments provided to register_ssh_key"; fi
  check_host_alive $System || err "Unable to connect to remote host"

  # validate and load private key
  test -s "$PrivateKey" || err "Unable to access private key file"
  PublicKey=$( ssh-keygen -y -P '' -q -f "$PrivateKey" 2>/dev/null )
  if [ $? -eq 1 ]; then err "Unable to load private key file"; fi

  if [[ -n "$SudoUser" ]]; then AccessUser=$SudoUser; else AccessUser=$RemoteUser; fi

  # get the ssh password
  read -sp "Password [$AccessUser]: " Pass; echo
  test -z "$Pass" && err "A password is required to log in to the remote server"

  # this can be done by adding a conditional to the expect script instead of having it twice,
  #  but I don't feel like looking up and escaping the syntax for that right now...
  #
  if [[ -n "$SudoUser" ]]; then
    expect -c "
set timeout 10
exp_internal $Debug
log_user $Debug
match_max 100000
spawn ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=keyboard-interactive,password -l $AccessUser $System
expect {
  \"*?assword:*\" { send -- \"$Pass\\r\" }
  eof { exit }
  timeout { exit }
}
expect -regexp \".*(\\\$|#).*\"
send -- \"sudo su - $RemoteUser\\r\"
expect {
  \".*?assword for $AccessUser:*\" { send -- \"$Pass\\r\" }
  eof { exit }
  timeout { exit }
}
expect -regexp \".*(\\\$|#).*\"
send -- \"grep -q \\\"$PublicKey\\\" .ssh/authorized_keys 2>/dev/null\\r\"
expect -regexp \".*(\\\$|#).*\"
send -- \"if \[ \\\$? -eq 1 \]; then echo \\\"$PublicKey\\\" >>.ssh/authorized_keys; fi\\r\"
expect -regexp \".*(\\\$|#).*\"
send -- \"exit\\r\"
expect -regexp \".*(\\\$|#).*\"
send -- \"exit\\r\"
expect eof
"
  else
    expect -c "
set timeout 10
exp_internal $Debug
log_user $Debug
match_max 100000
spawn ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=keyboard-interactive,password -l $AccessUser $System
expect {
  \"*?assword:*\" { send -- \"$Pass\\r\" }
  eof { exit }
  timeout { exit }
}
expect -regexp \".*(\\\$|#).*\"
send -- \"grep -q \\\"$PublicKey\\\" .ssh/authorized_keys 2>/dev/null\\r\"
expect -regexp \".*(\\\$|#).*\"
send -- \"if \[ \\\$? -eq 1 \]; then echo \\\"$PublicKey\\\" >>.ssh/authorized_keys; fi\\r\"
expect -regexp \".*(\\\$|#).*\"
send -- \"exit\\r\"
expect eof
"
  fi
}

# replace piped input with commas in a string
#
# optional:
#  $1	one character string seperator (default '\n')
#  $2	one character string substitue (default ',')
#
function replace {
  local str sep rep
  if [[ -n $1 ]]; then sep="$1"; else sep='\n'; fi
  if [[ -n $2 ]]; then rep="$2"; else rep=','; fi
  str=$( tr "$sep" "$rep" )
  printf -- '%s' "${str%$rep}"
}

function scs_abort {
  case $1 in
    '--disable'|'disable'|'--cancel'|'cancel')
      test -f $ABORTFILE && /bin/rm -f $ABORTFILE
      printf -- '\E[32;47m%s\E[0m\n' "***** ABORT DISABLED *****"
      scslog "abort disabled"
      return
      ;;
  esac
  if [ -f $ABORTFILE ]; then
    printf -- 'Abort file already exists.\n'
    return
  fi
  get_yn RL "Are you sure want to stop all running scs tasks (y/n)?" || return
  touch $ABORTFILE
  printf -- 'Abort file has been created. All background processes will exit.\n'
  scslog "abort enabled"
}

# write to the activity log
#
function scslog {
  test $# -eq 0 && return
  get_user --no-prompt
  if [[ "$1" == "-v" || "$1" == "--verbose" ]]; then
    shift
    printf -- '%s %s scs: [%s] %s %s\n' "$( date +'%b %_d %T' )" "$( hostname )" "$$" "$USERNAME" "$@" >>$SCS_Activity_Log
    printf -- '%s\n' "$@"
  else
    printf -- '%s %s scs: [%s] %s %s\n' "$( date +'%b %_d %T' )" "$( hostname )" "$$" "$USERNAME" "$@" >>$SCS_Activity_Log
  fi
  return 0
}

# shuf is not necessarily available
#
function shuf {
  perl -MList::Util=shuffle -le'printf for shuffle <>'
}

# execute a command on a remote server
#
# used to centralize ssh calls and make global configuration parameters practical
#
# required:
#   "host"            : remote host
#   "command"         : remote command to execute
#
# optional:
#   -d                : disable strict host key checking
#   -i </path/to/key> : identify file (key) (defaults to global identity file)
#   -l <user>         : remote user (defaults to global remote user)
#   -n                : Redirects stdin from /dev/null (actually, prevents reading from stdin).
#   -o <option>       : additional ssh option
#   -p <port>         : remote ssh port
#   -q                : quiet mode -> suppress stdout and stderr
#
function ssh_remote_command {
  local Command Insecure=0 Identity=$SCS_KeyFile Login=$SCS_RemoteUser Opt Port=22 Quiet=0 Remote SuppressStdin=0

  # process arguments
  while [ $# -gt 0 ]; do case $1 in
    -d) Insecure=1;;
    -i) Identity="$2"; shift;;
    -l) Login="$2"; shift;;
    -n) SuppressStdin=1;;
    -o) Opt="$2"; shift;;
    -p) Port="$2"; shift;;
    -q) Quiet=1;;
    *) if [[ -z "$Remote" ]]; then Remote="$1"; elif [[ -z "$Command" ]]; then Command="$@"; shift; break; fi;;
  esac; shift; done

  # validate input
  if [[ -z "$Command" ]]; then err "Missing command"; fi
  if [[ -z "$Remote" ]]; then err "Missing host"; fi
  if ! [[ -r "$Identity" ]]; then err "Invalid identity file"; fi

  # translate settings
  if [[ $SuppressStdin -eq 1 ]]; then SuppressStdin="-n "; else SuppressStdin=""; fi

  if [[ -n "$Opt" && $Insecure -eq 0 && $Quiet -eq 0 ]]; then
    ssh -o "PasswordAuthentication no" -o "$Opt" -l $Login -p $Port -i $Identity $SuppressStdin$Remote "$Command"
  elif [[ -z "$Opt" && $Insecure -eq 0 && $Quiet -eq 0 ]]; then
    ssh -o "PasswordAuthentication no" -l $Login -p $Port -i $Identity $SuppressStdin$Remote "$Command"
  elif [[ -n "$Opt" && $Insecure -eq 1 && $Quiet -eq 0 ]]; then
    ssh -o "PasswordAuthentication no" -o "StrictHostKeyChecking no" -o "$Opt" -l $Login -p $Port -i $Identity $SuppressStdin$Remote "$Command"
  elif [[ -z "$Opt" && $Insecure -eq 1 && $Quiet -eq 0 ]]; then
    ssh -o "PasswordAuthentication no" -o "StrictHostKeyChecking no" -l $Login -p $Port -i $Identity $SuppressStdin$Remote "$Command"
  elif [[ -n "$Opt" && $Insecure -eq 0 && $Quiet -eq 1 ]]; then
    ssh -o "PasswordAuthentication no" -o "$Opt" -l $Login -p $Port -i $Identity $SuppressStdin$Remote "$Command" >/dev/null 2>&1
  elif [[ -z "$Opt" && $Insecure -eq 0 && $Quiet -eq 1 ]]; then
    ssh -o "PasswordAuthentication no" -l $Login -p $Port -i $Identity $SuppressStdin$Remote "$Command" >/dev/null 2>&1
  elif [[ -n "$Opt" && $Insecure -eq 1 && $Quiet -eq 1 ]]; then
    ssh -o "PasswordAuthentication no" -o "StrictHostKeyChecking no" -o "$Opt" -l $Login -p $Port -i $Identity $SuppressStdin$Remote "$Command" >/dev/null 2>&1
  elif [[ -z "$Opt" && $Insecure -eq 1 && $Quiet -eq 1 ]]; then
    ssh -o "PasswordAuthentication no" -o "StrictHostKeyChecking no" -l $Login -p $Port -i $Identity $SuppressStdin$Remote "$Command" >/dev/null 2>&1
  else
    echo "Unexpected argument in ssh_remote_command"
  fi

  return $?
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

#Section: HELP
 #     # ####### #       ######
 #     # #       #       #     #
 #     # #       #       #     #
 ####### #####   #       ######
 #     # #       #       #
 #     # #       #       #
 #     # ####### ####### #

# help wrapper
#
function help {
  local SUBJ="$( expand_subject_alias "$( echo "$1" |perl -pe 's/\?//' |tr 'A-Z' 'a-z' )")"; shift
  if [ -z "$SUBJ" ]; then scs_help |less -c; exit 0; fi
  local VERB=""
  if [ $# -gt 0 ]; then
    VERB="$( expand_verb_alias "$( echo "$1" |perl -pe 's/\?//' |tr 'A-Z' 'a-z' )")"; shift
  fi
  test -z "$VERB" && local HELPER="${SUBJ}_help" || local HELPER="${SUBJ}_${VERB}_help"
  ( {
    eval ${HELPER} $@ 2>/dev/null
  } || {
    echo "Help section not available for '$SUBJ'."; echo
    usage --no-exit
  } ) |less -c
  exit 0
}

# locking
#
function lock_help { cat <<_EOF
NAME
	SCS Locking and Version Control

SYNOPSIS
	scs abort
	scs commit
	scs diff
	scs lock
	scs log
	scs status
	scs unlock|cancel

DESCRIPTION
	SCS implements some rudimentary locking to ensure two users on a multi-user system (sharing a single instance of the
	repository) do not overlap configuration changes.  Essentially any function that modifies the configuration will
	automatically 'lock' the repository and force the user to either commit or cancel the changes.  If it is desirable
	for multiple users to modify the configuration at once then each user should check out their own copy of the
	configuration.

	Uncommitted from master can be reviewed at any time with 'scs diff' and either committed (and released) with
	'scs commit' or discarded with 'scs cancel'.

	Cumulative changes from an upstream tracking branch or local master can be viewed in the same fashion using
	'scs diff --master', 'scs diff --branch <name>', or scs diff '--upstream'.  See the diff documentation below for
	more information.

	Any user can masquerade as another user by setting the SUDO_USER environment variable.  E.g.:
		SUDO_USER=bbuckeye $0 lock
	... will lock scs as the user 'bbuckeye'. This usage is discourged.

OPTIONS
	abort [--disable|--cancel]
		Sets global abort flag to stop any running background processes.  Use with caution.  All processes that
		run in the background periodically check for the abort flag and stop cleanly when it is set.  While
		abort is enabled scs is effectively locked out until abort mode is disabled.

		'abort --disable' or 'abort --cancel' turns off abort mode.

		Warning: some remote operations are currently unable to check the abort status and will never stop on
		their own. This is a bug.

	cancel
		Unlocks a locked repository and permanently discards and deletes any outstanding changes.

	commit [-y|--no-prompt] [--message|-m 'message'] [-p|--push]
		Commit all outstanding changes to the current branch and unlock the configuration.  A commit message is
		strongly encouraged.

		The '--no-prompt' option skips the normal request to review changes and confirm closing of the branch.

		The '--push' option will commit to the local repository and also attempt to push all outstanding changes
		to the upstream tracking branch (will *never* push to origin/master).

	diff [-b|--branch <name>] [-m|--master] [-u|--upstream]
		Wrapper for 'git diff' for some commonly used scenarios.  For anything not covered here simply switch
		to the scs configuration folder and use git diff:
			cd $( scs dir )

		'--branch' will diff against a local branch with the provided name.

		'--master' will diff against the local master.

		'--upstream' can be used with '--branch' or '--master' and perform the same function against the
			configured upstream repository.  If '--upstream' is provided alone the configured tracking
			repository will be referenced.

	lock
		Locks the repository for the current user without otherwise modifying the configuration.  Used exclusively
		to prevent other users on a multi-user system from locking the repository while you prepare changes.

	log
		Shows the git change log for all time. This illustrates why commit messages are important.

	status [-v|--verbose]
		Check whether or not scs is currently locked.  Returns 0 if unlocked and 1 if locked. This is useful for
		scripting scs commands.

		The '--verbose' flag will also include the state of any upstream repository.

	unlock
		Alias for 'cancel'.

EXAMPLES

RETURN CODE
	scs returns 0 on success and non-zero on error.

AUTHOR
	William Strucke <wstrucke@gmail.com>

COPYRIGHT
	Copyright © 2014 William Strucke. License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
	This is free software: you are free to change and redistribute it.  There is NO WARRANTY, to the extent permitted by law.

SEE ALSO
	$0 help
_EOF
}
function abort_help { lock_help; }
function cancel_help { lock_help; }
function commit_help { lock_help; }
function diff_help { lock_help; }
function log_help { lock_help; }
function status_help { lock_help; }
function unlock_help { lock_help; }

# general scs help (man scs equiv)
#
function scs_help { cat <<_EOF
NAME
	Simple Configuration [Management] System version ${SCS_Version} (${HostOS})

SYNOPSIS
	$0 [options] component [sub-component|verb] [--option1] [--option2] [...]

	commit [-m 'commit message']
	cancel [--force]
	help | commands
	abort | diff | dir | lock | log | pdir | status | unlock

	<component> create
	<component> delete [<name>]
	<component> list
	<component> show [<name>] [--brief]
	<component> update [<name>]

COMPONENTS
	application
		An application is a collection of set variables and files linked to a system via a build.

	build
		A build is an operating system (OS), memory, disk, processor (CPU), zero or more applications,
		and installed packages (via a system-build 'role') assigned to a system.

	constant
		A constant is a variable that can be set in one of five scopes and used to replace text in
		managed configuration files.

		Scopes include, in order of precedence:
			1. Application in an Environment
			2. Environment at a Location
			3. Environment (Global)
			4. Application (Global)
			5. Global

		Global is rarely used since it can represent a static value and often means a variable is unnecessary.
		A use case could be as a fall-back value for a constant, i.e. setting a global setting for all
		environments but having a different value in one or other (such as production).

		There is currently no way to set global variables in the scs ui (with my apologies). This is a bug.

	environment
		An environment is a set of applications, constants (variables), and optionally patches to files.

		Environments are linked to a location, after which systems can be assigned to them.

	file
		Managed configuration files come in one of seven types and are assembled any time a system
		audit or configuration deployment is requested.

		Files can optionally contain constants or resources and can optionally have a 'patch' for any environment,
		allowing tremendous flexibility in construction and deployment between a multitude of environments.

		File types include:

			file          a regular text file
			symlink       a symbolic link
			binary        a non-text file
			copy          a regular file that is not stored here. it will be copied by this application from
			                another location when it is deployed.  when auditing a remote system files of type
			                'copy' will only be audited for permissions and existence.
			delete        ensure a file or directory DOES NOT EXIST on the target system.
			download      a regular file that is not stored here. it will be retrieved by the remote system
			                when it is deployed.  when auditing a remote system files of type 'download' will
			                only be audited for permissions and existence.
			directory     a directory (useful for enforcing permissions)

		When a file is processed scs looks for a standard template notation for constants and resource references,
		using a bracket, percent sign, and space before and after the variable.

		A variable is notated with the variable type as a prefix followed by the unique name.  There are
		currently three types:
			resource
				See \`$0 help resource\` for more information.
			constant
				These are normal variables, scoped as indicated above.
			system
				See \`$0 help system\` for more information.

		Example notation:
			{% resource.name %}
			{% constant.name %}
			{% system.name %}, {% system.ip %}, {% system.location %}, {% system.environment %}

	hypervisor
		A hypervisor is a Linux host with libvirt/qemu used for running virtual machines.  It is associated with
		one or more networks, a single location, and one or more environments which allow systems to be built
		and deployed to it.

	location
		A location is assigned to networks, systems, and environments for the purpose of segregating settings
		that are specific to a deployment scenario.

	network
		A network is essentially an IPv4 address and subnet mask with one to 4,294,967,296 addresses.

		Networks have optional properties that are useful for applying system settings, such as a DNS server,
		gateway, NTP server, Syslog server, etc...  Networks can be defined as a 'build' network where new
		servers can be built.  Build networks have special properties.  See \`$0 help network\` for more information.

	resource
		A resource is a "physical" thing assigned to either a system or an application in an environment at a
		location.  Currently these are all IP addresses.  See \`$0 help resource\` for more information.

		Future updates may add network interfaces, disks, or other resource types.

	system
		A system is associated directly or indirectly with all other resource types.  It is the 'thing' an
		assembled configuration is deployed or installed to; it is built or managed and must be accessible
		from the management server with a root ssh key.

DESCRIPTION
	Manage application/server configurations and base templates across all environments.

	Generally if you do not provide a required argument you will prompted for it, e.g.:
		$0 application show
	... will output a list of applications and ask you to select one to show.

	Pressing ctrl+c at any time will abort and return you to your shell.

	Any command that alters the running configuration automatically locks scs.  Run \`$0 help lock\` for more information.

	Run commit when complete to finalize changes.

	HINT - Follow any command with '?' for more detailed usage information.

	\`$0 commands\` will output the legacy usage and command summary.

OPTIONS
	--config <string>
		Specify an alternate configuration directory (default location is '$CONF')

	help
		Displays this help dialogue.

	dir
		Print the path to the configuration directory.

	pdir
		Print the path to the executable directory (where this script is located).

ENVIRONMENT
	The below envrionment variables can be used to control some global settings.

	SCS_CONF - equivilent of providing --config </path/to/config>

	SCS_IDENTITY - path to the private key used to access remote systems over ssh

	SCS_RELEASES - path to store generated releases

	SCS_REMOTE_BACKUPS - number of backups to retain on remote systems when deploying configuration.
		a value of 0 will keep all backups, a value of 1 will only keep the current backup, etc...

	SCS_REMOTE_USER - remote user to run commands on and manage systems and hypervisors (default: root)

	SCS_SHARED_REPO - set to 0 to disable "locking". this is useful when used on a management server
		with a local repository that is accesssed by multiple concurrent users, to avoid contention.
		The default value is 1 (enabled).

	SCS_TEMP - directory to store temporary files. this normally includes the process id in the path.

	SCS_TEMP_LARGE - directory to store LARGE temporary files, e.g. >1GB

EXAMPLES

RETURN CODE
	scs returns 0 on success and non-zero on error.

AUTHOR
	William Strucke <wstrucke@gmail.com>

COPYRIGHT
	Copyright © 2014 William Strucke. License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
	This is free software: you are free to change and redistribute it.  There is NO WARRANTY, to the extent permitted by law.

SEE ALSO
	$0 help <component>
	$0 help lock
_EOF
}

function usage { cat <<_EOF
Simple Configuration [Management] System version ${SCS_Version} (${HostOS})
Manage application/server configurations and base templates across all environments.

Usage $0 [options] component <sub-component|verb> [--option1] [--option2] [...]
		$0 commit [-m 'commit message']
		$0 cancel [--force]
		$0 abort | commands | dir | diff | lock | log | pdir | status | unlock

Run commit when complete to finalize changes.

Components include:
	application, build, constant, environment, file, hypervisor, location, network, resource, system

All components have the following commands available:
	create
	delete [<name>]
	list
	show [<name>] [--brief]
	update [<name>]

Run \`$0 help\` for more information.

_EOF
  if [ "$1" != "--no-exit" ]; then exit 1; fi
}

function scs_commands { cat <<_EOF
Simple Configuration [Management] System version ${SCS_Version} (${HostOS})
Manage application/server configurations and base templates across all environments.

Usage $0 [options] component <sub-component|verb> [--option1] [--option2] [...]
		$0 commit [-m 'commit message']
		$0 cancel [--force]
		$0 abort | commands | diff | dir | lock | log | pdir | status | unlock

Run commit when complete to finalize changes.


HINT - Follow any command with '?' for more detailed usage information.

Component:
  application
    constant [--define|--undefine|--list] [<application>] [<constant>]
    file [--add|--remove|--list]
  build
    lineage <name> [--reverse]
    list [--tree] [--detail]
  constant
    show [--system <name>]
  environment
    application [<environment>] [--list] [<location>]
    application [<environment>] [--name <app_name>] [--add|--remove|--assign-resource|--unassign-resource|--list-resource] [<location>]
    application [<environment>] [--name <app_name>] [--define|--undefine|--list-constant] [<application>]
    constant [--define|--undefine|--list] [<environment>] [<constant>]
  file
    cat [<name>] [--environment <name>] [--silent] [--system <system>] [--system-vars /path/to/variables] [--verbose]
    edit [<name>] [--environment <name>]
  help
  hypervisor
    --locate-system <system_name> [--quick] | --system-audit
    <name> [--add-network|--remove-network|--add-environment|--remove-environment|--poll|--register-key|--search]
  location
    [<name>] [--assign|--unassign|--list]
    [<name>] constant [--define|--undefine|--list] [<environment>] [<constant>]
  network
    ip [--locate a.b.c.d]
    <name> ip [--assign|--check|--unassign|--list|--list-available|--list-assigned|--scan]
    <name> ipam [--add-range|--remove-range|--reserve-range|--free-range]
  resource
    <value> [--assign] [<system>]
    <value> [--unassign|--list]
  system
    <value> [--audit|--check|--convert|--deploy|--deprovision|--distribute|--lock|--provision|--push-build-scripts|--register-key|
             --release|--start-remote-build|--type|--unlock|--uptime|--vars|--vm-add-disk|--vm-disks]

Verbs - all top level components:
  create
  delete [<name>]
  list
  show [<name>] [--brief]
  update [<name>]

_EOF
}


#Section GIT/VCS
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
  L=$( git status -s |wc -l 2>/dev/null |awk '{print $1}' )
  # validate the lock
  if [[ $SCS_SharedLocalRepo -eq 1 && -f .scs_lock ]]; then
    grep -qE "^$USERNAME\$" .scs_lock
    if [ $? -ne 0 ]; then test "$1" == "--force" && echo "WARNING: These are not your outstanding changes!" || err "ERROR: These are not your outstanding changes!"; fi
  fi
  # confirm
  if [[ $L -gt 0 ]]; then get_yn DF "Are you sure you want to discard outstanding changes (y/n)?"; else DF="y"; fi
  if [ "$DF" == "y" ]; then
    # handle submodules
    if [ -f .gitmodules ]; then for F in $( grep "path = " .gitmodules |perl -pe 's/[[:space:]]*path = //' ); do
      if [ -d $F ]; then
        pushd $F >/dev/null 2>&1
        git clean -f >/dev/null 2>&1
        git reset --hard >/dev/null 2>&1
        popd >/dev/null 2>&1
      fi
    done; fi
    git clean -f >/dev/null 2>&1
    git reset --hard >/dev/null 2>&1
    if [[ $SCS_SharedLocalRepo -eq 1 && -f .scs_lock ]]; then rm -f .scs_lock; fi
    printf -- '\E[32;47m%s\E[0m\n' "***** SCS UNLOCKED [$( git branch |grep ^* |cut -d' ' -f2 )] *****" >&2
    if [[ $L -gt 0 ]]; then scslog "pending changes were canceled and deleted"; else scslog "unlocked clean"; fi
  fi
  popd >/dev/null 2>&1
}

# use this for anything that modifies a configuration file to keep changes committed
#
function commit_file {
  test -z "$1" && return
  # disabled
  return 0
  # disabled
  local match
  pushd $CONF >/dev/null 2>&1 || err "Unable to change to '${CONF}' directory"
  while [ $# -gt 0 ]; do
    match=0
    # handle submodules
    if [ -f .gitmodules ]; then for F in $( grep "path = " .gitmodules |perl -pe 's/[[:space:]]*path = //' ); do
      printf -- "$1" |grep -qE "^$F/"
      if [ $? -eq 0 ]; then
        # submodule file
        pushd $F >/dev/null 2>&1 || err "Unable to switch to submodule context $F"
        git add "${1/${F//\//\\\/}\//}" >/dev/null 2>&1; shift
        match=1
        break;
      fi
    done; fi
    if [ $match -eq 0 ]; then git add "$1" >/dev/null 2>&1; shift; fi
  done
  # handle submodules
  if [ -f .gitmodules ]; then for F in $( grep "path = " .gitmodules |perl -pe 's/[[:space:]]*path = //' ); do
    if [ -d $F ]; then
      pushd $F >/dev/null 2>&1
      git commit -m"committing change" >/dev/null 2>&1
      popd >/dev/null 2>&1
    fi
  done; fi
  if [ $( git status -s |wc -l 2>/dev/null |awk '{print $1}' ) -ne 0 ]; then
    git commit -m"committing change" >/dev/null 2>&1
  fi
  popd >/dev/null 2>&1
}

# delete a file from the repository
#
# $1 = file name relative to $CONF/
# $2 = '0' or '1', where 1 = do not commit changes (default is 0)
#
function delete_file {
  local match=0
  if [[ "${1:0:2}" == ".." || "${1:0:1}" == "/" || ! -f ${CONF}/$1 ]]; then return 1; fi
  pushd $CONF >/dev/null 2>&1
  # handle submodules
  if [ -f .gitmodules ]; then for F in $( grep "path = " .gitmodules |perl -pe 's/[[:space:]]*path = //' ); do
    printf -- "$1" |grep -qE "^$F/"
    if [ $? -eq 0 ]; then
      # submodule file
      pushd $F >/dev/null 2>&1 || err "Unable to switch to submodule context $F"
      git rm "${1/${F//\//\\\/}\//}" >/dev/null 2>&1
      match=1
      break;
    fi
  done; fi
  if [ $match -eq 0 ]; then git rm "$1" >/dev/null 2>&1; fi
  if [ "$2" != "1" ]; then
    # handle submodules
    if [ -f .gitmodules ]; then for F in $( grep "path = " .gitmodules |perl -pe 's/[[:space:]]*path = //' ); do
      if [ -d $F ]; then
        pushd $F >/dev/null 2>&1
        git commit -m'removing file $1' >/dev/null 2>&1
        popd >/dev/null 2>&1
      fi
    done; fi
    #git commit -m'removing file $1' >/dev/null 2>&1
  fi
  popd >/dev/null 2>&1
}

# diff the configuration against the git repository (or upstream)
#	diff [-b|--branch <name>] [-m|--master] [-u|--upstream]
#
function git_diff {
  local Branch='' Master=0 Upstream=0 LocalBranch RemoteRepo RemoteBranch

  # process arguments
  while [ $# -gt 0 ]; do case "$1" in
    -b|--branch) Branch="$2"; shift;;
    -m|--master) Master=1;;
    -u|--upstream) Upstream=1;;
  esac; shift; done

  # sanity check
  if [[ -n "$Branch" && $Master -eq 1 ]]; then err "Branch and master can not be specified together"; fi

  # load remote settings
  pushd $CONF >/dev/null 2>&1
  LocalBranch=$( git branch |grep ^* |cut -d' ' -f2 )
  if [ -z "$LocalBranch" ]; then LocalBranch=master; fi
  RemoteRepo=$( git config -l |grep "branch.$LocalBranch." |grep '.remote=' 2>/dev/null |awk 'BEGIN{FS="="}{print $NF}' )
  RemoteBranch=$( git config -l |grep "branch.$LocalBranch." |grep '.merge=' 2>/dev/null |awk 'BEGIN{FS="/"}{print $NF}' )

  # select branch
  if [[ $Master -eq 0 && -z "$Branch" ]]; then
    if [[ $Upstream -eq 1 && -n "$RemoteBranch" ]]; then
      Branch="$RemoteRepo/$RemoteBranch"
    else
      Branch="$LocalBranch"
    fi
  else
    if [[ $Master -eq 1 && $Upstream -eq 1 ]]; then
      if [[ -n "$RemoteRepo" ]]; then
        Branch="$RemoteRepo/master"
      else
        Branch="master"
      fi
    elif [ $Master -eq 1 ]; then
      Branch="master"
    elif [[ $Upstream -eq 1 && -n "$RemoteRepo" ]]; then
      Branch="$RemoteRepo/$Branch"
    fi
  fi

  # diff
  git diff $Branch
  popd >/dev/null 2>&1
}

function git_log {
  pushd $CONF >/dev/null 2>&1
  git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative
  popd >/dev/null 2>&1
}

# push repository changes to master
#
# requires:
#   --path </path/to/repo>
#
# optional:
#   --no-prompt
#   --title <string>
#
function git_push {
  local SkipPrompt=0 Title="repository" RepoPath Behind Branch RemoteRepo
  # get arguments
  while [ $# -gt 0 ]; do case "$1" in
    --no-prompt) SkipPrompt=1;;
    --path) RepoPath="$2"; shift;;
    --title) Title="$2"; shift;;
  esac; shift; done
  test -d "$RepoPath" || err "Repository path is invalid"
  get_user
  pushd $RepoPath >/dev/null 2>&1
  Branch=$( git branch |grep ^* |cut -d' ' -f2 )
  RemoteRepo=$( git config -l |grep "branch.$Branch." |grep '.remote=' 2>/dev/null |awk 'BEGIN{FS="="}{print $NF}' )
  RemoteBranch=$( git config -l |grep "branch.$Branch." |grep '.merge=' 2>/dev/null |awk 'BEGIN{FS="/"}{print $NF}' )
  if [ -z "$Branch" ]; then Branch=master; fi
  if [[ -n $RemoteRepo ]]; then
    git fetch >/dev/null 2>&1
    # disallow commits to upstream master
    if [ "$RemoteBranch" == "master" ]; then
      RemoteBranch="$USERNAME-$( date +'%Y%m%d-%H%M' )"
      if [ $SkipPrompt -ne 1 ]; then
        get_input RemoteBranch "Commits to upstream master are disallowed.  New $Title remote branch" --nc --default "$RemoteBranch"
      fi
      # configure for the new upstream branch
      git config branch.$Branch.remote $RemoteRepo
      git config branch.$Branch.merge refs/heads/$RemoteBranch
      if [ $? -ne 0 ]; then err "Error setting $Title remote tracking branch to '$RemoteBranch'!"; fi
      git config push.default simple
    fi
    Behind=$( git branch -v |grep ^* |grep behind |perl -pe 's/.*(\[|, )behind ([0-9]+)(]|,).*/\2/' ); if [ -z "$Behind" ]; then Behind=0; fi
    if [ $Behind -gt 0 ]; then err "ERROR: $Title is behind master.  Please merge changes and retry."; else git push $RemoteRepo HEAD:$RemoteBranch >/dev/null 2>&1; fi
    if [ $? -ne 0 ]; then err "Error pushing $Title changes to the upstream repository!"; fi
  fi
  popd >/dev/null 2>&1
  return 0
}

# output the status (modified, added, deleted files list)
#
# optional:
#   -v | --verbose   output additional information
#   --exit           internally used flag indicating the script should exit after this function
#
function git_status {
  local Exit=0 Status=0 Verbose=0 Branch RemoteRepo RemoteBranch Ahead Behind Message N
  # process arguments
  while [ $# -gt 0 ]; do case $1 in
    -v|--verbose) Verbose=1;;
    --exit) Exit=1;;
  esac; shift; done
  pushd $CONF >/dev/null 2>&1
  N=$( git diff --name-status |wc -l 2>/dev/null |awk '{print $1}' )
  Branch=$( git branch |grep ^* |cut -d' ' -f2 )
  RemoteRepo=$( git config -l |grep "branch.$Branch." |grep '.remote=' 2>/dev/null |awk 'BEGIN{FS="="}{print $NF}' )
  RemoteBranch=$( git config -l |grep "branch.$Branch." |grep '.merge=' 2>/dev/null |awk 'BEGIN{FS="/"}{print $NF}' )
  if [ -z "$Branch" ]; then Branch=master; fi
    if [[ $SCS_SharedLocalRepo -eq 1 ]]; then
    if ! [ -f .scs_lock ]; then
      printf -- '\E[32;47m%s\E[0m\n' "***** SCS UNLOCKED [$Branch] *****" >&2
      if [ $N -gt 0 ]; then git status; fi
    else
      printf -- '\E[31;47m%s\E[0m\n' "***** SCS LOCKED BY $( cat .scs_lock ) [$Branch] *****" >&2
      Status=1
      if [ $N -gt 0 ]; then git status; fi
    fi
  else
    printf -- 'Branch: %s\n' "$Branch"
  fi
  # check upstream
  if [[ -n $RemoteRepo && $Verbose -eq 1 ]]; then
    git fetch >/dev/null 2>&1
    Ahead=$( git branch -v |grep ^* |grep ahead |perl -pe 's/.* \[ahead ([0-9]+)].*/\1/' );            if [ -z "$Ahead" ]; then Ahead=0; fi
    Behind=$( git branch -v |grep ^* |grep behind |perl -pe 's/.*(\[|, )behind ([0-9]+)(]|,).*/\2/' ); if [ -z "$Behind" ]; then Behind=0; fi
    echo "--> tracking remote $RemoteRepo:$RemoteBranch"
    echo "--> $Ahead ahead, $Behind behind"
  elif [ $Verbose -eq 1 ]; then
    echo "--> no upstream master"
  fi
  popd >/dev/null 2>&1
  [ $Exit -eq 1 ] && exit $Status
}

# manage changes and locking with branches
#
function start_modify {
  # get the running user
  get_user
  # the current branch must either be master or the name of this user to continue
  cd $CONF || err
  if [[ $SCS_SharedLocalRepo -eq 0 ]]; then return 0; fi
  if [[ -f .scs_lock ]]; then
    grep -qE "^$USERNAME\$" .scs_lock
    if [ $? -ne 0 ]; then err "Another change is in progress, aborting."; fi
    return 0
  else
    echo "$USERNAME" >.scs_lock
  fi
  printf -- '\E[31;47m%s\E[0m\n' "***** SCS LOCKED BY $USERNAME [$( git branch |grep ^* |cut -d' ' -f2 )] *****" >&2
  scslog "locked"
  return 0
}

# merge changes back into the current branch
#
# optional:
#  -p|--push        push changes upstream too
#  -m|--message     commit message
#  -y|--no-prompt   do not prompt for review/confirmation
#
function stop_modify {
  # get the running user
  get_user
  local SkipPrompt=0 Message="$USERNAME completed modifications at $( date )" Push=0
  # process arguments
  while [ $# -gt 0 ]; do case "$1" in
    -p|--push) Push=1;;
    -m|--message) Message="$2"; shift;;
    -y|--no-prompt) SkipPrompt=1;;
    *) if [[ "$1" =~ ^-m ]]; then Message=$( echo $1 |-perl -pe 's/^..//g' ); shift; fi;;
  esac; shift; done
  # switch directories
  pushd $CONF >/dev/null 2>&1 || err
  # validate the lock
  if [[ $SCS_SharedLocalRepo -eq 1 && -f .scs_lock ]]; then
    if [ "$USERNAME" != "$( cat .scs_lock )" ]; then err "The configuration is locked by $( cat .scs_lock )"; fi
  fi
  # handle submodules
  if [ -f .gitmodules ]; then for F in $( grep "path = " .gitmodules |perl -pe 's/[[:space:]]*path = //' ); do
    if [ -d $F ]; then
      pushd $F >/dev/null 2>&1
      git commit -a -m"$Message" >/dev/null 2>&1
      if [[ $Push -eq 1 && $SkipPrompt -eq 0 ]]; then
        git_push --title "Sub-module $F" --path "$CONF/$F" || err "Error pushing changes to upstream repository!"
      elif [[ $Push -eq 1 ]]; then
        git_push --title "Sub-module $F" --path "$CONF/$F" --no-prompt || err "Error pushing changes to upstream repository!"
      fi
      popd >/dev/null 2>&1
      git add $F >/dev/null 2>&1
      git commit -m'commited submodules changes' $F >/dev/null 2>&1
    fi
  done; fi
  # check for modifications
  L=$( git status -s |wc -l 2>/dev/null |awk '{print $1}' )
  # just unlock &&/|| push if there are not uncommitted changes
  if [[ $L -eq 0 ]]; then
    if [[ $Push -eq 1 && $SkipPrompt -eq 0 ]]; then
      git_push --path $CONF || err "Error pushing changes to upstream repository!"
    elif [[ $Push -eq 1 ]]; then
      git_push --path $CONF --no-prompt || err "Error pushing changes to upstream repository!"
    fi
    if [[ $SCS_SharedLocalRepo -eq 1 && -f .scs_lock ]]; then
      rm -f .scs_lock
      printf -- '\E[32;47m%s\E[0m\n' "***** SCS UNLOCKED [$( git branch |grep ^* |cut -d' ' -f2 )] *****" >&2
    fi
    popd >/dev/null 2>&1
    return 0
  fi
  # there are uncommitted modifictions
  if [ $SkipPrompt -ne 1 ]; then
    get_yn DF "$L files have been modified. Do you want to review the changes (y/n)?"
    test "$DF" == "y" && git diff
    get_yn DF "Do you want to commit the changes (y/n)?"
    if [ "$DF" != "y" ]; then return 0; fi
  fi
  git commit -a -m"$Message" >/dev/null 2>&1 || err "Error committing outstanding changes"
  if [[ $Push -eq 1 && $SkipPrompt -eq 0 ]]; then
    git_push --path $CONF || err "Error pushing changes to upstream repository!"
  elif [[ $Push -eq 1 ]]; then
    git_push --path $CONF --no-prompt || err "Error pushing changes to upstream repository!"
  fi
  if [[ $SCS_SharedLocalRepo -eq 1 && -f .scs_lock ]]; then rm -f .scs_lock; fi
  popd >/dev/null 2>&1
  printf -- '\E[32;47m%s\E[0m\n' "***** SCS UNLOCKED [$( git branch |grep ^* |cut -d' ' -f2 )] *****" >&2
  scslog "committed pending changes with message: $Message"
}


#Section: APPLICATION
    #    ######  ######  #       ###  #####     #    ####### ### ####### #     #
   # #   #     # #     # #        #  #     #   # #      #     #  #     # ##    #
  #   #  #     # #     # #        #  #        #   #     #     #  #     # # #   #
 #     # ######  ######  #        #  #       #     #    #     #  #     # #  #  #
 ####### #       #       #        #  #       #######    #     #  #     # #   # #
 #     # #       #       #        #  #     # #     #    #     #  #     # #    ##
 #     # #       #       ####### ###  #####  #     #    #    ### ####### #     #

# manage global application constants
#
# constant [--define|--undefine|--list]
function application_constant {
  case "$1" in
    --define) application_constant_define ${@:2};;
    --undefine) application_constant_undefine ${@:2};;
    *) application_constant_list ${@:2};;
  esac
}

# define a constant for an application
#
function application_constant_define {
  local APP C
  generic_choose application "$1" APP && shift
  generic_choose constant "$1" C && shift
  constant_define --application "$APP" "$C" $@
}

# undefine a constant for an environment
#
function application_constant_undefine {
  local APP
  generic_choose application "$1" APP && shift
  constant_undefine --application "$APP"
}

function application_constant_list {
  local APP NUM A S
  generic_choose application "$1" APP && shift
  NUM=$( wc -l ${CONF}/value/by-app/$APP 2>/dev/null |awk '{print $1}' )
  test -z "$NUM" && NUM=0
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined constant${S} for $APP."
  test $NUM -eq 0 && return
  awk 'BEGIN{FS=","}{print $1}' ${CONF}/value/by-app/$APP |fold_list |perl -pe 's/^/   /'
}

function application_create {
  start_modify
  # get user input and validate
  get_input NAME "Name" --auto "$1"
  application_exists "$NAME" && err "Application already defined."
  get_input ALIAS "Alias" --auto "$2"
  application_exists --alias "$ALIAS" && err "Alias already defined."
  get_input BUILD "Build" --null --options "$( build_list_unformatted |replace )" --auto "$3"
  get_yn CLUSTER "LVS Support (y/n)" --auto "$4"
  # [FORMAT:application]
  printf -- "${NAME},${ALIAS},${BUILD},${CLUSTER}\n" >>$CONF/application
  commit_file application
}
function application_create_help { cat <<_EOF
Add a new application to SCS.

Usage: $0 application create [name] [alias] [build] [cluster]

Fields:
  Name - a unique name for the application, such as 'purchase'.
  Alias - a common alias for the application.  this field is not currently utilized.
  Build - the name of the system build this application is installed to.
  LVS Support - whether or not this application can sit behind a load balancer with more than one node.

_EOF
}

function application_delete {
  local APP="$1" C TYPE VAL ASSIGN_TYPE ASSIGN_TO NAME DESC
  generic_delete application $APP || return
  # delete from file-map as well
  # [FORMAT:file-map]
  perl -i -ne "print unless /^[^,]*,$APP,.*\$/" $CONF/file-map
  # [FORMAT:resource]
  for C in $( grep -E '^([^,]*,){2}application,([^,:]*:){2}'$APP',.*' resource |awk 'BEGIN{FS=","}{print $2}' ); do
    # [FORMAT:resource]
    IFS="," read -r TYPE VAL ASSIGN_TYPE ASSIGN_TO NAME DESC <<< "$( grep -E "^[^,]*,$C," ${CONF}/resource )"
    # [FORMAT:resource]
    perl -i -pe "s/[^,]*,$C,.*/${TYPE},${VAL//,/},,not assigned,${NAME//,/},${DESC}/" ${CONF}/resource
  done
  if [ -f "$CONF/value/by-app/$APP" ]; then delete_file value/by-app/$APP; fi
  for C in $( ls $CONF/env ); do if [ -f "$CONF/env/$C/by-app/$APP" ]; then delete_file env/$C/by-app/$APP; fi; done
  commit_file file-map resource
}
function application_delete_help { cat <<_EOF
Delete an application and its references from SCS.

Usage: $0 application delete [name]

If the name of the application is not provided as an argument you will be prompted to select it from a list.

_EOF
}

# general application help
#
function application_help { cat <<_EOF
NAME
	SCS Applications

SYNOPSIS
	scs application [create|delete|list|show|update] [<name>]
	scs application constant [--define|--undefine|--list] [<application>] [<constant>]
	scs application file [--add|--remove|--list]
	scs environment application [<environment>] [--list] [<location>]
	scs environment application [<environment>] [--name <app_name>] [--add|--remove|--assign-resource|--unassign-resource|--list-resource] [<location>]
	scs environment application [<environment>] [--name <app_name>] [--define|--undefine|--list-constant] [<application>]

DESCRIPTION
	An application is a collection of files and settings that are deployed to a system (an instance of a build).

	Applications are assigned to a single build and one or more environments.

	Generally if you do not provide a required argument you will prompted for it, e.g.:
		$0 application show
	... will output a list of applications and ask you to select one to show.

	Pressing ctrl+c at any time will abort and return you to your shell.

	Any command that alters the running configuration automatically locks scs.  Run \`$0 help lock\` for more information.

	To list defined applications, run:
		$0 application list

	To show the details of an application, run:
		$0 application show <name>

	To update a defined application:
		$0 application edit <name>

OPTIONS
	application create
		create (or define) a new application and tie to a build

	application delete [<name>]
		delete an application and purge all related data

	application list [--no-format|-1]
		list defined applications

		The '--no-format' or '-1' argument outputs the list without any summary information.

	application show [<name>] [--brief] [--files] [--systems]
		show details for an application and related objects.

		'--brief' will only output the application details and skip extraneous data.

		'--files' will only output the linked configuration files.

		'--systems' will only output the linked system objects.

	application update [<name>]
		update application settings or rename an application

	application constant --define [<application>] [<constant>]
		define a constant in the global application scope (priority 4)

	application constant --undefine [<application>] [<constant>]
		undefine (or clear) a defined constant in the global application scope (priority 4)

	application constant --list [<application>] [<constant>]
		show defined constants in the global application scope (priority 4)

	application file --add
		link a file to an application.  The same file can be linked to many applications.

	application file --remove
		unlink a file from an application

	application file --list
		show linked files

	environment application [<environment>] [--list] [<location>]
		show applications 'installed' or linked to an environment at a location
		applications can not be linked to a global environment and must tie to a location.
		
	environment application [<environment>] [--name <app_name>] --add [<location>]
		link (or install) an application in an environment at a location

	environment application [<environment>] [--name <app_name>] --remove [<location>]
		unlock (remove) an application from an environment at a location

	environment application [<environment>] [--name <app_name>] --assign-resource [<location>]
		assign a resource to an application in an environment at a location
		this will usually be used to assign cluster IPs (load balanced real IPs or 'cluster_ip') or
		heartbeat (high-availiability cluster) IP addressess or 'ha_ip' to an application in an
	  	environment.

		a typical example is X application is installed on Y real servers behind a load balancer.
		a resource is defined as a 'cluster_ip', which is the address on the load balancer and the
		loopback on each application server.  in order to make the cluster_ip resource available to
		scs when building configuration files it must be linked to the application in the environment
		and location using this command.

	environment application [<environment>] [--name <app_name>] --unassign-resource [<location>]
		unassign a resource from an application in an environment at a location.

		this releases the resource so it can be assigned to another application (or removed).

	environment application [<environment>] [--name <app_name>] --list-resource [<location>]
		show resources assigned to an application in an environment at a location.
		
	environment application [<environment>] [--name <app_name>] --define [<application>]
		define a constant for an application in the scope of an environment (priority 1)

		when constants are enumerated for replacement in file templates, those in this scope have
		priority over all other defined constants.

	environment application [<environment>] [--name <app_name>] --undefine [<application>]
		undefine (or clear) a defined constant in scope of an application in an environment (priority 1)

	environment application [<environment>] [--name <app_name>] --list-constant [<application>]
		show defined constants in scope of the application in an environment (priority 1)

EXAMPLES
	Create a new application:
		$0 application create

RETURN CODE
	scs returns 0 on success and non-zero on error.

AUTHOR
	William Strucke <wstrucke@gmail.com>

COPYRIGHT
	Copyright © 2014 William Strucke. License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
	This is free software: you are free to change and redistribute it.  There is NO WARRANTY, to the extent permitted by law.

SEE ALSO
	$0 help
_EOF
}

# checks if an application is defined
#
# optional:
#   --alias  check alias instead of name
#
function application_exists {
  local ALIAS=0
  if [ "$1" == "--alias" ]; then ALIAS=1; shift; fi
  test $# -eq 1 || return 1
  if [ $ALIAS -eq 0 ]; then
    # [FORMAT:application]
    grep -qE "^$1," $CONF/application || return 1
  else
    # [FORMAT:application]
    grep -qE ",$ALIAS," $CONF/application || return 1
  fi
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
  # [FORMAT:file-map]
  grep -qE "^$F,$APP," $CONF/file-map && return
  # [FORMAT:file-map]
  echo "$F,$APP," >>$CONF/file-map
  commit_file file-map
}
function application_file_add_help { cat <<_EOF
Link a file to an application

Usage: $0 application [<application_name>] file --add [<file_name>]

_EOF
}

# list files associated with an application
#
# this function is called both internally and externally
#
# optional:
#   --no-format   output the list without formatting
#
function application_file_list {
  test -z "$1" && shift
  if [ "$1" == "--no-format" ]; then shift; application_file_list_unformatted $@; return; fi
  local APP="$1" A S NUM F EN
  application_exists $APP || err "Unknown application"
  NUM=$( application_file_list_unformatted $APP |wc -l 2>/dev/null |awk '{print $1}' )
  test -z "$NUM" && NUM=0
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} file${S} linked to $APP."
  test $NUM -eq 0 && return
  ( for F in $( application_file_list_unformatted $APP ); do
    # [FORMAT:file]
    grep -E "^$F," $CONF/file |awk 'BEGIN{FS=","}{print $1,$2}'
  done ) |column -t |perl -pe 's/^/   /'
}
function application_file_list_help { cat <<_EOF
List all files linked to an application

Usage: $0 application [<application_name>] file --list

_EOF
}

# retrieve the list of files associated with an application
#
# optional:
#   --environment <string>	limit to files included in an environment
#
function application_file_list_unformatted {
  local App="$1" List NewList E EN File Limit Include; shift
  application_exists $App || err "Unknown application"

  while [ $# -gt 0 ]; do case $1 in
    --environment) EN="$2"; shift;;
  esac; shift; done

  # [FORMAT:file-map]
  List=$( grep -E "^[^,]*,$App," $CONF/file-map |awk 'BEGIN{FS=","}{print $1}' )

  if ! [ -z "$EN" ]; then
    NewList=""
    for File in $List; do
      # [FORMAT:file-map]
      Limit=$( grep -E "^$File,$App," $CONF/file-map |awk 'BEGIN{FS=","}{print $3}' )
      if [ -z "$Limit" ]; then NewList="$NewList $File"; continue; fi
      # translate the environment inclusion/exclusion syntax:
      # ''	(nothing) is the same as 'all'
      # 'all'	all environments match
      # 'none'	no environments match
      # '+name'	include environment
      # '-name'	exclude environment
      Include=0
      if [ "$Limit" == "" ]; then
        Include=1
      elif [ "${Limit:0:3}" == "all" ]; then
        Include=1
        for E in $( echo $Limit |tr '-' ' ' ); do if [ "${EN//-/_}" == "$E" ]; then Include=0; fi; done
      elif [ "${Limit:0:4}" == "none" ]; then
        Include=0
        for E in $( echo $Limit |tr '+' ' ' ); do if [ "${EN//-/_}" == "$E" ]; then Include=1; fi; done
      else
        err "Unhandled or invalid value in file::application map environment limit: '$Limit'"
      fi
      if [ $Include -eq 1 ]; then NewList="$NewList $File"; fi
    done
    List="$NewList"
  fi

  echo $List |tr ' ' '\n' |sort
}

# unlink a file from an application
#
# required:
#  $1  application
#  $2  file
#
# optional:
#  --no-prompt  do not confirm the action
#
function application_file_remove {
  local Application File SkipPrompt=0
  while [[ $# -gt 0 ]]; do case "$1" in
    --no-prompt) SkipPrompt=1;;
    *)
      if [[ -z "$Application" ]]; then Application="$1";
      elif [[ -z "$File" ]]; then File="$1";
      else application_file_remove_help; return 1; fi
      ;;
  esac; shift; done
  generic_choose application "$Application" Application
  # get the requested file or abort
  generic_choose file "$File" File
  # confirm
  if [[ $SkipPrompt -eq 0 ]]; then
    get_yn RL "Are you sure (y/n)?"
    if [ "$RL" != "y" ]; then return; fi
  fi
  start_modify
  # remove the mapping if it exists
  # [FORMAT:file-map]
  grep -qE "^$File,$Application," $CONF/file-map || err "Error - requested file is not associated with $Application."
  # [FORMAT:file-map]
  perl -i -ne "print unless /^$File,$Application,/" $CONF/file-map
  commit_file file-map
}
function application_file_remove_help { cat <<_EOF
Unlink a file from an application

Usage: $0 application file --remove [<application_name>] [<file_name>] [--no-prompt]

_EOF
}

function application_list {
  if [[ "$1" == "--no-format" || "$1" == "-1" ]]; then shift; application_list_unformatted $@; return; fi
  NUM=$( wc -l $CONF/application |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined application${S}."
  test $NUM -eq 0 && return
  application_list_unformatted $@ |fold_list |perl -pe 's/^/   /'
}

function application_list_unformatted {
  # [FORMAT:application]
  awk 'BEGIN{FS=","}{print $1}' $CONF/application |sort
}

# application_show
#
# output application details and linked objects
#
# optional:
#   --brief      only show the application details
#   --files      only show linked files
#   --systems    only show linked systems
#
function application_show {
  application_exists "$1" || err "Provide the application name"
  local APP ALIAS BUILD CLUSTER FILES i SystemList \
        ShowDetail=1 ShowFiles=1 ShowSystems=1

  case "$2" in
    --brief) ShowFiles=0; ShowSystems=0;;
    --files) ShowDetail=0; ShowSystems=0;;
    --systems) ShowDetail=0; ShowFiles=0;;
  esac

  # [FORMAT:application]
  IFS="," read -r APP ALIAS BUILD CLUSTER <<< "$( grep -E "^$1," ${CONF}/application )"
  if [[ $ShowDetail -eq 1 ]]; then
    printf -- "Name: $APP\nAlias: $ALIAS\nBuild: $BUILD\nCluster Support: $CLUSTER\n"
  fi

  if [[ $ShowSystems -eq 1 ]]; then
    # list systems by environment
    if [[ $ShowDetail -eq 1 ]]; then printf -- '\nSystems:\n'; fi
    SystemList=( $( system_list_unformatted --build $BUILD ) )
    if [[ ${#SystemList[*]} -gt 0 ]]; then
      for ((i=0;i<${#SystemList[*]};i++)); do
        # [FORMAT:system]
        grep -E "^${SystemList[i]}," ${CONF}/system |perl -pe 's/^([^,]*),([^,]*,){3}([^,]*),.*/\3 \1/'
      done |sort -k1,2 |column -t |perl -pe 's/^/   /'
    else
      printf -- '  None\n'
    fi
  fi

  if [[ $ShowFiles -eq 1 ]]; then
    # retrieve file list
    FILES=( $( application_file_list_unformatted $APP ) )
    # output linked configuration file list
    if [ ${#FILES[*]} -gt 0 ]; then
      if [[ $ShowDetail -eq 1 ]]; then printf -- "\nManaged configuration files:\n"; fi
      for ((i=0;i<${#FILES[*]};i++)); do
        # [FORMAT:file]
        grep -E "^${FILES[i]}," $CONF/file |awk 'BEGIN{FS=","}{print $1,$2}'
      done |sort |uniq |column -t |perl -pe 's/^/   /'
    else
      printf -- "\nNo managed configuration files."
    fi
  fi
}

# application_update
#
# alters the configuration for an existing application, including rename
#
function application_update {
  local APP ALIAS BUILD CLUSTER NAME File Location

  start_modify
  generic_choose application "$1" APP && shift

  # [FORMAT:application]
  IFS="," read -r APP ALIAS BUILD CLUSTER <<< "$( grep -E "^$APP," ${CONF}/application )"
  get_input NAME "Name" --default "$APP"
  get_input ALIAS "Alias" --default "$ALIAS"
  get_input BUILD "Build" --default "$BUILD" --null --options "$( build_list_unformatted |replace )"
  get_yn CLUSTER "LVS Support (y/n)"

  # [FORMAT:application]
  perl -i -pe "s/^$APP,.*/${NAME},${ALIAS},${BUILD},${CLUSTER}/" ${CONF}/application

  # handle rename
  if [[ "$NAME" != "$APP" ]]; then

     # switch to the config directory to perform git operations
     pushd ${CONF} >/dev/null 2>&1

     if [[ -s environment ]]; then

       # [FORMAT:environment]
       for Environment in $( perl -pe 's/,.*//' environment ); do

         # update environment as neeeded
         if [[ -d $Environment && -f env/$Environment/by-app/$APP ]]; then
           # [FORMAT:value/env/app]
           git mv env/$Environment/by-app/$APP env/$Environment/by-app/$NAME
         fi

         if [[ -s location ]]; then
           # [FORMAT:location]
           for Location in $( perl -pe 's/,.*//' location ); do
             if ! [[ -s $Location/$Environment ]]; then continue; fi
             # update environment
             # [FORMAT:<location></env>]
             perl -i -pe "s/^$APP\$/$NAME/" $Location/$Environment
           done
         fi

       done

     fi

     if [[ -s value/by-app/$APP ]]; then
       # [FORMAT:value/by-app/constant]
       git mv value/by-app/$APP value/by-app/$NAME
     fi

     # [FORMAT:file-map]
     perl -i -pe "s/([^,]*,)$APP(,.*)/\1$NAME\2/" file-map

     # [FORMAT:resource]
     perl -i -pe "s/:$APP,/:$NAME,/" resource

     # switch back
     popd >/dev/null 2>&1

  fi
  commit_file application
}


#Section: BUILD
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
  # [FORMAT:application]
  grep -E ",$C," ${CONF}/application |awk 'BEGIN{FS=","}{print $1}'
}

function build_create {
  start_modify
  # get user input and validate
  get_input NAME "Build"
  build_exists "$NAME" && err "Build already defined."
  get_input ROLE "Role" --null
  get_yn P "Child Build (y/n)?"
  if [ $? -eq 0 ]; then generic_choose build "" PARENT; else PARENT=""; fi
  if [ -z "$PARENT" ]; then
    get_input OS "Operating System" --null --options $OSLIST
    get_input ARCH "Architecture" --null --options $OSARCH
  else
    OS=""; ARCH=""
    # avoid circular dependencies
    printf -- ","$( build_lineage_unformatted $PARENT )"," |grep -q ",${NAME},"
    if [ $? -eq 0 ]; then err "This build is already a parent of the parent build you selected. This would create a circular dependency, aborted!"; fi
  fi
  get_input DISK "Disk Size (in GB, Default ${DEF_HDD})" --null --regex '^[1-9][0-9]*$'
  get_input RAM "Memory Size (in MB, Default ${DEF_MEM})" --null --regex '^[1-9][0-9]*$'
  get_input DESC "Description" --nc --null
  # [FORMAT:build]
  printf -- "${NAME},${ROLE},${DESC//,/},${OS},${ARCH},${DISK},${RAM},${PARENT}\n" >>$CONF/build
  commit_file build
}

function build_delete {
  build_exists "$1" || err "Missing or invalid build name"
  local InUse=0
  # prompt if the build is in use before deleting it
  # [FORMAT:application]
  grep -qE "^([^,]*,){2}$1," ${CONF}/application
  if [[ $? -eq 0 ]]; then
    InUse=1
    printf -- 'Warning: build is in use for the following applications:\n'
    # [FORMAT:application]
    grep -E "^([^,]*,){2}$1," ${CONF}/application |perl -pe 's/^([^,]*),.*/\1/; s/^/  /'
  fi
  # [FORMAT:system]
  grep -qE "^([^,]*),$1," ${CONF}/system
  if [[ $? -eq 0 ]]; then
    InUse=1
    printf -- 'Warning: build is in use for the following systems:\n'
    # [FORMAT:system]
    grep -E "^([^,]*),$1," ${CONF}/system |perl -pe 's/^([^,]*),.*/\1/; s/^/  /'
  fi
  # [FORMAT:build]
  grep -qE "^([^,]*,){7}$1\$" ${CONF}/build
  if [[ $? -eq 0 ]]; then
    InUse=1
    printf -- 'Warning: build is a parent for the following builds:\n'
    # [FORMAT:build]
    grep -E "^([^,]*,){7}$1\$" ${CONF}/build |perl -pe 's/^([^,]*),.*/\1/; s/^/  /'
  fi
  if [[ $InUse -eq 1 ]]; then
    get_yn R "Are you sure you want to delete build $1 (y/n)?" || return 1
  fi
  # execute delete operation
  generic_delete build $1
}

# general build help
#
function build_help { cat <<_EOF
NAME
	Builds

SYNOPSIS
	scs build [create|delete|list|show|update] [<name>]
	scs build lineage <name> [--reverse]
	scs build list [--tree] [--detail]

DESCRIPTION
	Builds serve two purposes in scs -- they link applications to servers and assign the system to a role in the
	system build process.

	Roles represent a set of packages and system settings designed to prepare a system for the application server
	and applications assigned to it.  A future scs release may replace the role with the actual package list,
	negating the need for the system build scripts entirely.

	Builds can optionally have a single parent build.  If utilized, this must directly tie to the inheritence
	structure in the system build process (the 'role').  This feature allows virtual systems to be built as a series of
	overlays, which can boost performance and reduce memory and disk utilization on the hypervisor.

OPTIONS

EXAMPLES
	build create
		Define a new build and configure it.

	build delete
		Permanently delete and remove a build.  Use caution deleting builds as they could be assigned to defined
		systems.

	build lineage [<name>] [--reverse]
		Display the inheritence path for a build.  This is only useful for builds with a defined parent.

		The '--reverse' option outputs the inheritence in reverse.

	build list [--tree] [--detail]
		List the defined builds.

		The '--tree' option outputs the inheritence path for each build in a visual tree structure.

		The '--detail' option includes the build description in a second column.

	build show
		Show a defined build, settings, and any linked applications.

	build update
		Update the settings for an existing build.


RETURN CODE
	scs returns 0 on success and non-zero on error.

AUTHOR
	William Strucke <wstrucke@gmail.com>

COPYRIGHT
	Copyright © 2014 William Strucke. License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
	This is free software: you are free to change and redistribute it.  There is NO WARRANTY, to the extent permitted by law.

SEE ALSO
	$0 help
_EOF
}

# checks if a build is defined
#
function build_exists {
  test $# -eq 1 || return 1
  # [FORMAT:build]
  grep -qE "^$1," $CONF/build || return 1
}

function build_lineage {
  build_lineage_unformatted $@ |perl -pe 's/,/ -> /g'
}

# return the lineage of a build
#
#   root,child,grandchild,etc...
#
# optional:
#   --reverse   lookup all builds containing X instead of from X
#
function build_lineage_unformatted {
  generic_choose build "$1" C
  local LINEAGE PARENT Build BuildList LocalLineage
  if [ "$2" == "--reverse" ]; then
    BuildList="$( build_list_unformatted |tr '\n' ' ' )"
    LINEAGE="$1"
    for Build in $BuildList; do
      [ "$Build" == "$1" ] && continue
      LocalLineage="$( build_lineage $Build |perl -pe "s/^.* $1 /$1 /" )"
      printf -- " -> ${LocalLineage} -> " |grep -q " -> $1 -> " && LINEAGE="${LINEAGE}\t${LocalLineage}"
    done
    printf -- "$LINEAGE" |tr '\t' '\n'
  else
    LINEAGE="$C"
    PARENT=$( build_parent $C )
    while [ ! -z "$PARENT" ]; do
      LINEAGE="$PARENT,$LINEAGE"
      PARENT=$( build_parent $PARENT )
    done
    printf -- "$LINEAGE"
  fi
}

function build_list {
  NUM=$( wc -l ${CONF}/build |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined build${S}."
  test $NUM -eq 0 && return
  if [ "$1" == "--tree" ]; then
    shift
    build_list_format_tree $@
  else
    if [ $# -gt 0 ]; then
      build_list_unformatted $@ |column -s',' -t
    else
      build_list_unformatted $@ |fold_list
    fi
  fi |perl -pe 's/^/   /'
}

# output the list of builds in a tree structure
#
function build_list_format_tree {
  local LINE
  local IFS=$'\n'
  for LINE in $( build_list_unformatted $@ ); do
    IFS=',' read -r B D <<< "$LINE"
    printf -- "$( build_lineage_unformatted $B )\t$D\n"
  done |LC_ALL=C sort |perl -pe 's/([^,]*,)/"    \\" . ("-" x (length($1)-4)) . "> "/gei' |perl -pe 's/(\s+\\-+>\s+\\)/" " x length($1) . "\\"/gei' |column -s$'\t' -t
}

function build_list_unformatted {
  if [ "$1" == "--detail" ]; then
    # [FORMAT:build]
    awk 'BEGIN{FS=","}{print $1","$3}' ${CONF}/build
  else
    awk 'BEGIN{FS=","}{print $1}' ${CONF}/build
  fi |sort
}

# get the parent of a build
#
function build_parent {
  local NAME ROLE DESC OS ARCH DISK RAM PARENT
  # [FORMAT:build]
  IFS="," read -r NAME ROLE DESC OS ARCH DISK RAM PARENT <<< "$( grep -E "^$1," ${CONF}/build )"
  printf -- "$PARENT\n"
  test -z "$PARENT" && return 1 || return 0
}

# get the root of a build
#
function build_root {
  generic_choose build "$1" C
  local ROOT
  ROOT="$C"
  PARENT=$( build_parent $C )
  while [ ! -z "$PARENT" ]; do
    ROOT="$PARENT"
    PARENT=$( build_parent $PARENT )
  done
  printf -- "$ROOT"
}

function build_show {
  build_exists "$1" || err "Missing or invalid build name"
  local NAME ROLE DESC OS ARCH DISK RAM PARENT RNAME RROLE RDESC RDISK RRAM RP BRIEF=0
  [ "$2" == "--brief" ] && BRIEF=1
  # [FORMAT:build]
  IFS="," read -r NAME ROLE DESC OS ARCH DISK RAM PARENT <<< "$( grep -E "^$1," ${CONF}/build )"
  if [ ! -z "$PARENT" ]; then
    ROOT=$( build_root $NAME )
    # [FORMAT:build]
    IFS="," read -r RNAME RROLE RDESC OS ARCH RDISK RRAM RP <<< "$( grep -E "^$ROOT," ${CONF}/build )"
    if [ -z "$DISK" ]; then DISK=$RDISK; fi
    if [ -z "$RAM" ]; then RAM=$RRAM; fi
  fi
  printf -- "Build: $NAME\nRole: $ROLE\nParent Build: $PARENT\nOperating System: $OS-$ARCH\nDisk Size (GB): $DISK\nMemory (MB): $RAM\nDescription: $DESC\n"
  printf -- "Lineage: $( build_lineage $NAME )\n"
  test $BRIEF -eq 1 && return
  # look up the applications configured for this build
  NUM=$( build_application_list "$1" |wc -l |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo -e "\nThere ${A} ${NUM} linked application${S}."
  if [ $NUM -gt 0 ]; then build_application_list "$1" |perl -pe 's/^/   /'; fi
}

function build_update {
  local ORIGNAME NAME ROLE DESC OS ARCH DISK RAM PARENT C P
  start_modify
  generic_choose build "$1" C && shift
  # [FORMAT:build]
  IFS="," read -r ORIGNAME ROLE DESC OS ARCH DISK RAM PARENT <<< "$( grep -E "^$C," ${CONF}/build )"
  get_input NAME "Build" --default "$ORIGNAME"
  get_input ROLE "Role" --default "$ROLE" --null
  get_yn P "Child Build [$PARENT] (y/n)?"
  if [ $? -eq 0 ]; then generic_choose build "" PARENT; else PARENT=""; fi
  if [ -z "$PARENT" ]; then
    get_input OS "Operating System" --default "$OS" --null --options $OSLIST
    get_input ARCH "Architecture" --default "$ARCH" --null --options $OSARCH
  else
    OS=""; ARCH=""
    # avoid circular dependencies
    printf -- ","$( build_lineage_unformatted $PARENT )"," |grep -q ",${NAME},"
    if [ $? -eq 0 ]; then err "This build is already a parent of the parent build you selected. This would create a circular dependency, aborted!"; fi
  fi
  get_input DISK "Disk Size (in GB, Default ${DEF_HDD})" --null --regex '^[1-9][0-9]*$' --default "$DISK"
  get_input RAM "Memory Size (in MB, Default ${DEF_MEM})" --null --regex '^[1-9][0-9]*$' --default "$RAM"
  get_input DESC "Description" --default "$DESC" --nc --null
  # [FORMAT:build]
  perl -i -pe "my \$str = '${NAME},${ROLE},${DESC//,/},${OS},${ARCH},${DISK},${RAM},${PARENT}'; s/^$C,.*/\$str/" ${CONF}/build
  commit_file build
  # handle rename
  if [[ "$NAME" != "$ORIGNAME" ]]; then
    # [FORMAT:system]
    perl -i -pe "s/([^,]*),$ORIGNAME,(.*)/\1,$NAME,\2/" ${CONF}/system
    # [FORMAT:application]
    perl -i -pe "s/([^,]*,[^,]*),$ORIGNAME,(.*)/\1,$NAME,\2/" ${CONF}/application
    # [FORMAT:build]
    perl -i -pe "s/(.*),$ORIGNAME\$/\\1,$NAME/" ${CONF}/build
  fi
}


#Section: CONSTANT
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
  # [FORMAT:constant]
  printf -- "${NAME},${DESC}\n" >>$CONF/constant
  commit_file constant
}

function constant_define {
  local NAME VAL SYSTEM APP EN LOC FILE NULL=0
  generic_choose constant "$1" NAME && shift

  while [ $# -gt 0 ]; do case $1 in
    --application) application_exists "$2" || err "Invalid application"; APP=$2; shift;;
    --environment) environment_exists "$2" || err "Invalid environment"; EN=$2; shift;;
    --location) location_exists "$2" || err "Invalid location"; LOC=$2; shift;;
    --null) NULL=1;;
    *) if [[ -z "$VAL" ]]; then VAL="$1"; else usage; fi;;
  esac; shift; done

  if [[ -n ${EN} && -n ${APP} ]]; then
    # [FORMAT:value/env/app]
    FILE=$CONF/env/$EN/by-app/$APP
  elif [[ -n ${EN} && -n ${LOC} ]]; then
    # [FORMAT:value/loc/constant]
    FILE=$CONF/env/$EN/by-loc/$LOC
  elif [[ -n ${EN} ]]; then
    # [FORMAT:value/env/constant]
    FILE=$CONF/env/$EN/constant
  elif [[ -n ${APP} ]]; then
    # [FORMAT:value/by-app/constant]
    FILE=$CONF/value/by-app/$APP
  else
    # [FORMAT:value/constant]
    FILE=$CONF/value/constant
  fi

  if [[ -z "$VAL" && $NULL -eq 0 ]]; then
    get_input VAL "Value" --nc --null
  fi

  start_modify
  if ! [ -f $FILE ]; then
    if ! [ -d $( dirname $FILE ) ]; then mkdir -p $( dirname $FILE ); fi
    touch $FILE
  fi
  grep -qE "^$NAME," $FILE
  if [ $? -eq 0 ]; then
    # already define, update value
    perl -i -pe "my \$str = '$NAME,${VAL//&/\&}'; s/^$NAME,.*/\$str/" $FILE
  else
    # not defined, add
    printf -- "$NAME,$VAL\n" >>$FILE
  fi
  commit_file $FILE
}

function constant_delete {
  local i j NAME="$1"
  generic_delete constant $NAME
  cd $CONF >/dev/null 2>&1 || return

  # list environments and applications
  EnList=$( environment_list --no-format )
  AppList=$( application_list --no-format )
  LocList=$( location_list --no-format )

  # 1. applications @ environment
  for i in $EnList; do
    for j in $AppList; do
      # [FORMAT:value/env/app]
      if [ -f "${CONF}/env/$i/by-app/$j" ]; then
        grep -qE "^$NAME," "${CONF}/env/$i/by-app/$j"
        if [[ $? -eq 0 ]]; then perl -i -ne "print unless /^$1,/" ${CONF}/env/$i/by-app/$j; commit_file ${CONF}/env/$i/by-app/$j; fi
      fi
    done
  done

  # 2. environments @ location
  for i in $LocList; do
    for j in $EnList; do
      # [FORMAT:value/loc/constant]
      if [ -f "${CONF}/env/$j/by-loc/$i" ]; then
        grep -qE "^$NAME," "${CONF}/env/$j/by-loc/$i"
        if [[ $? -eq 0 ]]; then perl -i -ne "print unless /^$1,/" ${CONF}/env/$j/by-loc/$i; commit_file ${CONF}/env/$j/by-loc/$i; fi
      fi
    done
  done

  # 3. environments (global)
  for i in $EnList; do
    # [FORMAT:value/env/constant]
    if [ -f "${CONF}/env/$i/constant" ]; then
      grep -qE "^$NAME," "${CONF}/env/$i/constant"
      if [[ $? -eq 0 ]]; then perl -i -ne "print unless /^$1,/" ${CONF}/env/$i/constant; commit_file ${CONF}/env/$i/constant; fi
    fi
  done

  # 4. applications (global)
  for i in $AppList; do
    # [FORMAT:value/by-app/constant]
    if [ -f "${CONF}/value/by-app/$i" ]; then
      grep -qE "^$NAME," "${CONF}/value/by-app/$i"
      if [[ $? -eq 0 ]]; then perl -i -ne "print unless /^$1,/" ${CONF}/value/by-app/$i; commit_file ${CONF}/value/by-app/$i; fi
    fi
  done

  # 5. global
  # [FORMAT:value/constant]
  grep -qE "^$NAME," ${CONF}/value/constant
  if [[ $? -eq 0 ]]; then perl -i -ne "print unless /^$1,/" ${CONF}/value/constant; commit_file ${CONF}/value/constant; fi
}

# general constant help
#
function constant_help { cat <<_EOF
NAME
	Constants (Variables)

SYNOPSIS
	scs application constant [--define|--undefine|--list] [<application>] [<constant>]
	scs constant [create|delete|list|show|update] [<name>]
	scs environment application [<environment>] [--name <app_name>] [--define|--undefine|--list-constant] [<application>]
	scs environment constant [--define|--undefine|--list] [<environment>] [<constant>]
	scs location [<name>] constant [--define|--undefine|--list] [<environment>] [<constant>]

DESCRIPTION
	Constants allow arbitrary values to be substituted in configuration files and can be conditionally defined based
	on a system's environment, location, and/or application.

	When multiple values are defined for a constant they are sorted by order of preference, then the highest ranked
	value is applied to the configuration.  This functionality allows for global variables, which are generally useful
	as a fallback or reserve value for a constant when no other definition is in scope.

	Scopes include, in order of precedence:
		1. Application in an Environment
		2. Environment at a Location
		3. Environment (Global)
		4. Application (Global)
		5. Global

	There is currently no way to define a constant in the global scope (priority 5) using the scs UI.

OPTIONS
	application constant --define [<application>] [<constant>]
		Define a constant in the global application scope (priority 4).

	application constant --list [<application>] [<constant>]
		List constants defined in the global application scope (priority 4) for an application.

	application constant --undefine [<application>] [<constant>]
		Remove the definition for a constant in the global application scope (priority 4).

	constant create
		Create a constant that can be defined and referenced in configuration files.

	constant define [--application <name>] [--environment <name>] [--location <name>] [--null] [<value>]
		Define a constant in any scope.  If --null is provided and no value is specified the
		constant will be set to an empty string, otherwise you will be prompted to enter a value.

		Scope 1 - Application in an Environment: Specify --environment and --application

		Scope 2 - Environment at a Location: Specify --environment and --location

		Scope 3 - Environment: Specify --environment

		Scope 4 - Application: Specify --application

		Scope 5 - Global: Do not provide any additional arguments.

	constant delete
		Delete a constant and remove all configured values.

	constant list [--no-format|-1]
		List defined constants.

		The '--no-format' or '-1' argument outputs the constant list without any summary information.

	constant show [--application <name>] [--environment <name>] [--location <name>] [--system <name>]
		Show constant details and where it is currently defined.

		If one or more optional arguments are provided with valid values, just show the
		value of the constant in that scope (if it is defined).

	constant undefine [--application <name>] [--environment <name>] [--location <name>]
		Undefine (remove) a defined constant in the specified scope.

		Scope 1 - Application in an Environment: Specify --environment and --application

		Scope 2 - Environment at a Location: Specify --environment and --location

		Scope 3 - Environment: Specify --environment

		Scope 4 - Application: Specify --application

		Scope 5 - Global: Do not provide any additional arguments.

	constant update
		Update the constant name (rename) or description.

	environment application [<environment>] [--name <app_name>] --define [<application>]
		Define a constant in the application::environment scope (priority 1).

	environment application [<environment>] [--name <app_name>] --undefine [<application>]
		Remove the definition for a constant in the application::environment scope (priority 1).

	environment application [<environment>] [--name <app_name>] --list-constant [<application>]
		List defined constants in the application::environment scope (priority 1).

	environment constant --define [<environment>] [<constant>]
		Define a constant in the global environment scope (priority 3).

	environment constant --undefine [<environment>] [<constant>]
		Remove the definition for a constant in the global environment scope (priority 3).

	environment constant --list [<environment>] [<constant>]
		List defined constants in the global environment scope (priority 3).

	location [<name>] constant --define [<environment>] [<constant>]
		Define a constant in the environment::location scope (priority 2).

	location [<name>] constant --undefine [<environment>] [<constant>]
		Remove the definition for a constant in the environment::location scope (priority 2).

	location [<name>] constant --list [<environment>] [<constant>]
		List defined constants in the environment::location scope (priority 2).

EXAMPLES

RETURN CODE
	scs returns 0 on success and non-zero on error.

AUTHOR
	William Strucke <wstrucke@gmail.com>

COPYRIGHT
	Copyright © 2014 William Strucke. License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
	This is free software: you are free to change and redistribute it.  There is NO WARRANTY, to the extent permitted by law.

SEE ALSO
	$0 help
_EOF
}

# checks if a constant exists
#
function constant_exists {
  test $# -eq 1 || return 1
  # [FORMAT:constant]
  grep -qE "^$1," $CONF/constant || return 1
}

# show all constants
#
# optional:
#   --no-format
function constant_list {
  if [[ "$1" == "--no-format" || "$1" == "-1" ]]; then shift; constant_list_unformatted $@; return; fi
  local NUM A S
  NUM=$( wc -l ${CONF}/constant |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined constant${S}."
  test $NUM -eq 0 && return
  constant_list_unformatted |fold_list |perl -pe 's/^/   /'
}

function constant_list_unformatted {
  # [FORMAT:constant]
  awk 'BEGIN{FS=","}{print $1}' ${CONF}/constant |sort
}

# combine two sets of variables and values, only including the first instance of duplicates
#
# example on including duplicates from first file only:
#   join -a1 -a2 -t',' <(sort -t',' -k1 1) <(sort -t',' -k1 2) |perl -pe 's/^([^,]*,[^,]*),.*/\1/'
#
function constant_list_dedupe {
  if ! [ -f $1 ]; then cat $2; return; fi
  if ! [ -f $2 ]; then cat $1; return; fi
  join -a1 -a2 -t',' <(sort -t',' -k1,1 $1) <(sort -t',' -k1,1 $2) |perl -pe 's/^([^,]*,[^,]*),.*/\1/'
}

function constant_show {
  local C NAME DESC EnList AppList LocList i j SYSTEM APPLICATION ENVIRONMENT LOCATION Brief=0
  C="$( printf -- "$1" |tr 'A-Z' 'a-z' )" ; shift

  # get any other provided options
  while [ $# -gt 0 ]; do case $1 in
    --application) APPLICATION="$2"; shift;;
    --brief) Brief=1;;
    --environment) ENVIRONMENT="$2"; shift;;
    --location) LOCATION="$2"; shift;;
    --system) SYSTEM="$2"; shift;;
    *) usage;;
  esac; shift; done
  if [[ -n ${SYSTEM} || -n ${APPLICATION} || -n ${ENVIRONMENT} || -n ${LOCATION} ]]; then
    constant_show_value "$C" "$SYSTEM" "$APPLICATION" "$ENVIRONMENT" "$LOCATION" ; return ;
  fi
  # validate system name
  if ! [ -z "$PARSE" ]; then grep -qE "^$PARSE," ${CONF}/system || err "Unknown system"; fi
  constant_exists "$C" || err "Unknown constant"
  # [FORMAT:constant]
  IFS="," read -r NAME DESC <<< "$( grep -E "^$C," ${CONF}/constant )"
  printf -- "Name: $NAME\nDescription: $DESC\n"

  if [[ $Brief -eq 1 ]]; then return 0; fi
  printf -- 'Defined (priority 1..5):\n'

  # list environments and applications
  EnList=$( environment_list --no-format )
  AppList=$( application_list --no-format )
  LocList=$( location_list --no-format )

  printf -- '  1. Application @ Environment:\n'

  # 1. applications @ environment
  for i in $EnList; do
    for j in $AppList; do
      # [FORMAT:value/env/app]
      if [ -f "${CONF}/env/$i/by-app/$j" ]; then
        grep -qE "^$NAME," "${CONF}/env/$i/by-app/$j" && printf -- '      %s::%s = %s\n' $j $i "$( constant_show_value "$NAME" "" "$j" "$i" "" )"
      fi
    done
  done

  printf -- '\n  2. Environment @ Location:\n'

  # 2. environments @ location
  for i in $LocList; do
    for j in $EnList; do
      # [FORMAT:value/loc/constant]
      if [ -f "${CONF}/env/$j/by-loc/$i" ]; then
        grep -qE "^$NAME," "${CONF}/env/$j/by-loc/$i" && printf -- '      %s::%s = %s\n' $j $i "$( constant_show_value "$NAME" "" "" "$j" "$i" )"
      fi
    done
  done

  printf -- '\n  3. Environment:\n'

  # 3. environments (global)
  for i in $EnList; do
    # [FORMAT:value/env/constant]
    if [ -f "${CONF}/env/$i/constant" ]; then
      grep -qE "^$NAME," "${CONF}/env/$i/constant" && printf -- '      %s = %s\n' $i "$( constant_show_value "$NAME" "" "" "$i" "" )"
    fi
  done

  printf -- '\n  4. Application:\n'

  # 4. applications (global)
  for i in $AppList; do
    # [FORMAT:value/by-app/constant]
    if [ -f "${CONF}/value/by-app/$i" ]; then
      grep -qE "^$NAME," "${CONF}/value/by-app/$i" && printf -- '      %s = %s\n' $i "$( constant_show_value "$NAME" "" "$i" "" "" )"
    fi
  done

  printf -- '\n  5. Global:\n'

  # 5. global
  # [FORMAT:value/constant]
  test $( grep -cE "^$NAME," ${CONF}/value/constant ) -eq 1 && printf -- '      Defined = %s\n' "$( constant_show_value "$NAME" "" "" "" "" )" \
    || printf -- '      Not Defined\n'

  echo
}

function constant_show_value {
  local NAME SYS APP EN LOC
  NAME=$1
  SYS=$2
  APP=$3
  EN=$4
  LOC=$5
  if [[ -n ${SYS} ]]; then
    system_vars $SYS | grep -e "^constant.$NAME" | awk '{ print $2 }' ; return ;
  fi
  if [[ -n ${EN} && -n ${APP} ]]; then
    # [FORMAT:value/env/app]
    grep "^$NAME," $CONF/env/$EN/by-app/$APP 2> /dev/null | cut -f2 -d"," ; return ;
  fi
  if [[ -n ${EN} && -n ${LOC} ]]; then
    # [FORMAT:value/loc/constant]
    grep "^$NAME," $CONF/env/$EN/by-loc/$LOC 2> /dev/null | cut -f2 -d"," ; return ;
  fi
  if [[ -n ${EN} ]]; then
    # [FORMAT:value/env/constant]
    grep "^$NAME," $CONF/env/$EN/constant 2> /dev/null | cut -f2 -d"," ; return ;
  fi
  if [[ -n ${APP} ]]; then
    # [FORMAT:value/by-app/constant]
    grep "^$NAME," $CONF/value/by-app/$APP 2>/dev/null | cut -f2 -d"," ; return ;
  fi
  # [FORMAT:value/constant]
  grep "^$NAME," $CONF/value/constant | cut -f2 -d","
}

function constant_undefine {
  local NAME APP EN LOC FILE
  generic_choose constant "$1" NAME && shift

  while [ $# -gt 0 ]; do case $1 in
    --application) application_exists "$2" || err "Invalid application"; APP=$2;;
    --environment) environment_exists "$2" || err "Invalid environment"; EN=$2;;
    --location) location_exists "$2" || err "Invalid location"; LOC=$2;;
    *) usage;;
  esac; shift 2; done

  if [[ -n ${EN} && -n ${APP} ]]; then
    # [FORMAT:value/env/app]
    FILE="$CONF/env/$EN/by-app/$APP"
  elif [[ -n ${EN} && -n ${LOC} ]]; then
    # [FORMAT:value/loc/constant]
    FILE="$CONF/env/$EN/by-loc/$LOC"
  elif [[ -n ${EN} ]]; then
    # [FORMAT:value/env/constant]
    FILE="$CONF/env/$EN/constant"
  elif [[ -n ${APP} ]]; then
    # [FORMAT:value/by-app/constant]
    FILE="$CONF/value/by-app/$APP"
  elif [[ -z ${EN} && -z ${APP} && -z ${LOC} ]]; then
    # [FORMAT:value/constant]
    FILE="${CONF}/value/constant"
  else
    err
  fi

  test -f $FILE || return 0
  start_modify
  perl -i -ne "print unless /^$NAME,/" $FILE >/dev/null
  commit_file $FILE
}

function constant_update {
  start_modify
  generic_choose constant "$1" C && shift
  # [FORMAT:constant]
  IFS="," read -r NAME DESC <<< "$( grep -E "^$C," ${CONF}/constant )"
  get_input NAME "Name" --default "$NAME"
  # force lowercase for constants
  NAME=$( printf -- "$NAME" |tr 'A-Z' 'a-z' )
  get_input DESC "Description" --default "$DESC" --null --nc
  # [FORMAT:constant]
  perl -i -pe "s/^$C,.*/${NAME},${DESC}/" ${CONF}/constant
  commit_file constant
}


#Section: ENVIRONMENT
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
  # [FORMAT:value/env/app]
  touch $CONF/env/$ENV/by-app/$APP
  commit_file "${LOC}/${ENV}" $CONF/env/$ENV/by-app/$APP
}

function environment_application_define_constant {
  local APP C ENV="$1"; shift
  generic_choose application "$1" APP && shift
  generic_choose constant "$1" C && shift
  constant_define --environment "$ENV" --application "$APP" "$C" $@
}

function environment_application_undefine_constant {
  local APP C ENV="$1"; shift
  # get the requested application or abort
  generic_choose application "$1" APP && shift
  generic_choose constant "$1" C && shift
  constant_undefine --environment "$ENV" --application "$APP" "$C"
}

function environment_application_list_constant {
  ENV=$1; shift
  # get the requested application or abort
  generic_choose application "$1" APP && shift
  # [FORMAT:value/env/app]
  test -f $CONF/env/$ENV/by-app/$APP && NUM=$( wc -l $CONF/env/$ENV/by-app/$APP |awk '{print $1}' ) || NUM=0
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There $A $NUM defined constant$S for $ENV $APP."
  test $NUM -eq 0 && return
  awk 'BEGIN{FS=","}{print $1}' $CONF/env/$ENV/by-app/$APP |sort |perl -pe 's/^/   /'
}

function environment_application_byname_assign {
  start_modify
  ENV=$1; shift
  # get the requested application or abort
  generic_choose application "$1" APP && shift
  # select an available resource to assign
  generic_choose resource "$1" RES "^(cluster|ha)_ip,.*,not assigned," && shift
  # verify the resource is available for this purpose
  # [FORMAT:resource]
  grep -E "^[^,]*,${RES//,/}," $CONF/resource |grep -qE '^(cluster|ha)_ip,.*,not assigned,' || err "Error - invalid or unavailable resource."
  # get the requested location or abort
  generic_choose location "$1" LOC && shift
  test -f ${CONF}/${LOC}/${ENV} || err "Error - please create $ENV at $LOC first."
  grep -qE "^$APP$" ${CONF}/${LOC}/${ENV} || err "Error - please add $APP to $LOC $ENV before managing it."
  # assign resource, update index
  # [FORMAT:resource]
  IFS="," read -r TYPE VAL ASSIGN_TYPE ASSIGN_TO NAME DESC <<< "$( grep -E "^[^,]*,$RES," ${CONF}/resource )"
  # [FORMAT:resource]
  perl -i -pe "s/^[^,]*,${RES},.*/${TYPE},${VAL},application,${LOC}:${ENV}:${APP},${NAME},${DESC}/" ${CONF}/resource
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
  # [FORMAT:resource]
  grep -E "^[^,]*,${RES//,/}," $CONF/resource |grep -qE ",application,$LOC:$ENV:$APP," || err "Error - the provided resource is not assigned to this application."
  # confirm
  get_yn RL "Are you sure (y/n)?"
  if [ "$RL" != "y" ]; then return; fi
  # assign resource, update index
  # [FORMAT:resource]
  IFS="," read -r TYPE VAL ASSIGN_TYPE ASSIGN_TO NAME DESC <<< "$( grep -E "^[^,]*,$RES," ${CONF}/resource )"
  # [FORMAT:resource]
  perl -i -pe "s/^[^,]*,${RES},.*/${TYPE},${VAL},,not assigned,${NAME},${DESC}/" ${CONF}/resource
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
  sort ${CONF}/${LOC}/${ENV} |perl -pe 's/^/   /'
}

function environment_application_remove {
  start_modify
  ENV=$1; shift
  generic_choose application "$1" APP && shift
  # get the requested location or abort
  generic_choose location "$1" LOC && shift
  test -f ${CONF}/${LOC}/${ENV} && NUM=$( wc -l ${CONF}/${LOC}/${ENV} |awk '{print $1}' ) || NUM=0
  printf -- "Removing $APP from $LOC $ENV, deleting all configurations, files, resources, constants, et cetera...\n"
  get_yn RL "Are you sure (y/n)?"; test "$RL" != "y" && return
  # unassign the application
  perl -i -ne "print unless /^${APP}\$/" $CONF/$LOC/$ENV
  # !!FIXME!!
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
  local C ENV
  generic_choose environment "$1" ENV && shift
  generic_choose constant "$1" C && shift
  constant_define --environment "$ENV" "$C" $@
}

# undefine a constant for an environment
#
function environment_constant_undefine {
  local C ENV
  generic_choose environment "$1" ENV && shift
  generic_choose constant "$1" C && shift
  constant_undefine --environment "$ENV" "$C"
}

function environment_constant_list {
  generic_choose environment "$1" ENV && shift
  # [FORMAT:value/env/constant]
  NUM=$( wc -l ${CONF}/env/$ENV/constant |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined constant${S} for $ENV."
  test $NUM -eq 0 && return
  awk 'BEGIN{FS=","}{print $1}' ${CONF}/env/$ENV/constant |fold_list |perl -pe 's/^/   /'
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
  mkdir -p $CONF/template/patch/${NAME} $CONF/env/${NAME} >/dev/null 2>&1
  # [FORMAT:environment]
  printf -- "${NAME},${ALIAS},${DESC}\n" >>${CONF}/environment
  # [FORMAT:value/env/constant]
  touch $CONF/env/${NAME}/constant
  commit_file environment env/${NAME}/constant
}

function environment_delete {
  generic_delete environment $1 || return
  cd $CONF >/dev/null 2>&1 || return
  test -d env/$1 && git rm -r env/$1
  perl -i -ne "print unless /^$1,/" $CONF/hv-environment
  commit_file hv-environment
}

# checks if an environment is defined
#
function environment_exists {
  test $# -eq 1 || return 1
  # [FORMAT:environment]
  grep -qE "^$1," $CONF/environment || return 1
}

# general environment help
#
function environment_help { cat <<_EOF
NAME
	Environments

SYNOPSIS
	scs environment [create|delete|list|show|update] [<name>]
	scs environment application [<environment>] [--list] [<location>]
	scs environment application [<environment>] [--name <app_name>] [--add|--remove|--assign-resource|--unassign-resource|--list-resource] [<location>]
	scs environment application [<environment>] [--name <app_name>] [--define|--undefine|--list-constant] [<application>]
	scs environment constant [--define|--undefine|--list] [<environment>] [<constant>]
	scs file cat [<name>] [--environment <name>] [--vars <system>] [--silent] [--verbose]
	scs file edit [<name>] [--environment <name>]
	scs hypervisor <name> [--add-environment|--remove-environment]
	scs location [<name>] constant [--define|--undefine|--list] [<environment>] [<constant>]

DESCRIPTION
	Environments are a distinct collection of applications and related configurations.  They will usually share the same
	resources, such as databases or internal/external network connections.

	Environments are assigned to locations, after which applications can be assigned to the environment::location pair.

	Each defined file can have a single defined patch for each environment.

OPTIONS
	environment application [<environment>] --list [<location>]
		List applications assigned to an environment and location.

	environment application [<environment>] [--name <app_name>] --add [<location>]
		Assign an application to an environment at a location.

	environment application [<environment>] [--name <app_name>] --remove [<location>]
		Unassign an application from an environment at a location.

	environment application [<environment>] [--name <app_name>] --assign-resource [<location>]
		Assign a resource to an application in an environment at a location.

	environment application [<environment>] [--name <app_name>] --unassign-resource [<location>]
		Unassign a resource from an application in an environment at a location.

	environment application [<environment>] [--name <app_name>] --list-resource [<location>]
		List resources assigned to an application in an environment at a a location.

	environment application [<environment>] [--name <app_name>] --define [<application>]
		Define a constant for an application in an environment (priority 1).

	environment application [<environment>] [--name <app_name>] --undefine [<application>]
		Undefine a constant for an application in an environment (priority 1).

	environment application [<environment>] [--name <app_name>] --list-constant [<application>]
		List defined constants for an application in an environment (priority 1).

	environment constant --define [<environment>] [<constant>]
		Define a global environment constant (priority 3).

	environment constant --undefine [<environment>] [<constant>]
		Undefine a global environment constant (priority 3).

	environment constant --list [<environment>] [<constant>]
		List defined global environment constants (priority 3).

	environment create
		Create a new environment.

	environment delete
		Delete an existing environment and remove all defined constants, application links,
		and file diffs.  This action should not be performed without due consideration.

	environment list [--no-format|-1]
		List environments.

		The '--no-format' or '-1' argument outputs the list without any summary information.

	environment show
		Show environment details and linked locations.

	environment update
		Update or rename an environment.

	file cat [<name>] [--environment <name>] [--vars <system>] [--silent] [--verbose]
		Process and output a configuration file.  If an environment is provided, scs will
		assemble the variable values for that environment and replace them in the file.

		If a system is provided (with --vars) the variables for the system in the assigned
		environment will be substituted.

	file edit [<name>] [--environment <name>]
		Open the configuration file (or template) in vim.  Variables can be added or removed.
		See \`$0 help constant\` for more information on variable assignment and formatting.

		If an environment is provided the base file will be combined with any existing patch
		for the environment and the resultant file will be opened in vim where it can be edited
		normally.  When the editor is closed any changes will be compared to the original base
		template and a new patch will be generated for the environment.

	hypervisor <name> --add-environment
		Link an environment to a hypervisor.  Systems are assigned to exactly one environment
		and can only be deployed to hypervisors that are linked to the environment the system
		is in (unless forcibly overridden).

	hypervisor <name> --remove-environment
		Unlink an environment from a hypervisor.  This will not affect systems in the
		environment that are already deployed to the hypervisor, but will prevent new systems
		in the environment from being built on the hypervisor.

	location [<name>] constant --define [<environment>] [<constant>]
		Define a constant in the environment::location scope (priority 2).

	location [<name>] constant --undefine [<environment>] [<constant>]
		Remove the definition for a constant in the environment::location scope (priority 2).

	location [<name>] constant --list [<environment>] [<constant>]
		List defined constants in the environment::location scope (priority 2).

EXAMPLES

RETURN CODE
	scs returns 0 on success and non-zero on error.

AUTHOR
	William Strucke <wstrucke@gmail.com>

COPYRIGHT
	Copyright © 2014 William Strucke. License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
	This is free software: you are free to change and redistribute it.  There is NO WARRANTY, to the extent permitted by law.

SEE ALSO
	$0 help
_EOF
}

function environment_list {
  if [[ "$1" == "--no-format" || "$1" == "-1" ]]; then shift; environment_list_unformatted $@; return; fi
  NUM=$( wc -l ${CONF}/environment |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined environment${S}."
  test $NUM -eq 0 && return
  environment_list_unformatted |perl -pe 's/^/   /'
}

function environment_list_unformatted {
  awk 'BEGIN{FS=","}{print $1}' ${CONF}/environment |sort
}

function environment_show {
  environment_exists "$1" || err "Unknown or missing environment"
  local NAME ALIAS DESC BRIEF=0
  [ "$2" == "--brief" ] && BRIEF=1
  # [FORMAT:environment]
  IFS="," read -r NAME ALIAS DESC <<< "$( grep -E "^$1," ${CONF}/environment )"
  printf -- "Name: $NAME\nAlias: $ALIAS\nDescription: $DESC\n"
  test $BRIEF -eq 1 && return
  # also show installed locations
  NUM=$( find $CONF -name $NAME -type f |grep -vE '(env|template|value)' |wc -l |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo -e "\nThere ${A} ${NUM} linked location${S}."
  if [ $NUM -gt 0 ]; then
    find $CONF -name $NAME -type f |grep -vE '(env|template|value)' |perl -pe 's%'$CONF'/(.{3}).*%   \1%'
  fi
  printf -- '\n'
}

function environment_update {
  start_modify
  generic_choose environment "$1" C && shift
  # [FORMAT:environment]
  IFS="," read -r NAME ALIAS DESC <<< "$( grep -E "^$C," ${CONF}/environment )"
  get_input NAME "Name" --default "$NAME"
  get_input ALIAS "Alias (One Letter, Unique)" --default "$ALIAS"
  get_input DESC "Description" --default "$DESC" --null --nc
  # force uppercase for site alias
  ALIAS=$( printf -- "$ALIAS" | tr 'a-z' 'A-Z' )
  # [FORMAT:environment]
  perl -i -pe "s/^$C,.*/${NAME},${ALIAS},${DESC}/" ${CONF}/environment
  # handle rename
  if [ "$NAME" != "$C" ]; then
    pushd ${CONF} >/dev/null 2>&1
    test -d template/patch/$C && git mv template/patch/$C template/patch/$NAME >/dev/null 2>&1
    test -d env/$C && git mv env/$C env/$NAME >/dev/null 2>&1
    # [FORMAT:location]
    for L in $( awk 'BEGIN{FS=","}{print $1}' ${CONF}/location ); do
      test -d $L/$C && git mv $L/$C $L/$NAME >/dev/null 2>&1
    done
    popd >/dev/null 2>&1
  fi
  commit_file environment
}


#Section: FILE
 ####### ### #       #######
 #        #  #       #
 #        #  #       #
 #####    #  #       #####
 #        #  #       #
 #        #  #       #
 #       ### ####### #######

# output a (text) file contents to stdout
#
# cat [<name>] [--environment <name>] [--silent] [--system <system>] [--system-vars /path/to/file] [--verbose]
#
function file_cat {
  # get file name to show
  generic_choose file "$1" C && shift
  # set defaults
  local EN="" PARSE="" SILENT=0 VERBOSE=0 NAME PTH TYPE OWNER GROUP OCTAL TARGET DESC \
        SystemVars=""
  # get any other provided options
  while [ $# -gt 0 ]; do case $1 in
    --environment) EN="$2"; shift;;
    --silent) SILENT=1;;
    --system) PARSE="$2"; shift;;
    --system-vars) SystemVars="$2"; shift;;
    --verbose) VERBOSE=1;;
    *) usage;;
  esac; shift; done
  # validate system name
  if [[ -n $PARSE ]]; then system_exists $PARSE || err "Unknown system"; fi
  # load file data
  # [FORMAT:file]
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
  if [[ -z $SystemVars && -n $PARSE ]]; then
    # generate the system variables
    system_vars $PARSE >$TMP/systemvars.$$
    SystemVars=$TMP/systemvars.$$
  fi
  if [[ -n $SystemVars && -f $SystemVars ]]; then
    # process template variables
    parse_template $TMP/$C $SystemVars $SILENT $VERBOSE
    if [ $? -ne 0 ]; then test $SILENT -ne 1 && echo "Error parsing template" >&2; return 1; fi
  fi
  # output the file and remove it
  cat $TMP/$C
  rm -f $TMP/$C
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
  file_exists "$NAME" && err "File already defined."
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
  # [FORMAT:file]
  printf -- "${NAME},${PTH},${TYPE},${OWNER},${GROUP},${OCTAL},${TARGET},${DESC}\n" >>${CONF}/file
  # create base file
  if [ "$TYPE" == "file" ]; then
    pushd $CONF >/dev/null 2>&1 || err "Unable to change to '${CONF}' directory"
    test -d template || mkdir template >/dev/null 2>&1
    touch template/${NAME}
    git add template/${NAME} >/dev/null 2>&1
    #git commit -m"template created by ${USERNAME}" file template/${NAME} >/dev/null 2>&1 || err "Error committing new template to repository"
    popd >/dev/null 2>&1
  elif [ "$TYPE" == "binary" ]; then
    printf -- "\nPlease copy the binary file to: $CONF/env/<environment>/binary/$NAME\n"
    printf -- "\nAfter the copy is complete, add to git manually in our repo ($CONF)\n"
  else
    commit_file file
  fi
}

function file_delete {
  start_modify
  generic_choose file "$1" C && shift
  printf -- "WARNING: This will remove any templates and stored configurations in all environments for this file!\n"
  get_yn RL "Are you sure (y/n)?"
  if [ "$RL" == "y" ]; then
    # [FORMAT:file]
    perl -i -ne "print unless /^$C,/" ${CONF}/file
    # [FORMAT:file-map]
    perl -i -ne "print unless /^$C,/" ${CONF}/file-map
    pushd $CONF >/dev/null 2>&1
    find template/ -type f -name $C -exec git rm -f {} \; >/dev/null 2>&1
    git add file file-map >/dev/null 2>&1
    #git commit -m"template removed by ${USERNAME}" >/dev/null 2>&1 || err "Error committing removal to repository"
    find env/ -type f -name $C -exec rm -f {} \; >/dev/null 2>&1
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
  # [FORMAT:file]
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
    $EditProgram $TMP/$C
    wait
    # do nothing further if there were no changes made
    if [ $( md5s $TMP/$C{.ORIG,} |uniq |wc -l |awk '{print $1}' ) -eq 1 ]; then
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
    echo "Wrote $( wc -c $CONF/template/$ENV/$C |awk '{print $1}' ) bytes to $ENV/$C."
    # commit
    pushd $CONF >/dev/null 2>&1
    git add template/$ENV/$C >/dev/null 2>&1
    popd >/dev/null 2>&1
    commit_file template/$ENV/$C
  else
    # create a copy of the template to edit
    cat $CONF/template/$C >/tmp/app-config.$$
    $EditProgram /tmp/app-config.$$
    wait
    # prompt for verification
    echo -e "Please review the change:\n"
    diff -c $CONF/template/$C /tmp/app-config.$$
    echo
    get_yn RL "Proceed with change (y/n)?"
    if [ "$RL" != "y" ]; then rm -f /tmp/app-config.$$; return; fi
    # apply patches to the template for each environment with a patch and verify the apply successfully
    echo "Validating template instances..."
    NEWPATCHES=(); NEWENVIRON=()
    pushd $CONF/template >/dev/null 2>&1
    for E in $( find . -mindepth 2 -type f -name $C -print0 |xargs -0 -n1 dirname 2>/dev/null |perl -pe 's/^\.\///' ); do
      echo -n "${E}... "
      cat /tmp/app-config.$$ >/tmp/app-config.$$.1
      patch -p0 /tmp/app-config.$$.1 <$E/$C >/dev/null 2>&1
      if [ $? -ne 0 ]; then
        echo -e "FAILED\n\nThis patch will not apply successfully to $E."
        get_yn RL "Would you like to try to resolve the patch manually (y/n)?"
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
        echo; get_yn RL "Proceed with change (y/n)?"
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
    #pushd ${CONF} >/dev/null 2>&1
    #if [ $( git status -s template/${C} |wc -l |awk '{print $1}' ) -ne 0 ]; then
    #  git commit -m"template updated by ${USERNAME}" template/${C} >/dev/null 2>&1 || err "Error committing template change"
    #fi
    #popd >/dev/null 2>&1
  fi
}
function file_edit_help {
  echo "HELP NOT AVAILABLE -- YOU ARE ON YOUR OWN"
}

# checks if a file is defined
#
function file_exists {
  test $# -eq 1 || return 1
  # [FORMAT:file]
  grep -qE "^$1," $CONF/file || return 1
}

# general file help
#
function file_help { cat <<_EOF
NAME
	Files (templates or file system resources)

SYNOPSIS
	scs application file [--add|--remove|--list]
	scs file [create|delete|list|show|update] [<name>]
	scs file cat [<name>] [--environment <name>] [--vars <system>] [--silent] [--verbose]
	scs file edit [<name>] [--environment <name>]

DESCRIPTION
	Managed configuration files come in one of seven types and are assembled any time a system
	audit or configuration deployment is requested.

	Files can optionally contain constants or resources and can optionally have a 'patch' for any environment,
	allowing tremendous flexibility in construction and deployment between a multitude of environments.

	File types include:

		file          a regular text file
		symlink       a symbolic link
		binary        a non-text file
		copy          a regular file that is not stored here. it will be copied by this application from
		                another location when it is deployed.  when auditing a remote system files of type
		                'copy' will only be audited for permissions and existence.
		delete        ensure a file or directory DOES NOT EXIST on the target system.
		download      a regular file that is not stored here. it will be retrieved by the remote system
		                when it is deployed.  when auditing a remote system files of type 'download' will
		                only be audited for permissions and existence.
		directory     a directory (useful for enforcing permissions)

	When a file is processed scs looks for a standard template notation for constants and resource references,
	using a bracket, percent sign, and space before and after the variable.

	A variable is notated with the variable type as a prefix followed by the unique name.  There are
	currently three types:
		resource
			See \`$0 help resource\` for more information.
		constant
			These are normal variables.  See \`$) help constant\` for more information.
		system
			See \`$0 help system\` for more information.

	Example notation:
		{% resource.name %}
		{% constant.name %}
		{% system.name %}, {% system.ip %}, {% system.location %}, {% system.environment %}

OPTIONS
	application file --add
		Link a file to an application.  The same file can be linked to many applications.

	application file --remove
		Unlink a file from an application.  This does not otherwise alter the file.

	application file --list
		List files linked to an application.

	file cat [<name>] [--environment <name>] [--silent] [--system <system>] [--system-vars /path/to/variables] [--verbose]
		Process and output the contents of a file.

		If an environment is provided any patch for that environment will be applied.

		If a system is provided, variables will be compiled for that system and replaced in the
		file where they appear, as they would be done when the system was deployed.

		Silent mode will hide errors (the file will still be displayed).

		Verbose mode causes every undefined variable to be explicitely output.

	file create
		Create a file definition.

	file delete
		Remove a file, it's contents, and all environment patches.

	file edit [<name>] [--environment <name>]
		Open the configuration file (or template) in vim.  Variables can be added or removed.
		See \`$0 help constant\` for more information on variable assignment and formatting.

		If an environment is provided the base file will be combined with any existing patch
		for the environment and the resultant file will be opened in vim where it can be edited
		normally.  When the editor is closed any changes will be compared to the original base
		template and a new patch will be generated for the environment.

	file list
		List defined files and their deployment path.

	file show
		Output configuration summary for the file.

	file update
		Update or rename the file.  A rename operation will properly rename patches and update
		references to the file throughout scs.

EXAMPLES

RETURN CODE
	scs returns 0 on success and non-zero on error.

AUTHOR
	William Strucke <wstrucke@gmail.com>

COPYRIGHT
	Copyright © 2014 William Strucke. License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
	This is free software: you are free to change and redistribute it.  There is NO WARRANTY, to the extent permitted by law.

SEE ALSO
	$0 help
_EOF
}

function file_list {
  NUM=$( wc -l ${CONF}/file |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined file${S}."
  test $NUM -eq 0 && return
  # [FORMAT:file]
  awk 'BEGIN{FS=","}{print $1,$2}' ${CONF}/file |sort |column -t |perl -pe 's/^/   /'
}

# show file details
#
# storage format (brief):
#   name,path,type,owner,group,octal,target,description
#
function file_show {
  file_exists "$1" || err "Unknown or missing file name"
  # [FORMAT:file]
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
    [ "$TYPE" == "file" ] && printf -- "\nSize: $( file_size $CONF/template/$NAME ) bytes"
#    [ "$TYPE" == "binary" ] && printf -- "\nSize: $( file_size $CONF/env/.../binary/$NAME ) bytes"
  fi
  printf -- '\n'

  if [ "$TYPE" == "binary" ]; then
    printf -- "Local Path:\n"
    for F in $( find $CONF/env -name "$NAME" -print ); do
      printf -- '  %s (%s bytes)' "$F" "$( file_size $F )"
      if [[ "$( file -b $F )" == "ASCII text" && -n "$( head -n1 $F |grep -- "-----BEGIN CERTIFICATE-----" )" ]]; then
        # this appears to be an ssl certificate
        printf -- '\n    SSL Certificate Data: '
        openssl x509 -noout -modulus -in $F |openssl md5 |cut -d' ' -f2 |tr '\n' ' '
        openssl x509 -in $F -noout -fingerprint
      elif [[ "$( file -b $F )" == "ASCII text" && -n "$( head -n1 $F |grep -- "-----BEGIN RSA PRIVATE KEY-----" )" ]]; then
        # this appears to be a private key
        printf -- '\n    SSL Certificate Data: '
        openssl rsa -noout -modulus -in $F |openssl md5 |cut -d' ' -f2
      else
        printf -- '\n'
      fi
    done
  fi

  printf -- 'Linked Applications:\n'
  if [ "$( grep -c "^$1," ${CONF}/file-map )" -eq 0 ]; then
    printf -- '  None\n'
  else
    grep "^$1," ${CONF}/file-map |cut -d, -f2 |sort |perl -pe 's/^/  /'
  fi
}

# return the file size in bytes
# implemented in this fashion to enable multi-platform compatibility
#
function file_size {
  test -f "$1" || return
  echo $( wc -c $1 |awk '{print $1}' )
}

function file_update {
  start_modify
  generic_choose file "$1" C && shift
  # [FORMAT:file]
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
      for DIR in $( find template/ -type f -name $C -exec dirname {} \\; ); do
        git mv $DIR/$C $DIR/$NAME >/dev/null 2>&1
      done
    elif [ "$TYPE" == "binary" ]; then
      for DIR in $( find env/ -type f -name $C -exec dirname {} \\; ); do
        git mv $DIR/$C $DIR/$NAME >/dev/null 2>&1
      done
    fi
    popd >/dev/null 2>&1
    # update map
    # [FORMAT:file-map]
    perl -i -pe "s%^$C,(.*)%${NAME},\1%" ${CONF}/file-map
  fi
  # [FORMAT:file]
  perl -i -pe "s%^$C,.*%${NAME},${PTH},${TYPE},${OWNER},${GROUP},${OCTAL},${TARGET},${DESC}%" $CONF/file
  # if type changed from "file" to something else, delete the template
  if [[ "$T" == "file" && "$TYPE" != "file" ]]; then
    pushd $CONF >/dev/null 2>&1
    find template/ -type f -name $C -exec git rm {} \; >/dev/null 2>&1
    #git commit -m"template removed by ${USERNAME}" >/dev/null 2>&1
    popd >/dev/null 2>&1
  fi
  commit_file file file-map
}


#Section: LOCATION
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
  test $( printf -- "$CODE" |wc -c |awk '{print $1}' ) -eq 3 || err "Error - the location code must be exactly three characters."
  get_input NAME "Name" --nc
  get_input DESC "Description" --nc --null
  # validate unique name
  grep -qE "^$CODE," $CONF/location && err "Location already defined."
  # add
  # [FORMAT:location]
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
  #git commit -m"${USERNAME} added $ENV to $LOC" ${LOC}/$ENV >/dev/null 2>&1 || err "Error committing change to the repository"
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
  local C ENV="$2" LOC="$1"; shift 2
  generic_choose constant "$1" C && shift
  constant_define --environment "$ENV" --location "$LOC" "$C" $@
}

function location_environment_constant_undefine {
  local C ENV="$2" LOC="$1"; shift 2
  generic_choose constant "$1" C && shift
  constant_undefine --environment "$ENV" --location "$LOC" "$C"
}

function location_environment_constant_list {
  LOC="$1"; ENV="$2"; shift 2
  # [FORMAT:value/loc/constant]
  test -f $CONF/env/$ENV/by-loc/$LOC && NUM=$( wc -l $CONF/env/$ENV/by-loc/$LOC |awk '{print $1}' ) || NUM=0
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined constant${S} for $LOC $ENV."
  test $NUM -eq 0 && return
  awk 'BEGIN{FS=","}{print $1}' $CONF/env/$ENV/by-loc/$LOC |sort |perl -pe 's/^/   /'
}

# list environments at a location
#
# required:
#  $1 location
#
function location_environment_list {
  test -d ${CONF}/$1 && NUM=$( find ${CONF}/$1/ -type f |perl -pe 's%'"${CONF}/$1"'/%%' |grep -vE '^(\.|template|network|$)' |wc -l |awk '{print $1}' ) || NUM=0
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined environment${S} at $1."
  test $NUM -eq 0 && return
  find ${CONF}/$1/ -type f |perl -pe 's%'"${CONF}/$1"'/%%' |grep -vE '^(\.|template|network|$)' |sort |perl -pe 's/^/   /'
}

function location_environment_unassign {
  start_modify
  LOC=$1; shift
  # get the requested environment or abort
  generic_choose environment "$1" ENV && shift
  printf -- "Removing $ENV from location $LOC, deleting all configurations, files, resources, constants, et cetera...\n"
  get_yn RL "Are you sure (y/n)?"; test "$RL" != "y" && return
  # unassign the environment
  pushd $CONF >/dev/null 2>&1
  test -f ${LOC}/$ENV && git rm -rf ${LOC}/$ENV >/dev/null 2>&1
  #git commit -m"${USERNAME} removed $ENV from $LOC" >/dev/null 2>&1 || err "Error committing change to the repository"
  popd >/dev/null 2>&1
}

# checks if a location is defined
#
function location_exists {
  test $# -eq 1 || return 1
  # [FORMAT:location]
  grep -qE "^$1," $CONF/location || return 1
}

# general location help
#
function location_help { cat <<_EOF
NAME

SYNOPSIS
	scs location [<name>] [--assign|--unassign|--list]
	scs location [<name>] constant [--define|--undefine|--list] [<environment>] [<constant>]

DESCRIPTION

OPTIONS

EXAMPLES

RETURN CODE
	scs returns 0 on success and non-zero on error.

AUTHOR
	William Strucke <wstrucke@gmail.com>

COPYRIGHT
	Copyright © 2014 William Strucke. License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
	This is free software: you are free to change and redistribute it.  There is NO WARRANTY, to the extent permitted by law.

SEE ALSO
	$0 help
_EOF
}

function location_list {
  if [[ "$1" == "--no-format" || "$1" == "-1" ]]; then shift; location_list_unformatted $@; return; fi
  NUM=$( wc -l ${CONF}/location |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined location${S}."
  test $NUM -eq 0 && return
  location_list_unformatted |perl -pe 's/^/   /'
}

function location_list_unformatted {
  awk 'BEGIN{FS=","}{print $1}' ${CONF}/location |sort
}

function location_show {
  location_exists "$1" || err "Unknown or missing location name"
  # [FORMAT:location]
  IFS="," read -r CODE NAME DESC <<< "$( grep -E "^$1," ${CONF}/location )"
  printf -- "Code: $CODE\nName: $NAME\nDescription: $DESC\n"
}

function location_update {
  start_modify
  generic_choose location "$1" C && shift
  # [FORMAT:location]
  IFS="," read -r CODE NAME DESC <<< "$( grep -E "^$C," ${CONF}/location )"
  get_input CODE "Location Code (three characters)" --default "$CODE"
  test $( printf -- "$CODE" |wc -c |awk '{print $1}' ) -eq 3 || err "Error - the location code must be exactly three characters."
  get_input NAME "Name" --nc --default "$NAME"
  get_input DESC "Description" --nc --null --default "$DESC"
  # [FORMAT:location]
  perl -i -pe "s/^$C,.*/${CODE},${NAME},${DESC}/" ${CONF}/location
  # handle rename
  if [ "$CODE" != "$C" ]; then
    pushd $CONF >/dev/null 2>&1
    test -d $C && git mv $C $CODE >/dev/null 2>&1
    perl -i -pe "s/^$C,/${CODE},/" network
    popd >/dev/null 2>&1
  fi
  commit_file location
}


#Section: NETWORK
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
  if [ "$1" == "ip" ]; then network_by_ip ${@:2}; return 0; fi
  network_exists "$1" || err "Missing network or invalid format. Please ensure you are entering 'location-zone-alias'."
  # function
  case "$2" in
    ip) network_ip $1 ${@:3};;
    ipam) network_ipam $1 ${@:3};;
    *) network_show $1;;
  esac
}

function network_by_ip {
  case $1 in
    --locate) network_ip_locate ${@:2};;
    *) echo "Usage: $0 network ip --locate a.b.c.d";;
  esac
}

# create a network
#
# network:
#    location,zone,alias,network,mask,cidr,gateway_ip,static_routes,dns_ip,vlan,description,repo_address,repo_fs_path,repo_path_url,build,default-build,ntp_ip
#
function network_create {
  local LOC ZONE ALIAS DESC BITS GW HAS_ROUTES DNS DHCP NTP BUILD DEFAULT_BUILD REPO_ADDR REPO_PATH REPO_URL
  start_modify
  # get user input and validate
  get_input LOC "Location Code" --options "$( location_list_unformatted |replace )"
  get_input ZONE "Network Zone" --options core,edge
  get_input ALIAS "Site Alias"
  # validate unique name
  network_exists "$LOC-$ZONE-$ALIAS" && err "Network already defined."
  get_input DESC "Description" --nc --null
  while ! $(valid_ip "$NET"); do get_input NET "Network"; done
  get_input BITS "CIDR Mask (Bits)" --regex '^[0-9]+$'
  while ! $(valid_mask "$MASK"); do get_input MASK "Subnet Mask" --default $(cdr2mask $BITS); done
  get_input GW "Gateway Address" --null
  get_yn HAS_ROUTES "Does this network have host static routes (y/n)?" && network_edit_routes $NET
  get_input DNS "DNS Server Address" --null
  get_input DHCP "DHCP Server Address" --null
  get_input NTP "NTP Server Address" --null
  get_input VLAN "VLAN Tag/Number" --null
  get_yn BUILD "Use network for system builds (y/n)?"
  if [ "$BUILD" == "y" ]; then
    get_yn DEFAULT_BUILD "Should this be the *default* build network at the location (y/n)?"
    # when adding a new default build network make sure we prompt if another exists, since it will be replaced
    # [FORMAT:network]
    if [[ "$DEFAULT_BUILD" == "y" && $( grep -E ',y$' ${CONF}/${LOC}/network |grep -vE "^${ZONE},${ALIAS}," |wc -l |awk '{print $1}' ) -ne 0 ]]; then
      get_yn RL "WARNING: Another default build network exists at this site. Are you sure you want to replace it (y/n)?"
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
  #   --format: location,zone,alias,network,mask,cidr,gateway_ip,dns_ip,vlan,description,repo_address,repo_fs_path,repo_path_url,build,default-build,ntp_ip,dhcp_ip\n
  # [FORMAT:network]
  printf -- "${LOC},${ZONE},${ALIAS},${NET},${MASK},${BITS},${GW},${HAS_ROUTES},${DNS},${VLAN},${DESC},${REPO_ADDR},${REPO_PATH},${REPO_URL},${BUILD},${DEFAULT_BUILD},${NTP},${DHCP}\n" >>$CONF/network
  test ! -d ${CONF}/${LOC} && mkdir ${CONF}/${LOC}
  #   --format: zone,alias,network/cidr,build,default-build\n
  # [FORMAT:location/network]
  if [[ "$DEFAULT_BUILD" == "y" && $( grep -E ',y$' ${CONF}/${LOC}/network |grep -vE "^${ZONE},${ALIAS}," |wc -l |awk '{print $1}' ) -gt 0 ]]; then
    # get the current default network (if any) and update it
    # [FORMAT:location/network]
    IFS="," read -r Z A DISC <<< "$( grep -E ',y$' ${CONF}/${LOC}/network |grep -vE "^${ZONE},${ALIAS}," )"
    # [FORMAT:network]
    perl -i -pe "s%^(${LOC},${Z},${A},.*),y,y(,[^,]*){2}\$%\1,y,n\2%" ${CONF}/network
    # [FORMAT:network]
    perl -i -pe 's/,y$/,n/' ${CONF}/${LOC}/network
  fi
  # [FORMAT:location/network]
  printf -- "${ZONE},${ALIAS},${NET}/${BITS},${BUILD},${DEFAULT_BUILD}\n" >>${CONF}/${LOC}/network
  commit_file network ${CONF}/${LOC}/network
  if [[ "$HAS_ROUTES" == "y" && -f $TMP/${NET}-routes ]]; then cat $TMP/${NET}-routes >${CONF}/net/${NET}-routes; commit_file ${CONF}/net/${NET}-routes; fi
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
  network_exists "$C" || err "Missing network or invalid format. Please ensure you are entering 'location-zone-alias'."
  get_yn RL "Are you sure (y/n)?"
  if [ "$RL" == "y" ]; then
    # [FORMAT:network]
    IFS="," read -r LOC ZONE ALIAS NET DISC <<< "$( grep -E "^${C//-/,}," ${CONF}/network )"
    perl -i -ne "print unless /^${C//-/,},/" ${CONF}/network
    perl -i -ne "print unless /^${ZONE},${ALIAS},/" ${CONF}/${LOC}/network
    perl -i -ne "print unless /^${C//-/,},/" ${CONF}/hv-network
    if [ -f ${CONF}/net/${NET} ]; then delete_file net/${NET}; fi
    if [ -f ${CONF}/net/${NET}-routes ]; then delete_file net/${NET}-routes; fi
  fi
  commit_file network ${CONF}/${LOC}/network ${CONF}/hv-network
}

# open network route editor
#
# net/a.b.c.0-routes:
#    device net network netmask netmask gw gateway
#
# creates 'a.b.c.0-routes' in TMP.  the calling function should put it in place and commit the change
#
function network_edit_routes {
  if [ $# -ne 1 ]; then err "A network is required"; fi
  start_modify
  # create the working file
  mkdir $TMP && touch $TMP/${1}-routes
  test -f ${CONF}/net/${1}-routes && cat ${CONF}/net/${1}-routes >$TMP/${1}-routes
  # clear the screen
  tput smcup
  # engage editor
  local COL=$(tput cols) OPT LINE DEVICE NET NETMASK GATEWAY I V
  while [ "$OPT" != 'q' ]; do
    clear; I=0
    printf -- '%s%*s%s\n' 'SCS Route Editor' $((COL-16)) "$1"
    printf -- '%*s\n' $COL '' | tr ' ' -
    if ! [ -s $TMP/${1}-routes ]; then
      echo '  ** No routes exist **'
    else
      local IFS=$'\n'
      # [FORMAT:net/routes]
      while read LINE; do
        I=$(($I+1))
        printf -- '  %s: %s\n' $I $LINE
      done < $TMP/${1}-routes
    fi
    printf -- '\n\n'
    read -p 'e# to edit, d# to remove, n to add, v to edit in vim, w to save/quit, or a to abort (#=line number): ' OPT
    case ${OPT:0:1} in
      n)
	get_input DEVICE "  Device" --default "any" --nc
	get_input NET "  Target Network"
        get_input NETMASK "  Target Network Mask"
	get_input GATEWAY "  Gateway"
        # [FORMAT:net/routes]
        printf -- '%s net %s netmask %s gw %s\n' $DEVICE $NET $NETMASK $GATEWAY >>$TMP/${1}-routes
        ;;
      v)
        vim $TMP/${1}-routes
        ;;
      w)
	OPT='q'
	;;
      a)
	rm -f $TMP/${1}-routes
	OPT='q'
	;;
      e)
	V=${OPT:1}
#	if [ "$V" != "$( printf -- '$V' |perl -pe 's/[^0-9]*//g' )" ]; then echo "validation error 1: '$V' is not '$( printf -- '$V' |perl -pe 's/[^0-9]*//g' )'"; sleep 1; continue; fi
	if [[ $V -le 0 || $V -gt $I ]]; then echo "validation error 2"; sleep 1; continue; fi
        # [FORMAT:net/routes]
	IFS=" " read -r DEVICE NET NETMASK GATEWAY <<<$(awk '{print $1,$3,$5,$7}' $TMP/${1}-routes |head -n$V |tail -n1)
	get_input DEVICE "  Device" --default "$DEVICE" --nc
	get_input NET "  Target Network" --default "$NET"
        get_input NETMASK "  Target Network Mask" --default "$NETMASK"
	get_input GATEWAY "  Gateway" --default "$GATEWAY"
        perl -i -ne "print if \$. != $V" $TMP/${1}-routes
        # [FORMAT:net/routes]
        printf -- '%s net %s netmask %s gw %s\n' $DEVICE $NET $NETMASK $GATEWAY >>$TMP/${1}-routes
	;;
      d)
	V=${OPT:1}
#	if [ "$V" != "$( printf -- '$V' |perl -pe 's/[^0-9]*//g' )" ]; then echo "validation error 1: '$V' is not '$( printf -- '$V' |perl -pe 's/[^0-9]*//g' )'"; sleep 1; continue; fi
	if [[ $V -le 0 || $V -gt $I ]]; then echo "validation error 2"; sleep 1; continue; fi
        perl -i -ne "print if \$. != $V" $TMP/${1}-routes
	;;
    esac
  done
  # restore the screen
  tput rmcup
  return 0
}

# checks if a network is defined
#
function network_exists {
  test $# -eq 1 || return 1
  if [[ $( printf -- "$1" |perl -pe 's/[^-]*//g' |wc -c |awk '{print $1}' ) -ne 2 ]]; then return 1; fi
  # [FORMAT:network]
  grep -qE "^${1//-/,}," $CONF/network || return 1
}

# general network help
#
function network_help { cat <<_EOF
NAME

SYNOPSIS
	scs network ip [--locate a.b.c.d]
	scs network <name> ip [--assign|--check|--unassign|--list|--list-available|--list-assigned|--scan]
	scs network <name> ipam [--add-range|--remove-range|--reserve-range|--free-range]

DESCRIPTION

OPTIONS

EXAMPLES

RETURN CODE
	scs returns 0 on success and non-zero on error.

AUTHOR
	William Strucke <wstrucke@gmail.com>

COPYRIGHT
	Copyright © 2014 William Strucke. License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
	This is free software: you are free to change and redistribute it.  There is NO WARRANTY, to the extent permitted by law.

SEE ALSO
	$0 help
_EOF
}

# <name> ip [--assign|--unassign|--list|--list-available|--list-assigned]
function network_ip {
  network_exists "$1" || err "Missing network or invalid format. Please ensure you are entering 'location-zone-alias'."
  # function
  case "$2" in
    --assign) network_ip_assign ${@:3};;
    --check) network_ip_check $3;;
    --unassign) network_ip_unassign ${@:3};;
    --list) network_ip_list $1 ${@:3};;
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
#   --force	assign the address and ignore checks
#   --comment	prompt for a comment (unfortantly there is no easy way to pass in a string)
#
# net/a.b.c.0
#   --format: octal_ip,cidr_ip,reserved,dhcp,hostname,host_interface,comment,interface_comment,owner\n
#
function network_ip_assign {
  if [ $# -lt 2 ]; then network_ip_assign_help >&2; return 1; fi

  local RET FILENAME FORCE=0 ASSN IP Hostname Comment

  while [ $# -gt 0 ]; do case $1 in
    --comment) get_input Comment "Comment" --nc;;
    --force) FORCE=1;;
    *)
      if [ -z "$IP" ]; then IP="$1";
      elif [ -z "$Hostname" ]; then Hostname="$1";
      else network_ip_assign_help >&2; return 1
      fi
      ;;
  esac; shift; done

  valid_ip $IP || err "Invalid IP."
  FILENAME=$( get_network $IP 24 )

  # validate address
  grep -q "^$( ip2dec $IP )," ${CONF}/net/${FILENAME} 2>/dev/null || err "The requested IP is not available."
  [[ "$( grep "^$( ip2dec $IP )," ${CONF}/net/${FILENAME} |awk 'BEGIN{FS=","}{print $3}' )" == "y" && $FORCE -eq 0 ]] && err "The requested IP is reserved."
  ASSN="$( grep "^$( ip2dec $IP )," ${CONF}/net/${FILENAME} |awk 'BEGIN{FS=","}{print $5}' )"
  if [[ "$ASSN" != "" && "$ASSN" != "$Hostname" && $FORCE -eq 0 ]]; then err "The requested IP is already assigned."; fi

  start_modify

  # load the ip data
  # [FORMAT:net/network]: octal_ip,cidr_ip,reserved,dhcp,hostname,host_interface,comment,interface_comment,owner\n
  IFS="," read -r A B C D E F G H I <<<"$( grep "^$( ip2dec $IP )," ${CONF}/net/${FILENAME} )"

  # check if the ip is in use (last ditch effort)
  if [[ $FORCE -eq 0 && "$ASSN" == "" && $( exit_status network_ip_check $IP ) -ne 0 ]]; then
    # mark the address as reserved
    # [FORMAT:net/network]
    perl -i -pe "s/^$( ip2dec $IP ),.*/$A,$B,y,$D,$E,$F,auto-reserved: address in use,$H,$I/" ${CONF}/net/${FILENAME}
    echo "The requested IP is in use."
    RET=1
  else
    # assign
    # [FORMAT:net/network]
    perl -i -pe "my \$str = '$A,$B,n,$D,$Hostname,,${Comment//,/-},,$USERNAME'; s/^$( ip2dec $IP ),.*/\$str/" ${CONF}/net/${FILENAME}
    RET=0
  fi

  # commit changes
  git add ${CONF}/net/${FILENAME}
  commit_file ${CONF}/net/${FILENAME}
  return $RET
}
function network_ip_assign_help { cat <<_EOF
Usage: $0 network <name> ip --assign <a.b.c.d> <hostname> [--force] [--comment <string>]
_EOF
}

# try to determine whether or not an IP is in use
#
# required:
#   $1	ip to check
#
# optional:
#   $2	hostname to match against
#
function network_ip_check {
  local P
  valid_ip "$1" || return 1
  # tcp port 22 (ssh), 80 (http), 443 (https), and 8080 (http-alt)
  check_host_alive $1 && return 1
  for P in $IP_Check_Ports; do check_host_alive $1 $P 1 && return 1; done
  # icmp/ping
  if [ $( ping -c4 -n -s8 -W4 -q $1 |grep -E '0 (packets )?received' |wc -l |awk '{print $1}' ) -eq 0 ]; then return 1; fi
  # optional /etc/hosts matching
  if ! [ -z "$2" ]; then
    grep -qE '^'$( echo $1 |perl -pe 's/\./\\./g' )'[ \t]' /etc/hosts
    if [ $? -eq 0 ]; then
      grep -E '^'$( echo $1 |perl -pe 's/\./\\./g' )'[ \t]' /etc/hosts |grep -q "$2" || return 1
    fi
  else
    grep -qE '^'$( echo $1 |perl -pe 's/\./\\./g' )'[ \t]' /etc/hosts && return 1
  fi
  return 0
}

# output network ip addresses and assignments
#
# optional:
#   --start   start output at IP
#
function network_ip_list {
  network_exists "$1" || err "Missing network or invalid format. Please ensure you are entering 'location-zone-alias'."
  local Location Zone Alias Net NetMask CIDR Gateway DNS Vlan Description i File DPad EPad Broadcast \
        Octal IP Reserved DHCP Hostname HostInterface Comment IntComment Owner Title TitleLength \
        Length Add Start=0

  # [FORMAT:network]: location,zone,alias,network,mask,cidr,gateway_ip,static_routes,dns_ip,vlan,description,repo_address,repo_fs_path,repo_path_url,build,default-build,ntp_ip,dhcp_ip\n
  read -r Location Zone Alias Net NetMask CIDR Gateway DNS Vlan Description <<< "$( grep -E "^${1//-/,}," ${CONF}/network |awk 'BEGIN{FS=","}{print $1,$2,$3,$4,$5,$6,$7,$9,$10,$11}' )"
  shift

  while [ $# -gt 0 ]; do case $1 in
    --start) valid_ip $2 || err "Invalid IP address"; Start=$( ip2dec $2 ); shift;;
    *) network_ip_list_help >&2; return 1;;
  esac; shift; done

  Title="$( printf -- "%s - %s - %s - VLAN %s\n" "${Location}-${Zone}-${Alias}" "${Net}/${CIDR}" "$Description" "${Vlan}" )"

  # compute the broadcast address
  Broadcast=$( dec2ip $(( $( ip2dec $Net ) + $( cdr2size $CIDR ) - 1 )) )

  # networks are stored as /24s so adjust the netmask if it's smaller than that
  test $CIDR -gt 24 && CIDR=24

  # formatting
  if [ $((${#Title}%2)) -eq 1 ]; then Add=1; else Add=0; fi
  Length=135	# 16 + 36 + 60 + 15 + 8
  DPad=$( printf '%0.1s' "-"{1..135} )
  EPad=$( printf '%0.1s' "="{1..137} )
  TitleLength=$(( ((${#Title}+$Length)/2) - 1 ))

  printf '%s\n' "$EPad"
  printf "|%*s%*s|\n" $TitleLength "$Title" $(((($Length-${#Title})/2)+$Add))
  printf '%s\n' "$EPad"
  printf '| %-16s | %-36s | %-60s | %-12s |\n' 'IP Address' 'Hostname' 'Comment' 'User'
  printf '|%s|\n' "$DPad"

  # look at each /24 in the network
  for ((i=0;i<$(( 2**(24 - $CIDR) ));i++)); do

    File=$( get_network $( dec2ip $(( $( ip2dec $Net ) + ( $i * 256 ) )) ) 24 )

    # skip this address if the entire subnet is not configured
    test -f ${CONF}/net/${File} || continue

    # [FORMAT:net/network]: octal_ip,cidr_ip,reserved,dhcp,hostname,host_interface,comment,interface_comment,owner\n
    while IFS=',' read -r Octal IP Reserved DHCP Hostname HostInterface Comment IntComment Owner; do

      if [ $Octal -lt $Start ]; then continue; fi

      if [ "$IP" == "$Gateway" ]; then
        Hostname="***GATEWAY***"
      elif [ "$IP" == "$Net" ]; then
        Hostname="***NETWORK***"; Comment="Network Address Reserved"
      elif [ "$IP" == "$Broadcast" ]; then
        Hostname="***BROADCAST***"; Comment="Broadcast Address Reserved"
      elif [ "$Reserved" == "y" ]; then
        Hostname="***RESERVED*** $Hostname"
      fi

      printf '| %-16s | %-36s | %-60s | %-12s |\n' "$IP" "$Hostname" "$Comment" "$Owner"

    done <<< "$( cat ${CONF}/net/${File} )"

  done

  printf '%s\n' "$EPad"

  return 0
}
function network_ip_list_help { cat <<_EOF
Usage: $0 network <name> ip --list [--start <a.b.c.d>]
_EOF
}

# list unassigned and unreserved ip addresses in a network
#
# optional arguments:
#   --limit X   limit to X number of randomized results
#
function network_ip_list_available {
  network_exists "$1" || err "Missing network or invalid format. Please ensure you are entering 'location-zone-alias'."
  if [[ "$2" == "--limit" && "${3//[^0-9]/}" == "$3" && $3 -gt 0 ]]; then
    network_ip_list_available $1 |shuf |head -n $3
    return
  fi
  # load the network
  # [FORMAT:network]
  read -r NETIP NETCIDR <<< "$( grep -E "^${1//-/,}," ${CONF}/network |awk 'BEGIN{FS=","}{print $4,$6}' )"
  # networks are stored as /24s so adjust the netmask if it's smaller than that
  test $NETCIDR -gt 24 && NETCIDR=24
  # look at each /24 in the network
  for ((i=0;i<$(( 2**(24 - $NETCIDR) ));i++)); do
    FILENAME=$( get_network $( dec2ip $(( $( ip2dec $NETIP ) + ( $i * 256 ) )) ) 24 )
    # skip this address if the entire subnet is not configured
    test -f ${CONF}/net/${FILENAME} || continue
    # 'free' IPs are those with 'n' in the third column and an empty fifth column
    # [FORMAT:net/network]
    grep -E '^[^,]*,[^,]*,n,' ${CONF}/net/${FILENAME} |grep -E '^[^,]*,[^,]*,[yn],[yn],,' |awk 'BEGIN{FS=","}{print $2}'
  done
}

# locate the registered networks the provided IP resides in
#
function network_ip_locate {
  test $# -eq 1 || return 1
  valid_ip $1 || return 1
  local ADDR=$( ip2dec $1 ) NAME NET CIDR
  # [FORMAT:network]
  while read NAME NET CIDR; do
    if [[ $ADDR -ge $( ip2dec $NET ) && $ADDR -le $( ip2dec $( ipadd $NET $(( $( cdr2size $CIDR ) - 1 )) ) ) ]]; then printf -- "%s\n" "$NAME"; fi
  done <<< "$( awk 'BEGIN{FS=","}{print $1"-"$2"-"$3,$4,$6}' ${CONF}/network )"
}

# scan a subnet for used addresses and reserve them
#
function network_ip_scan {
  network_exists "$1" || err "Missing network or invalid format. Please ensure you are entering 'location-zone-alias'."
  start_modify
  # declare variables
  local NETIP NETCIDR FILENAME
  # load the network
  # [FORMAT:network]
  read -r NETIP NETCIDR <<< "$( grep -E "^${1//-/,}," ${CONF}/network |awk 'BEGIN{FS=","}{print $4,$6}' )"
  # loop through the ip range and check each address
  for ((i=$( ip2dec $NETIP );i<$( ip2dec $( ipadd $NETIP $( cdr2size $NETCIDR ) ) );i++)); do
    FILENAME=$( get_network $( dec2ip $i ) 24 )
    # skip this address if the entire subnet is not configured
    test -f ${CONF}/net/${FILENAME} || continue
    # skip the address if it is registered
    grep -q "^$i," ${CONF}/net/${FILENAME} || continue
    # skip the address if it is already marked reserved
    # [FORMAT:net/network]
    grep "^$i," ${CONF}/net/${FILENAME} |grep -qE '^[^,]*,[^,]*,y,' && continue
    if [ $( exit_status network_ip_check $( dec2ip $i ) ) -ne 0 ]; then
      # mark the address as reserved
      # [FORMAT:net/network]
      IFS="," read -r A B C D E F G H I <<<"$( grep "^$i," ${CONF}/net/${FILENAME} )"
      # [FORMAT:net/network]
      perl -i -pe "s/^$i,.*/$A,$B,y,$D,$E,$F,auto-reserved: address in use,$H,$I/" ${CONF}/net/${FILENAME}
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
  # [FORMAT:net/network]
  IFS="," read -r A B C D E F G H I <<<"$( grep "^$( ip2dec $1 )," ${CONF}/net/${FILENAME} )"
  # [FORMAT:net/network]
  perl -i -pe "s/^$( ip2dec $1 ),.*/$A,$B,n,$D,,,,,/" ${CONF}/net/${FILENAME}
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
  network_exists "$1" || err "Missing network or invalid format. Please ensure you are entering 'location-zone-alias'."
  # function
  case "$2" in
    --add-range) network_ipam_add_range $1 ${@:3};;
    --remove-range) network_ipam_remove_range $1 ${@:3};;
    --reserve-range) network_ipam_reserve_range $1 ${@:3};;
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
  network_exists "$1" || err "Missing network or invalid format. Please ensure you are entering 'location-zone-alias'."
  start_modify
  test $# -gt 1 || err "An IP and mask or IP Range is required"
  # initialize variables
  local NETNAME=$1 FIRST_IP LAST_IP CIDR NETIP NETLAST NETCIDR; shift
  # first check if a mask was provided in the first address
  printf -- "$1" |grep -q "/"
  if [ $? -eq 0 ]; then
    FIRST_IP=$( printf -- "$1" |perl -pe 's%/.*%%' )
    CIDR=$( printf -- "$1" |perl -pe 's%.*/%%' )
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
  # [FORMAT:network]
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
    # [FORMAT:net/network]
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
  network_exists "$1" || err "Missing network or invalid format. Please ensure you are entering 'location-zone-alias'."
  test $# -gt 1 || err "An IP and mask or IP Range is required"
  # initialize variables
  local NETNAME=$1 FIRST_IP LAST_IP CIDR NETIP NETLAST NETCIDR; shift
  # first check if a mask was provided in the first address
  printf -- "$1" |grep -q "/"
  if [ $? -eq 0 ]; then
    FIRST_IP=$( printf -- "$1" |perl -pe 's%/.*%%' )
    CIDR=$( printf -- "$1" |perl -pe 's%.*/%%' )
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
  # [FORMAT:network]
  read -r NETIP NETCIDR <<< "$( grep -E "^${NETNAME//-/,}," ${CONF}/network |awk 'BEGIN{FS=","}{print $4,$6}' )"
  # get the expected last ip in the network
  NETLAST=$( ipadd $NETIP $(( $( cdr2size $NETCIDR ) - 1 )) )
  [[ $( ip2dec $FIRST_IP ) -lt $( ip2dec $NETIP ) || $( ip2dec $FIRST_IP ) -gt $( ip2dec $NETLAST) ]] && err "Starting address is outside expected range."
  [[ $( ip2dec $LAST_IP ) -lt $( ip2dec $NETIP ) || $( ip2dec $LAST_IP ) -gt $( ip2dec $NETLAST) ]] && err "Ending address is outside expected range."
  # confirm
  start_modify
  echo "This operation will remove records for $(( $( ip2dec $LAST_IP ) - $( ip2dec $FIRST_IP ) + 1 )) ip address(es)!"
  get_yn RL "Are you sure (y/n)?"
  if [ "$RL" == "y" ]; then
    # loop through the ip range and remove each address from the appropriate file
    for ((i=$( ip2dec $FIRST_IP );i<=$( ip2dec $LAST_IP );i++)); do
      # get the file name
      FILENAME=$( get_network $( dec2ip $i ) 24 )
    # [FORMAT:net/network]
      perl -i -ne "print unless /^$i,/" ${CONF}/net/$FILENAME 2>/dev/null
    done
    git add ${CONF}/net/$FILENAME >/dev/null 2>&1
    commit_file ${CONF}/net/$FILENAME
  fi
}

# mark a range of IP addresses as reserved and unavailable for allocation
#
# arguments:
#   loc-zone-alias  required
#   start-ip/mask   optional ip and optional mask (or bits)
#   end-ip          optional end ip
#
function network_ipam_reserve_range {
  network_exists "$1" || err "Missing network or invalid format. Please ensure you are entering 'location-zone-alias'."
  test $# -gt 1 || err "An IP and mask or IP Range is required"
  # initialize variables
  local NETNAME=$1 FIRST_IP LAST_IP CIDR NETIP NETLAST NETCIDR; shift
  # first check if a mask was provided in the first address
  printf -- "$1" |grep -q "/"
  if [ $? -eq 0 ]; then
    FIRST_IP=$( printf -- "$1" |perl -pe 's%/.*%%' )
    CIDR=$( printf -- "$1" |perl -pe 's%.*/%%' )
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
  # [FORMAT:network]
  read -r NETIP NETCIDR <<< "$( grep -E "^${NETNAME//-/,}," ${CONF}/network |awk 'BEGIN{FS=","}{print $4,$6}' )"
  # get the expected last ip in the network
  NETLAST=$( ipadd $NETIP $(( $( cdr2size $NETCIDR ) - 1 )) )
  [[ $( ip2dec $FIRST_IP ) -lt $( ip2dec $NETIP ) || $( ip2dec $FIRST_IP ) -gt $( ip2dec $NETLAST) ]] && err "Starting address is outside expected range."
  [[ $( ip2dec $LAST_IP ) -lt $( ip2dec $NETIP ) || $( ip2dec $LAST_IP ) -gt $( ip2dec $NETLAST) ]] && err "Ending address is outside expected range."
  # confirm
  start_modify
  # loop through the ip range and reserve each address in the appropriate file
  for ((i=$( ip2dec $FIRST_IP );i<=$( ip2dec $LAST_IP );i++)); do
    # get the file name
    FILENAME=$( get_network $( dec2ip $i ) 24 )

    # load the ip data
    # [FORMAT:net/network]: octal_ip,cidr_ip,reserved,dhcp,hostname,host_interface,comment,interface_comment,owner\n
    IFS="," read -r A B C D E F G H I <<<"$( grep "^$i," ${CONF}/net/${FILENAME} )"

    # [FORMAT:net/network]
    perl -i -pe "s/^$i,.*/$A,$B,y,$D,$E,$F,reserved,$H,$I/" ${CONF}/net/${FILENAME}

    git add ${CONF}/net/${FILENAME}
  done
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
        DEFAULT=$( grep -E "^$2," ${CONF}/network |grep -E ',y,y(,[^,]*){2}$' |awk 'BEGIN{FS=","}{print $1"-"$2"-"$3}' )
        ALL=$( grep -E "^$2," ${CONF}/network |grep -E ',y,[yn](,[^,]*){2}$' |awk 'BEGIN{FS=","}{print $1"-"$2"-"$3}' |tr '\n' ' ' )
        test ! -z "$DEFAULT" && printf -- "default: $DEFAULT\n"
        test ! -z "$ALL" && printf -- "available: $ALL\n"
        ;;
      --match)
        $( valid_ip $2 ) || err "Invalid IP"
        DEC=$( ip2dec $2 )
        # [FORMAT:network]
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
    ( printf -- "Site Alias Network\n"; network_list_unformatted ) |column -t |perl -pe 's/^/   /'
  fi
}

function network_list_unformatted {
  # [FORMAT:network]
  awk 'BEGIN{FS=","}{print $1"-"$2,$3,$4"/"$6}' ${CONF}/network |sort
}

# return path to a temporary file with static routes for the requested IP, if there are any
#
function network_routes_by_ip {
  test $# -eq 1 || return 1
  valid_ip $1 || return 1
  local NAME=$( network_ip_locate $1 )
  test -z "$NAME" && return 1
  printf -- '%s' "$NAME" |grep -q " " && err "Error: more than one network was returned for the provided address"
  # [FORMAT:network]
  IFS="," read -r LOC ZONE ALIAS NET MASK BITS GW HAS_ROUTES DNS VLAN DESC REPO_ADDR REPO_PATH REPO_URL BUILD DEFAULT_BUILD NTP DHCP <<< "$( grep -E "^${NAME//-/,}," ${CONF}/network )"
  if [ "$HAS_ROUTES" != "y" ]; then return; fi
  if [ -f "${CONF}/net/${NET}-routes" ]; then mkdir $TMP >/dev/null 2>&1; cat ${CONF}/net/${NET}-routes >$TMP/${NET}-routes; printf -- '%s\n' "$TMP/${NET}-routes"; fi
}

# output network info
#
# network:
#   location,zone,alias,network,mask,cidr,gateway_ip,static_routes,dns_ip,vlan,description,repo_address,repo_fs_path,repo_path_url,build,default-build,ntp_ip
#
function network_show {
  network_exists "$1" || err "Missing network or invalid format. Please ensure you are entering 'location-zone-alias'."
  local LOC ZONE ALIAS NET MASK BITS GW HAS_ROUTES DNS VLAN DESC REPO_ADDR REPO_PATH REPO_URL BUILD DEFAULT_BUILD NTP BRIEF=0
  [ "$2" == "--brief" ] && BRIEF=1
  #   --format: location,zone,alias,network,mask,cidr,gateway_ip,dns_ip,vlan,description,repo_address,repo_fs_path,repo_path_url,build,default-build\n
  # [FORMAT:network]
  IFS="," read -r LOC ZONE ALIAS NET MASK BITS GW HAS_ROUTES DNS VLAN DESC REPO_ADDR REPO_PATH REPO_URL BUILD DEFAULT_BUILD NTP DHCP <<< "$( grep -E "^${1//-/,}," ${CONF}/network )"
  printf -- "Location Code: $LOC\nNetwork Zone: $ZONE\nSite Alias: $ALIAS\nDescription: $DESC\nNetwork: $NET\nSubnet Mask: $MASK\nSubnet Bits: $BITS\nGateway Address: $GW\nDNS Server: $DNS\nDHCP Server: $DHCP\nNTP Server: $NTP\nVLAN Tag/Number: $VLAN\nBuild Network: $BUILD\nDefault Build Network: $DEFAULT_BUILD\nRepository Address: $REPO_ADDR\nRepository Path: $REPO_PATH\nRepository URL: $REPO_URL\n"
  test $BRIEF -eq 1 && return
  printf -- "Static Routes:\n"
  if [ "$HAS_ROUTES" == "y" ]; then
    cat ${CONF}/net/${NET}-routes |perl -pe 's/^/   /'
  else
    printf -- "  None\n"
  fi
}

# update a network
#
# network:
#   location,zone,alias,network,mask,cidr,gateway_ip,static_routes,dns_ip,vlan,description,repo_address,repo_fs_path,repo_path_url,build,default-build,ntp_ip
#
function network_update {
  local L Z A NETORIG MASKORIG BITS GW HAS_ROUTES DNS VLAN DESC REPO_ADDR REPO_PATH REPO_URL BUILD DEFAULT_BUILD NTP DHCP
  start_modify
  if [ -z "$1" ]; then
    network_list
    printf -- "\n"
    get_input C "Network to Modify (loc-zone-alias)"
    printf -- "\n"
  else
    C="$1"
  fi
  network_exists "$C" || err "Missing network or invalid format. Please ensure you are entering 'location-zone-alias'."
  # [FORMAT:network]
  IFS="," read -r L Z A NETORIG MASKORIG BITS GW HAS_ROUTES DNS VLAN DESC REPO_ADDR REPO_PATH REPO_URL BUILD DEFAULT_BUILD NTP DHCP <<< "$( grep -E "^${C//-/,}," ${CONF}/network )"
  get_input LOC "Location Code" --default "$L" --options "$( location_list_unformatted |replace )"
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
  get_yn HAS_ROUTES "Does this network have host static routes (y/n)?" --default "$HAS_ROUTES" && network_edit_routes $NET
  get_input DNS "DNS Server Address" --null --default "$DNS"
  get_input DHCP "DHCP Server Address" --null --default "$DHCP"
  get_input NTP "NTP Server Address" --null --default "$NTP"
  get_input VLAN "VLAN Tag/Number" --default "$VLAN" --null
  get_yn BUILD "Use network for system builds (y/n)?" --default "$BUILD"
  if [ "$BUILD" == "y" ]; then
    get_yn DEFAULT_BUILD "Should this be the *default* build network at the location (y/n)?" --default "$DEFAULT_BUILD"
    # when adding a new default build network make sure we prompt if another exists, since it will be replaced
    if [[ "$DEFAULT_BUILD" == "y" && $( grep -E ',y$' ${CONF}/${LOC}/network |grep -vE "^${ZONE},${ALIAS}," |wc -l |awk '{print $1}' ) -ne 0 ]]; then
      get_yn RL "WARNING: Another default build network exists at this site. Are you sure you want to replace it (y/n)?"
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
  # [FORMAT:location/network]
  if [[ "$DEFAULT_BUILD" == "y" && $( grep -E ',y$' ${CONF}/${LOC}/network |grep -vE "^${ZONE},${ALIAS}," |wc -l |awk '{print $1}' ) -gt 0 ]]; then
    # get the current default network (if any) and update it
    # [FORMAT:location/network]
    IFS="," read -r ZP AP DISC <<< "$( grep -E ',y$' ${CONF}/${LOC}/network |grep -vE "^${ZONE},${ALIAS}," )"
    # [FORMAT:network]
    perl -i -pe "s%^(${LOC},${ZP},${AP},.*),y,y(,[^,]*){2}\$%\1,y,n\2%" ${CONF}/network
    # [FORMAT:location/network]
    perl -i -pe 's/,y$/,n/' ${CONF}/${LOC}/network
  fi
  #   --format: location,zone,alias,network,mask,cidr,gateway_ip,static_routes,dns_ip,vlan,description,repo_address,repo_fs_path,repo_path_url,build,default-build,ntp_ip\n
  # [FORMAT:network]
  perl -i -pe "s%^${C//-/,},.*%${LOC},${ZONE},${ALIAS},${NET},${MASK},${BITS},${GW},${HAS_ROUTES},${DNS},${VLAN},${DESC},${REPO_ADDR},${REPO_PATH},${REPO_URL},${BUILD},${DEFAULT_BUILD},${NTP},${DHCP}%" ${CONF}/network
  #   --format: zone,alias,network/cidr,build,default-build\n
  if [ "$LOC" == "$L" ]; then
    # location is not changing, safe to update in place
    # [FORMAT:location/network]
    perl -i -pe "s%^${Z},${A},.*%${ZONE},${ALIAS},${NET}/${BITS},${BUILD},${DEFAULT_BUILD}%" ${CONF}/${LOC}/network
    commit_file network ${CONF}/${LOC}/network
  else
    # location changed, remove from old location and add to new
    # [FORMAT:location/network]
    perl -i -ne "print unless /^${ZONE},${ALIAS},/" ${CONF}/${L}/network
    test ! -d ${CONF}/${LOC} && mkdir ${CONF}/${LOC}
    # [FORMAT:location/network]
    printf -- "${ZONE},${ALIAS},${NET}/${BITS},${BUILD},${DEFAULT_BUILD}\n" >>${CONF}/${LOC}/network
    commit_file network ${CONF}/${LOC}/network ${CONF}/${L}/network
  fi
  if [[ "$HAS_ROUTES" == "y" && -f $TMP/${NET}-routes ]]; then cat $TMP/${NET}-routes >${CONF}/net/${NET}-routes; commit_file ${CONF}/net/${NET}-routes; fi
}


#Section: TEMPLATE
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
  while [ $( grep -cE '{% (resource|constant|system)\.[^ ,]+ %}' $1 ) -gt 0 ]; do
    local NAME=$( grep -Em 1 '{% (resource|constant|system)\.[^ ,]+ %}' $1 |perl -pe 's/.*\{% (resource|constant|system)\.([^ ,]+) %\}.*/\1.\2/' )
    grep -qE "^$NAME " $2
    if [ $? -ne 0 ]; then
      if [ $SHOWERROR -eq 1 ]; then printf -- "Error: Undefined variable $NAME\n" >&2; fi
      if [ $VERBOSE -eq 1 ]; then
        printf -- "  Missing Variable: '$NAME'\n" >&2
        perl -i -pe "s/{% ${NAME} %}//" $1
        RETVAL=1
        continue
      else
        return 1
      fi
    fi
    local VAL=$( grep -E "^$NAME " $2 |perl -pe "s/^$NAME //" )
    perl -i -pe "my \$str = '${VAL}'; s/{% ${NAME} %}/\$str/" $1
  done
  return $RETVAL
}


#Section: RESOURCE
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
  # [FORMAT:resource]
  grep -qE "^ip,$1,,not assigned," ${CONF}/resource || err "Invalid or unavailable resource"
  # get the system name
  generic_choose system "$2" HOST
  # update the assignment in the resource file
  # [FORMAT:resource]
  perl -i -pe "s/^(ip,$1),,not assigned,(.*)\$/\1,host,$HOST,\2/" ${CONF}/resource
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
  # [FORMAT:resource]
  grep -qE "^(cluster_|ha_)?ip,$1,(host|application)," ${CONF}/resource || err "Invalid or unassigned resource"
  # confirm
  get_yn RL "Are you sure (y/n)?"
  test "$RL" != "y" && return
  # update the assignment in the resource file
  # [FORMAT:resource]
  perl -i -pe "s/^(.*ip,$1),(host|application),[^,]*,(.*)\$/\1,,not assigned,\2/" ${CONF}/resource
  commit_file resource
}

# resource field format:
#   type,value,assignment_type(application,host),assigned_to,name,description\n
#
function resource_create {
  start_modify
  # get user input and validate
  get_input NAME "Name" --null
  get_input TYPE "Type" --options ip,cluster_ip,ha_ip
  get_input VAL "Value" --nc
  get_input DESC "Description" --nc --null
  # validate unique value
  # [FORMAT:resource]
  grep -qE "^[^,]*,${VAL//,/}," $CONF/resource && err "Error - not a unique resource value."
  # add
  # [FORMAT:resource]
  printf -- "${TYPE},${VAL//,/},,not assigned,${NAME//,/},${DESC}\n" >>$CONF/resource
  commit_file resource
}

function resource_delete {
  start_modify
  generic_choose resource "$1" C && shift
  get_yn RL "Are you sure (y/n)?"
  if [ "$RL" == "y" ]; then
    # [FORMAT:resource]
    perl -i -ne "print unless /^[^,]*,${C},/" ${CONF}/resource
  fi
  commit_file resource
}

# general resource help
#
function resource_help { cat <<_EOF
NAME

SYNOPSIS
	scs resource <value> [--assign] [<system>]
	scs resource <value> [--unassign|--list]

DESCRIPTION

OPTIONS

EXAMPLES

RETURN CODE
	scs returns 0 on success and non-zero on error.

AUTHOR
	William Strucke <wstrucke@gmail.com>

COPYRIGHT
	Copyright © 2014 William Strucke. License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
	This is free software: you are free to change and redistribute it.  There is NO WARRANTY, to the extent permitted by law.

SEE ALSO
	$0 help
_EOF
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
    # [FORMAT:resource]
    grep -E "^$TYPE,$VAL," ${CONF}/resource |grep -qE ',(host|application),'
    if [ $? -eq 0 ]; then
      # ok... load the resource so we show what it's assigned to
      # [FORMAT:resource]
      IFS="," read -r TYPE VAL ASSIGN_TYPE ASSIGN_TO NAME DESC <<< "$( grep -E "^$TYPE,$VAL," ${CONF}/resource )"
      printf -- " $ASSIGN_TYPE:$ASSIGN_TO" |perl -pe 's/^ host/ system/'
    else
      printf -- " [unassigned]"
    fi
    printf -- "\n"
  done |column -t |perl -pe 's/^/   /'
}

# show available resources
#
# optional:
#  $1  regex to filter list on
#
function resource_list_unformatted {
  if ! [ -z "$1" ]; then
    # [FORMAT:resource]
    grep -E "$1" ${CONF}/resource |awk 'BEGIN{FS=","}{print $5,$1,$2}' |sort
  else
    # [FORMAT:resource]
    awk 'BEGIN{FS=","}{print $5,$1,$2}' ${CONF}/resource |sort
  fi
}

function resource_show {
  test $# -eq 1 || err "Provide the resource value"
  # [FORMAT:resource]
  grep -qE "^[^,]*,$1," ${CONF}/resource || err "Unknown resource"
  # [FORMAT:resource]
  IFS="," read -r TYPE VAL ASSIGN_TYPE ASSIGN_TO NAME DESC <<< "$( grep -E "^[^,]*,$1," ${CONF}/resource )"
  printf -- "Name: $NAME\nType: $TYPE\nValue: $VAL\nDescription: $DESC\nAssigned to $ASSIGN_TYPE: $ASSIGN_TO\n"
}

function resource_update {
  start_modify
  generic_choose resource "$1" C && shift
  # [FORMAT:resource]
  IFS="," read -r TYPE VAL ASSIGN_TYPE ASSIGN_TO NAME DESC <<< "$( grep -E "^[^,]*,$C," ${CONF}/resource )"
  get_input NAME "Name" --default "$NAME" --null
  get_input TYPE "Type" --options ip,cluster_ip,ha_ip --default "$TYPE"
  get_input VAL "Value" --nc --default "$VAL"
  # validate unique value
  if [ "$VAL" != "$C" ]; then
    # [FORMAT:resource]
    grep -qE "^[^,]*,${VAL//,/}," $CONF/resource && err "Error - not a unique resource value."
  fi
  get_input DESC "Description" --nc --null --default "$DESC"
  # [FORMAT:resource]
  perl -i -pe "s/^[^,]*,$C,.*/${TYPE},${VAL//,/},${ASSIGN_TYPE},${ASSIGN_TO},${NAME//,/},${DESC}/" ${CONF}/resource
  commit_file resource
}


#Section: HYPERVISOR
 #     # #     # ######  ####### ######  #     # ###  #####  ####### ######
 #     #  #   #  #     # #       #     # #     #  #  #     # #     # #     #
 #     #   # #   #     # #       #     # #     #  #  #       #     # #     #
 #######    #    ######  #####   ######  #     #  #   #####  #     # ######
 #     #    #    #       #       #   #    #   #   #        # #     # #   #
 #     #    #    #       #       #    #    # #    #  #     # #     # #    #
 #     #    #    #       ####### #     #    #    ###  #####  ####### #     #

#   --format: environment,hypervisor
function hypervisor_add_environment {
  hypervisor_exists "$1" || err "Unknown or missing hypervisor name."
  start_modify
  # get the environment
  generic_choose environment "$2" ENV
  # verify this mapping does not already exist
  # [FORMAT:hv-environment]
  grep -qE "^$ENV,$1\$" ${CONF}/hv-environment && err "That environment is already linked"
  # add mapping
  # [FORMAT:hv-environment]
  printf -- "$ENV,$1\n" >>${CONF}/hv-environment
  commit_file hv-environment
}

#   --format: loc-zone-alias,hv-name,interface
function hypervisor_add_network {
  hypervisor_exists "$1" || err "Unknown or missing hypervisor name."
  start_modify
  # get the network
  if [ -z "$2" ]; then
    network_list
    printf -- "\n"
    get_input C "Network to Modify (loc-zone-alias)"
  else
    test $( printf -- "$2" |perl -pe 's/[^-]*//g' |wc -c |awk '{print $1}' ) -eq 2 || err "Invalid format. Please ensure you are entering 'location-zone-alias'."
    C="$2"
  fi
  grep -qE "^${C//-/,}," ${CONF}/network || err "Unknown network"
  # verify this mapping does not already exist
  # [FORMAT:hv-network]
  grep -qE "^$C,$1," ${CONF}/hv-network && err "That network is already linked"
  # get the interface
  if [ -z "$3" ]; then get_input IFACE "Network Interface"; else IFACE="$3"; fi
  # add mapping
  # [FORMAT:hv-network]
  printf -- "$C,$1,$IFACE\n" >>${CONF}/hv-network
  commit_file hv-network
}

#   [<name>] [--add-network|--remove-network|--add-environment|--remove-environment|--poll|--search]
function hypervisor_byname {
  if [ "$1" == "--locate-system" ]; then hypervisor_locate_system ${@:2}; return; fi
  if [ "$1" == "--system-audit" ]; then hypervisor_system_audit ${@:2}; return; fi
  if [ "$1" == "--rank" ]; then hypervisor_rank ${@:2}; echo; return; fi
  if [ "$1" == "--uuid" ]; then hypervisor_qemu_uuid -q; return; fi
  hypervisor_exists "$1" || err "Unknown or missing hypervisor name."
  case "$2" in
    --add-environment) hypervisor_add_environment $1 ${@:3};;
    --add-network) hypervisor_add_network $1 ${@:3};;
    --poll) hypervisor_poll $1 ${@:3};;
    --register-key) hypervisor_register_key $1 ${@:3};;
    --remove-environment) hypervisor_remove_environment $1 ${@:3};;
    --remove-network) hypervisor_remove_network $1 ${@:3};;
    --search) hypervisor_search $1 ${@:3};;
  esac
}

#   --format: name,management-ip,location,vm-path,vm-min-disk(mb),min-free-mem(mb),enabled
function hypervisor_create {
  start_modify
  # get user input and validate
  get_input NAME "Hostname"
  # validate unique name
  hypervisor_exists "$1" && err "Hypervisor already defined."
  while ! $(valid_ip "$IP"); do get_input IP "Management IP"; done
  get_input LOC "Location" --options "$( location_list_unformatted |replace )"
  get_input VMPATH "VM Storage Path"
  get_input MINDISK "Disk Space Minimum (MB)" --regex '^[0-9]*$'
  get_input MINMEM "Memory Minimum (MB)" --regex '^[0-9]*$'
  get_yn ENABLED "Enabled (y/n)"
  # add
  # [FORMAT:hypervisor]
  printf -- "${NAME},${IP},${LOC},${VMPATH},${MINDISK},${MINMEM},${ENABLED}\n" >>$CONF/hypervisor
  commit_file hypervisor
}

function hypervisor_delete {
  generic_delete hypervisor $1 || return
  # also delete from hv-environment and hv-network
  # [FORMAT:hv-environment]
  perl -i -ne "print unless /^[^,]*,$1\$/" $CONF/hv-environment
  # [FORMAT:hv-network]
  perl -i -ne "print unless /^[^,]*,$1,/" $CONF/hv-network
  commit_file hv-environment hv-network
}

# checks if a hypervisor is defined
#
function hypervisor_exists {
  test $# -eq 1 || return 1
  # [FORMAT:hypervisor]
  grep -qE "^$1," $CONF/hypervisor || return 1
}

# general hypervisor help
#
function hypervisor_help { cat <<_EOF
NAME
	Hypervisors

SYNOPSIS
	scs hypervisor --locate-system <system_name> [--quick] | --system-audit | --rank | --uuid
	scs hypervisor <name> [--add-network|--remove-network|--add-environment|--remove-environment|--poll|--register-key|--search]

DESCRIPTION
	Hypervisors are libvirt/qemu CentOS Linux servers that are used for deployment and/or management of systems.

	Networks must be linked to hypervisors in order to build or deploy systems to them.  Environments must be
	linked in order for automatic system builds to function properly.  Each hypervisor can be linked to multiple
	and overlapping environments and networks.  They do not have to have identical network configurations though
	it is strongly recommended to configure them identically, where possible.

	Hypervisors should have the following scripts installed:
		/usr/local/utils/kvm
		/usr/local/utils/kvm-install.sh

	A future release should eliminate the external dependencies.

OPTIONS
	hypervisor create
		Define a hypervisor.

	hypervisor delete [<name>]
		Remove a hypervisor.  This will prevent scs from being able to locate systems on the removed host.

	hypervisor list [--location <string>] [--enabled] [--environment <string>] [--network <string>] [--backing <string>]
		List registered hypervisors.

		--location <string>	limit to the specified location
		--enabled		limit to enabled hypervisors (this also checks disk/memory minimums)
		--environment <string>	limit to the specified environment
		--network <string>	limit to the specified network (may be specified up to two times)
		--backing <string>	limit to hypervisors containing the specified backing image

	hypervisor show [<name>]
		Show hypervisor details, including configured network interfaces and linked environments.

	hypervisor update [<name>]
		Update hypervisor details, including enabling or disabling use of the host.

	hypervisor --locate-system <system_name> [--quick]
		Locate all hypervisors a system is registered on.  This function causes scs to lock due to the
		way it is implemented.

		The '--quick' flag will cause the function to simply output the last known configuration for a
		system, provided a location is known.  If the system has never been found a full search will
		be performed, which is the same behavior as if '--quick' was not specified.

	hypervisor --rank [--avoid <string>] hypervisor1 hypervisor2 ...
		Given a list of one or more registered hypervisors, rank them according to available resources
		and return the top ranked system.  This function is used internally to identify which
		hypervisor a host should be deployed to, given a pre-selected list of compatible systems.

		If --avoid is provided, the hypervisors will also be checked for a running system matching
		the provided substring.  If a match is found that hypervisor will not be returned unless the
		match is also found on all other provided hosts.

	hypervisor --system-audit
		System audit runs \`hypervisor --locate-system\` for every registered system.

	hypervisor --uuid
		Generate a globally unique id (guid) and mac address for a vm across all registered hypervisors.

	hypervisor <name> --add-network
		Link a registered network to a hypervisor on an interface.

	hypervisor <name> --remove-network
		Unlink a network from a hypervisor.

	hypervisor <name> --add-environment
		Link an environment to a hypervisor.

	hypervisor <name> --remove-environment
		Unlink an environment from a hypervisor.

	hypervisor <name> --poll
		Connect to the hypervisor and report back memory and disk utilization, and their respective values
		as a percentage of the configured minimums for the host.

	hypervisor <name> --register-key [--sudo <sudo_user>] <remote-user> <private-key>
		Register your SSH public key on the hypervisor under the specified user account.  The remote user
		account must exist and must be authorized for remote login.  You will be prompted for the user's
		password to add the key.

		The <private-key> argument is the path on your machine to the SSH private key.  The public key
		will be generated from this private key in order to validate both keys, and the private key can
		not be encrypted.

		If '--sudo' is provided then login with the sudo_user account and elevate privileges to
		remote-user to set up the key.

	hypervisor <name> --search <string>
		Search a hypervisor for virtual machines matching the provided string.  The string will be passed to
		grep so partial matches are valid.

EXAMPLES

RETURN CODE
	scs returns 0 on success and non-zero on error.

AUTHOR
	William Strucke <wstrucke@gmail.com>

COPYRIGHT
	Copyright © 2014 William Strucke. License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
	This is free software: you are free to change and redistribute it.  There is NO WARRANTY, to the extent permitted by law.

SEE ALSO
	$0 help
_EOF
}

# show the configured hypervisors
#
# optional:
#   --location <string>     limit to the specified location
#   --enabled               limit to enabled hypervisors (this also checks disk/memory minimums)
#   --environment <string>  limit to the specified environment
#   --network <string>      limit to the specified network (may be specified up to two times)
#   --backing <string>      limit to hypervisors containing the specified backing image
#
function hypervisor_list {
 local NUM A S LIST N NL HypervisorIP VMPath MinDisk MinMem
 NUM=$( wc -l ${CONF}/hypervisor |awk '{print $1}' )
  if [ $# -eq 0 ]; then
    if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
    echo "There ${A} ${NUM} defined hypervisor${S}."
    test $NUM -eq 0 && return
    awk 'BEGIN{FS=","}{print $1}' ${CONF}/hypervisor |sort |perl -pe 's/^/   /'
  else
    if [ $NUM -eq 0 ]; then return; fi
    LIST="$( awk 'BEGIN{FS=","}{print $1}' ${CONF}/hypervisor |tr '\n' ' ' )"
    while [ $# -gt 0 ]; do case "$1" in
      --location)
        NL=""
        for N in $LIST; do
          # [FORMAT:hypervisor]
          grep -qE '^'$N',[^,]*,'$2',' ${CONF}/hypervisor && NL="$NL $N"
        done; LIST="$NL"; shift
        ;;
      --enabled)
        NL=""
        for N in $LIST; do
          # [FORMAT:hypervisor]
          grep -qE '^'$N',([^,]*,){5}y' ${CONF}/hypervisor
          if [ $? -eq 0 ]; then
            [ $( hypervisor_poll $N --disk 2>/dev/null ) -eq 0 ] && continue
            [ $( hypervisor_poll $N --mem 2>/dev/null ) -eq 0 ] && continue
            NL="$NL $N"
          fi
        done; LIST="$NL"; shift
        ;;
      --environment)
        NL=""
        for N in $LIST; do
          # [FORMAT:hv-environment]
          grep -qE '^'$2','$N'$' ${CONF}/hv-environment && NL="$NL $N"
        done; LIST="$NL"; shift
        ;;
      --network)
        NL=""
        for N in $LIST; do
          # [FORMAT:hv-network]
          grep -qE '^'$2','$N',' ${CONF}/hv-network && NL="$NL $N"
        done; LIST="$NL"; shift
        ;;
      --backing)
        system_exists $2 || err "Invalid system"
        NL=""
        for N in $LIST; do
          # [FORMAT:hypervisor]
          read -r HypervisorIP VMPath <<< "$( grep -E "^$N," ${CONF}/hypervisor |awk 'BEGIN{FS=","}{print $2,$4}' )"
          check_host_alive $HypervisorIP || continue
          ssh_remote_command -d -q $HypervisorIP "test -f ${VMPath}/${BACKING_FOLDER}${2}.img" && NL="$NL $N"
        done; LIST="$NL"; shift
        ;;
      *) err "Invalid argument";;
    esac; shift; done
    for N in $LIST; do printf -- "$N\n"; done
  fi
}

# locate the hypervisor a system is installed on
#
# if more than one is found (i.e. due to shared filesystems) the HV the VM is running
#   on will be returned. if it is not running, one of the HVs will be picked and
#   returned
#
# --all                 show all hosts this system was found on
# --quick               try to use the cached location (if available)
# --search-as-backing   force search as a backing image regardless of system configuration
# --search-as-single    force search as a single regardless of system configuration
#
function hypervisor_locate_system {
  # !!FIXME!! -- This needs to not lock the repository, like, ever.
  system_exists $1 || err "Unknown system"

  # variable scope
  local NAME H HV PREF BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY ON OFF HIP ENABLED \
        VM STATE FOUND VMPATH ALL=0 QUICK=0 ForceBacking=0 ForceSingle=0 SystemBuildDate \
        Cache SystemLock

  # load the system
  # [FORMAT:system]
  IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$1," ${CONF}/system )"; shift
  test "$VIRTUAL" == "n" && err "Not a virtual machine"

  # process args
  while [ $# -ne 0 ]; do case $1 in
    --all)                ALL=1;;
    --quick)              QUICK=1;;
    --search-as-backing)  ForceBacking=1;;
    --search-as-single)   ForceSingle=1;;
  esac; shift; done

  if [ $ForceBacking -eq 1 ]; then BASE_IMAGE="y"; fi
  if [ $ForceSingle -eq 1 ] ; then BASE_IMAGE="n"; fi

  # cache check
  if [ $QUICK -eq 1 ]; then
    if [ $ALL -eq 1 ]; then
      # [FORMAT:hv-system]
      grep -E '^'$NAME',' ${CONF}/hv-system |awk 'BEGIN{FS=","}{print $2}' |sort
      grep -qE '^'$NAME',' ${CONF}/hv-system && return 0 || return 1
    fi
    # [FORMAT:hv-system]
    while read -r NAME H PREF; do
      if [[ -z "$HV" || "$PREF" == "y" ]]; then HV=$H; fi
    done <<< "$( grep -E '^'$NAME',' ${CONF}/hv-system |tr ',' ' ' )"
    if ! [ -z "$HV" ]; then printf -- '%s\n' "$HV"; return 0; fi
  fi

  # load hypervisors
  LIST=$( hypervisor_list --location $LOC )
  test -z "$LIST" && return 1

  # check if there is a preferred HV already
  # [FORMAT:hv-system]
  PREF="$( grep -E "^$NAME,[^,]*,y\$" ${CONF}/hv-system |awk 'BEGIN{FS=","}{print $2}' )"
  # [FORMAT:hv-system]
  Cache="$( grep -E "^$NAME," ${CONF}/hv-system |perl -pe 's/[^,]*,([^,]*),.*/\1/' |tr '\n' ' ' |perl -pe 's/ $//' )"

  # [FORMAT:hv-system]
  #perl -i -ne "print unless /^${NAME},/" ${CONF}/hv-system >/dev/null 2>&1

  # set defaults
  for HV in $LIST; do
    # load the host
    # [FORMAT:hypervisor]
    read HIP VMPATH ENABLED <<<"$( grep -E "^$HV," ${CONF}/hypervisor |awk 'BEGIN{FS=","}{print $2,$4,$7}' )"
    test "$ENABLED" == "y" || continue
    # test the connection
    check_host_alive $HIP || continue
    # search
    if [ "$BASE_IMAGE" == "y" ]; then
      VM=$( ssh_remote_command -d $HIP "ls ${VMPATH}/${BACKING_FOLDER}${NAME}.img 2>/dev/null |perl -pe 's/\.img//'" )
      if [ -z "$VM" ]; then STATE=""; else STATE="shut"; fi
    else
      read VM STATE <<<"$( ssh_remote_command -d $HIP "virsh list --all |awk '{print \$2,\$3}' |grep -vE '^(Name|\$)'" |grep -E "^$NAME " )"
    fi
    test -z "$VM" && continue
    if [ "$STATE" == "shut" ]; then OFF="$HV"; else ON="$HV"; fi
    # check the cache
    printf -- ' %s ' "$Cache" |grep -q " $HV "
    if [[ $? -ne 0 ]]; then
      printf -- '%s,%s,n\n' "$NAME" "$HV" >>${CONF}/hv-system
    else
      Cache="$( printf -- '%s' "$Cache" |perl -pe "s/ ?$HV ?//" )"
    fi
  done

  # remove hosts that were not found
  for HV in $Cache; do perl -i -ne "print unless /[^,]*,$HV,/" ${CONF}/hv-system >/dev/null 2>&1; done

  # check results
  if ! [ -z "$OFF" ]; then FOUND="$OFF"; fi
  if ! [ -z "$ON" ]; then FOUND="$ON"; PREF="$ON"; fi

  # update hypervisor-system map to set the preferred master
  # [FORMAT:hv-system]
  if [[ -n "$PREF" ]]; then perl -i -pe "s/^${NAME},${PREF},.*/${NAME},${PREF},y/" ${CONF}/hv-system; fi
  commit_file hv-system

  # output results and return status
  if [ $ALL -eq 1 ]; then
    # [FORMAT:hv-system]
    grep -E '^'$NAME',' ${CONF}/hv-system |awk 'BEGIN{FS=","}{print $2}' |sort
    grep -qE '^'$NAME',' ${CONF}/hv-system && return 0 || return 1
  fi
  if ! [ -z "$FOUND" ]; then printf -- '%s\n' $FOUND; return 0; fi
  return 1
}

# poll the hypervisor for current system status
#   --format: name,management-ip,location,vm-path,vm-min-disk(mb),min-free-mem(mb),enabled
#
# optional:
#   --disk   only display free disk in MB
#   --mem    only display free memory in MB
#
function hypervisor_poll {
  hypervisor_exists "$1" || err "Unknown or missing hypervisor name."
  local NAME IP LOC VMPATH MINDISK MINMEM ENABLED FREEMEM MEMPCT N M ONE FIVE FIFTEEN
  # load the host
  # [FORMAT:hypervisor]
  IFS="," read -r NAME IP LOC VMPATH MINDISK MINMEM ENABLED <<< "$( grep -E "^$1," ${CONF}/hypervisor )"
  # test the connection
  check_host_alive $IP || err "Hypervisor is not accessible at this time"
  # collect memory usage
  FREEMEM=$( ssh_remote_command -d $IP "free -m |head -n3 |tail -n1 |awk '{print \$NF}'" )
  MEMPCT=$( echo "scale=2;($FREEMEM / $MINMEM)*100" |bc |perl -pe 's/\..*//' )
  # optionally only return memory
  if [ "$2" == "--mem" ]; then
    # if memory is at or below minimum mask it as 0
    if [ $(( $FREEMEM - $MINMEM )) -le 0 ]; then printf -- "0"; else printf -- "$FREEMEM"; fi
    return 0
  fi
  # collect disk usage
  N=$( ssh_remote_command -d $IP "df -h $VMPATH |tail -n1 |awk '{print \$3}'" )
  case "${N: -1}" in
    T) M="* 1024 * 1024";;
    G) M="* 1024";;
    M) M="* 1";;
    k) M="/ 1024";;
    b) M="/ 1024 / 1024";;
    *) err "Unknown size qualifer in '$N'";;
  esac
  FREEDISK=$( echo "${N%?} $M" |bc |perl -pe 's/\..*//' )
  DISKPCT=$( echo "scale=2;($FREEDISK / $MINDISK)*100" |bc |perl -pe 's/\..*//' )
  # optionally only return disk space
  if [ "$2" == "--disk" ]; then
    # if disk is at or below minimum mask it as 0
    if [ $(( $FREEDISK - $MINDISK )) -le 0 ]; then printf -- "0"; else printf -- "$FREEDISK"; fi
    return 0
  fi
  # collect load data
  IFS="," read -r ONE FIVE FIFTEEN <<< "$( ssh_remote_command -d $IP "uptime |perl -pe 's/.* load average: //'" )"
  # output results
  printf -- "Name: $NAME\nAvailable Disk (MB): $FREEDISK (${DISKPCT}%% of minimum)\nAvailable Memory (MB): $FREEMEM (${MEMPCT}%% of minimum)\n1-minute Load Avg: $ONE\n5-minute Load Ave: $FIVE\n15-minute Load Avg: $FIFTEEN\n"
}

# generate a unique system uuid and mac address for a qemu virtual machine
#
# arguments:
#  -u  Validate Uniqueness of assigned UUIDs and MAC Addresses ONLY
#  -v  Verbose Output
#  -q  Generate a unique UUID/MAC ONLY
#  -?  Display Usage
#
function hypervisor_qemu_uuid {
  # variables
  local ALL_HV=$( hypervisor_list | tr '\n' ' ' )
  local HVS=""
  local TEMP="/tmp/kvm-uuid.$$"
  local XMLPATH="/etc/libvirt/qemu"
  local VERBOSE=0
  local VALIDATE=1
  local GENERATE=1
  local QUIET=0
  local DUPES=0

  # process arguments
  while [ $# -gt 0 ]; do case $1 in
    '-u') GENERATE=0;;
    '-v') VERBOSE=1;;
    '-q') VALIDATE=0; QUIET=1;;
    *) usage;;
  esac; shift; done

  # validate all HVs are online and accessible
  for H in $ALL_HV; do
    if [ $VERBOSE -eq 1 ]; then echo -n "Verifying hypervisor is online... " >&2; fi
    check_host_alive $H
    if [ $? -ne 0 ]; then
      test $VERBOSE -eq 1 && echo "error connecting to $H!" >&2
    else
      HVS="$( printf -- "$HVS $H" |perl -pe 's/^ //' )"
    fi
  done

  test -z "$HVS" && exit 1

  # enumerate all addresses currently in use
  for H in $HVS; do ssh_remote_command $H "grep -E '<(uuid|mac address)' ${XMLPATH}/*.xml"; done |sort |uniq |awk '{print $2,$3}' |perl -pe 's%[ \t]*[0-9]* <%%; s%'"'"'%%g; s%<?/[a-z]*>%%; s%( address=|>)% %' >$TEMP 2>/dev/null

  if [ $VALIDATE -eq 1 ]; then
    # MAC
    for M in $( grep mac $TEMP |sort |uniq -c |grep -vE '^ *1' |awk '{print $3}' ); do
      echo "**WARNING** Duplicate MAC Address '$M' found!"; DUPES=1
      for H in $HVS; do
        R=$( ssh_remote_command $H "cd ${XMLPATH}; grep '$M' *.xml |perl -pe 's%\.xml.*%%'" |replace |perl -pe 's%,$%%' )
        if ! [ -z "$R" ]; then echo "  [$H] $R"; fi
      done
    done

    # UUID
    for U in $( grep uuid $TEMP |sort |uniq -c |grep -vE '^ *1' |awk '{print $3}' ); do
      echo "**WARNING** Duplicate UUID '$U' found!"; DUPES=1
      for H in $HVS; do
        R=$( ssh_remote_command $H "cd ${XMLPATH}; grep '$U' *.xml |perl -pe 's%\.xml.*%%'" |replace |perl -pe 's%,$%%' )
        if ! [ -z "$R" ]; then echo "  [$H] $R"; fi
      done
    done
  fi

  if [ $GENERATE -eq 1 ]; then
    # find the next available MAC
    MAC="54:52:00$( < /dev/urandom tr -dc a-f0-9 |head -c6 |perl -pe 's%(..)%:\1%g' )"
    while [ $( grep -ic $MAC $TEMP ) -gt 0 ]; do
      MAC="54:52:00$( < /dev/urandom tr -dc a-f0-9 |head -c6 |perl -pe 's%(..)%:\1%g' )"
    done

    # find the next available UUID
    UUID=$( uuidgen )
    while [ $( grep -ic $UUID $TEMP ) -gt 0 ]; do UUID=$( uuidgen ); done

    test $QUIET -eq 0 && echo
    echo "UUID       : $UUID"
    echo "MAC Address: $MAC"
  fi

  if [[ $VALIDATE -eq 1 && $DUPES -eq 1 ]]; then
    exit 1
  elif [ $VALIDATE -eq 1 ]; then
    echo "All registered physical addresses are unique"
  fi
}

# given a list of one or more hypervisors return the top ranked system based on
#   available resources
#
# [--avoid <string>]  optional string to match on each hypervisor.  if all hosts are valid, exclude any
#                     with running VMs matching this string. if all available hosts match the string,
#                     then ignore it entirely.
#
function hypervisor_rank {
  test -z "$1" && return 1
  local AVOID
  # optional --avoid argument, to avoid putting a vm alongside another
  if [ "$1" == "--avoid" ]; then AVOID="$2"; shift 2; fi
  # create an array from the input list of hosts
  LIST=( $@ )
  # special case where only one host is provided
  if [ ${#LIST[@]} -eq 1 ]; then printf -- ${LIST[0]}; return 0; fi
  # start comparing at zero so first result is always the first best
  local DISK=0 MEM=0 D=0 M=0 SEL="" BACKUPSEL=""
  for ((i=0;i<${#LIST[@]};i++)); do
    # get the stats from the host
    D=$( hypervisor_poll ${LIST[$i]} --disk 2>/dev/null )
    test -z "$D" && continue
    M=$( hypervisor_poll ${LIST[$i]} --mem 2>/dev/null )
    # this is the tricky part -- how to we determine which is 'better' ?
    # what if one host has lots of free disk space but no memory?
    # I am going to rank free memory higher than CPU -- the host with the most memory unless they are very close
    C=$( echo "scale=2; (($M + 1) - ($MEM + 1)) / ($MEM + 1) * 100" |bc |perl -pe 's/\..*//' )
    if [ $C -gt 5 ]; then
      # greater than 5% more memory on this hypervisor, set it as preferred
      # ... but first check for avoidance
      if [[ ! -z "$AVOID" && ! -z "$( hypervisor_search ${LIST[$i]} $AVOID )" ]]; then
        # found a match, don't use this HV
        # since it already checked out set is a the backup if there is not one already
        test -z "$BACKUPSEL" && BACKUPSEL=${LIST[$i]}
      else
        MEM=$M; DISK=$D
        SEL=${LIST[$i]}
      fi
    fi
  done
  # if nothing was found, use the backup (in case of avoidance)
  if [ -z "$SEL" ]; then SEL=$BACKUPSEL; fi
  # if we still do not have anything, then no joy
  if [ -z "$SEL" ]; then err "Error ranking hypervisors"; fi
  printf -- $SEL
}

# register an ssh key on a hypervisor
#
function hypervisor_register_key {
  local IP
  hypervisor_exists "$1" || err "Unknown or missing hypervisor name."
  if [[ $# -lt 3 && $# -gt 6 ]]; then hypervisor_register_key_help >&2; exit 1; fi
  IP=$( hypervisor_show $1 --brief |grep Address |cut -d' ' -f3 )
  valid_ip $IP || err "The specified hypervisor has an invalid management address."
  if [ $# -eq 5 ]; then
    if [ "$2" != "--sudo" ]; then hypervisor_register_key_help >&2; exit 1; fi
    if [[ "$6" == "--debug" ]]; then
      register_ssh_key --host "$IP" --sudo "$3" --user "$4" --key "$5" --debug
    else
      register_ssh_key --host "$IP" --sudo "$3" --user "$4" --key "$5"
    fi
  else
    if [[ "$4" == "--debug" ]]; then
      register_ssh_key --host "$IP" --user "$2" --key "$3" --debug
    else
      register_ssh_key --host "$IP" --user "$2" --key "$3"
    fi
  fi
}
function hypervisor_register_key_help { cat <<_EOF
Usage: $0 hypervisor <name> --register-key [--sudo <sudo_user>] <user-name> <private-key-file>

Register an existing public/private key pair for key-based authentication
to a remote hypervisor under the specified user account.  You must have
the password and authorization to log in to the remote server.

If --sudo is provided, log into the hypervisor as <sudo_user> and use
the provided password (you will be prompted for it) to elevate
privileges to access the target account.
_EOF
}

function hypervisor_remove_environment {
  hypervisor_exists "$1" || err "Unknown or missing hypervisor name."
  start_modify
  # get the environment
  generic_choose environment "$2" ENV
  # verify this mapping exists
  # [FORMAT:hv-environment]
  grep -qE "^$ENV,$1\$" ${CONF}/hv-environment || return
  # remove mapping
  # [FORMAT:hv-environment]
  perl -i -ne "print unless /^${ENV},$1/" ${CONF}/hv-environment
  commit_file hv-environment
}

function hypervisor_remove_network {
  hypervisor_exists "$1" || err "Unknown or missing hypervisor name."
  start_modify
  # get the network
  if [ -z "$2" ]; then
    network_list
    printf -- "\n"
    get_input C "Network to Modify (loc-zone-alias)"
  else
    test $( printf -- "$2" |perl -pe 's/[^-]*//g' |wc -c |awk '{print $1}' ) -eq 2 || err "Invalid format. Please ensure you are entering 'location-zone-alias'."
    C="$2"
  fi
  grep -qE "^${C//-/,}," ${CONF}/network || err "Unknown network"
  # verify this mapping already exists
  # [FORMAT:hv-network]
  grep -qE "^$C,$1," ${CONF}/hv-network || return
  # remove mapping
  # [FORMAT:hv-network]
  perl -i -ne "print unless /^$C,$1,/" ${CONF}/hv-network
  commit_file hv-network
}

# search for running virtual machines matching a string
#
function hypervisor_search {
  hypervisor_exists "$1" || err "Unknown or missing hypervisor name."
  # load the host
  # [FORMAT:hypervisor]
  IFS="," read -r NAME IP LOC VMPATH MINDISK MINMEM ENABLED <<< "$( grep -E "^$1," ${CONF}/hypervisor )"
  # test the connection
  check_host_alive $IP || err "Hypervisor is not accessible at this time"
  # validate search string
  test -z "$2" && err "Missing search operand"
  # search
  local LIST=$( ssh_remote_command -d $IP "virsh list |awk '{print \$2}' |grep -vE '^(Name|\$)'" |grep "$2" )
  test -z "$LIST" && return 1
  printf -- "$LIST\n"
}

#   --format: name,management-ip,location,vm-path,vm-min-disk(mb),min-free-mem(mb),enabled
function hypervisor_show {
  hypervisor_exists "$1" || err "Unknown or missing hypervisor name."
  local NAME IP LOC VMPATH MINDISK MINMEM ENABLED BRIEF=0
  [ "$2" == "--brief" ] && BRIEF=1
  # load the host
  # [FORMAT:hypervisor]
  IFS="," read -r NAME IP LOC VMPATH MINDISK MINMEM ENABLED <<< "$( grep -E "^$1," ${CONF}/hypervisor )"
  # output the status/summary
  printf -- "Name: $NAME\nManagement Address: $IP\nLocation: $LOC\nVM Storage: $VMPATH\nReserved Disk (MB): $MINDISK\nReserved Memory (MB): $MINMEM\nEnabled: $ENABLED\n"
  test $BRIEF -eq 1 && return
  # get networks
  printf -- "\nNetwork Interfaces:\n"
  # [FORMAT:hv-network]
  grep -E ",$1," ${CONF}/hv-network |awk 'BEGIN{FS=","}{print $3":",$1}' |perl -pe 's/^/  /' |sort
  # get environments
  printf -- "\nLinked Environments:\n"
  # [FORMAT:hv-environment]
  grep -E ",$1\$" ${CONF}/hv-environment |perl -pe 's/^/  /; s/,.*//' |sort
  echo
}

# audit all virtual machines to locate which hypervisor they are on, to update the hv-system map
#
function hypervisor_system_audit {
  start_modify
  # load all virtual machines
  # [FORMAT:system]
  LIST=$( grep -E '^([^,]*,){5}y,' ${CONF}/system |awk 'BEGIN{FS=","}{print $1}' |sort )
  test -z "$LIST" && return
  # locate each virtual machine
  printf -- 'Please wait..'
  for S in $LIST; do hypervisor_locate_system $S >/dev/null 2>&1; printf -- '.'; done
  printf -- ' done\n'
}

#   --format: name,management-ip,location,vm-path,vm-min-disk(mb),min-free-mem(mb),enabled
function hypervisor_update {
  start_modify
  generic_choose hypervisor "$1" C && shift
  # [FORMAT:hypervisor]
  IFS="," read -r NAME ORIGIP LOC VMPATH MINDISK MINMEM ENABLED <<< "$( grep -E "^$C," ${CONF}/hypervisor )"
  get_input NAME "Hostname" --default "$NAME"
  # validate unique name if it is changed
  test "$NAME" != "$C" && grep -qE "^$NAME," $CONF/hypervisor && err "Hypervisor already defined."
  while ! $(valid_ip "$IP"); do get_input IP "Management IP" --default "$ORIGIP" ; done
  get_input LOC "Location" --options "$( location_list_unformatted |replace )" --default "$LOC"
  get_input VMPATH "VM Storage Path" --default "$VMPATH"
  get_input MINDISK "Disk Space Minimum (MB)" --regex '^[0-9]*$' --default "$MINDISK"
  get_input MINMEM "Memory Minimum (MB)" --regex '^[0-9]*$' --default "$MINMEM"
  get_yn ENABLED "Enabled (y/n)" --default "$ENABLED"
  # [FORMAT:hypervisor]
  perl -i -pe "s%$C,.*%${NAME},${IP},${LOC},${VMPATH},${MINDISK},${MINMEM},${ENABLED}%" ${CONF}/hypervisor
  if [ "$NAME" != "$C" ]; then
    # [FORMAT:hv-environment]
    perl -i -pe "s/,$C\$/,$NAME/" ${CONF}/hv-environment
    # [FORMAT:hv-network]
    perl -i -pe "s%^([^,]*),$C,(.*)\$%\1,${NAME},\2%" ${CONF}/hv-network
  fi
  commit_file hypervisor hv-environment hv-network
}


#Section: SYSTEM
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
  system_exists "$1" || err "Unknown or missing system name"
  # function
  case "$2" in
    --audit)               system_audit $1 ${@:3};;
    --check)               system_check $1 ${@:3};;
    --convert)             system_convert $1 ${@:3};;
    --deploy)              system_deploy $1 ${@:3};;
    --deprovision)         system_deprovision $1 ${@:3};;
    --distribute)          system_distribute $1 ${@:3};;
    --lock)                system_lock $1;;
    --provision)           system_provision $1 ${@:3};;
    --push-build-scripts)  system_push_build_scripts $1 ${@:3};;
    --register-key)        system_register_key $1 ${@:3};;
    --release)             system_release $1;;
    --start-remote-build)  system_start_remote_build $1 ${@:3};;
    --type)                system_type $1;;
    --unlock)              system_unlock $1;;
    --uptime)              system_uptime $1;;
    --vars)                system_vars $1;;
    --vm-add-disk)         system_vm_disk_create $1 ${@:3};;
    --vm-disks)            system_vm_disks $1;;
  esac
}

# audit a system against the generated configuration
#
# requires:
#  $1  system name
#
# optional:
#   --no-prompt   do not ask to review changes, just show differences
#
function system_audit {
  system_exists "$1" || err "Unknown or missing system name"
  local VALID=0 FILE F SkipCheck SkipPrompt=0 System="$1"; shift
  local NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate

  # process arguments
  while [ $# -gt 0 ]; do case $1 in
    --no-prompt) SkipPrompt=1;;
    *) err "invalid argument";;
  esac; shift; done

  # load the system
  # [FORMAT:system]
  IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$System," ${CONF}/system )"
  # test connectivity
  check_host_alive $System || err "System $System is not accessible at this time"

  # generate the release
  echo "Generating release..."
  FILE=$( system_release $System |tail -n1 |perl -pe 's/\.bsx/.cpio.gz/' )
  test -s "$FILE" || err "Error generating release"

  # prepare the release directory
  echo "Extracting..."
  mkdir -p $TMP/release/{REFERENCE,ACTUAL}

  # switch to the release root
  pushd $TMP/release/REFERENCE >/dev/null 2>&1

  # extract release to local directory
  gzip -dc $FILE |cpio -idm 2>/dev/null || err "Error extracting release to local directory"

  # clean up temporary release archive
  rm -f $FILE

  # move the stat file out of the way
  mv scs-stat ../

  # remove scs deployment scripts for audit
  rm -f scs-*

  # pull down the files to audit
  echo "Retrieving current system configuration..."
  for F in $( find . -type f |perl -pe 's%^\./%%' ); do
    mkdir -p $TMP/release/ACTUAL/$( dirname $F )
    scp -i $SCS_KeyFile -p $SCS_RemoteUser@$System:/$F $TMP/release/ACTUAL/$F >/dev/null 2>&1
  done
  ssh_remote_command -d $System "stat -c '%N %U %G %a %F' $( awk '{print $1}' $TMP/release/scs-stat |tr '\n' ' ' ) 2>/dev/null |perl -pe 's/regular (empty )?file/file/; s/symbolic link/symlink/'" |perl -pe 's/[`'"'"']*//g' >$TMP/release/scs-actual

  # review differences
  echo "Analyzing configuration..."
  for F in $( find . -type f |perl -pe 's%^\./%%' ); do
    SkipCheck=0

    if [ -f $TMP/release/ACTUAL/$F ]; then

      if [[ "$( file -b $TMP/release/REFERENCE/$F )" == "ASCII text" && -n "$( head -n1 $TMP/release/REFERENCE/$F |grep -- "-----BEGIN CERTIFICATE-----" )" ]]; then
        # this appears to be a certificate
        SkipCheck=1
        if [[ "$( openssl x509 -noout -modulus -in $TMP/release/REFERENCE/$F |openssl md5 |cut -d' ' -f2 )" != "$( openssl x509 -noout -modulus -in $TMP/release/ACTUAL/$F |openssl md5 |cut -d' ' -f2 )" ]]; then
          VALID=1
          echo "Deployed certificate and reference do not match: $F"
        fi
      elif [[ "$( file -b $F )" == "ASCII text" && -n "$( head -n1 $F |grep -- "-----BEGIN RSA PRIVATE KEY-----" )" ]]; then
        # this appears to be a private key
        SkipCheck=1
        if [[ "$( openssl rsa -noout -modulus -in $TMP/release/REFERENCE/$F |openssl md5 |cut -d' ' -f2 )" != "$( openssl rsa -noout -modulus -in $TMP/release/ACTUAL/$F |openssl md5 |cut -d' ' -f2 )" ]]; then
          VALID=1
          echo "Deployed private key and reference do not match: $F"
        fi
      fi

      if [[ $SkipCheck -eq 0 && $( md5s $TMP/release/{REFERENCE,ACTUAL}/$F |uniq |wc -l |awk '{print $1}' ) -gt 1 ]]; then
        VALID=1
        echo "Deployed file and reference do not match: $F"
        if [[ $SkipPrompt -ne 1 ]]; then
          get_yn DF "Do you want to review the differences (y/n/d) [Enter 'd' for diff only]?" --extra d
          test "$DF" == "y" && vimdiff $TMP/release/{REFERENCE,ACTUAL}/$F
          test "$DF" == "d" && diff -c $TMP/release/{REFERENCE,ACTUAL}/$F
        else
          diff $TMP/release/{REFERENCE,ACTUAL}/$F
        fi
      fi

    elif [ $( file_size $TMP/release/REFERENCE/$F ) -eq 0 ]; then
      echo "Ignoring empty file $F"
    else
      echo "WARNING: Remote system is missing file: $F"
      VALID=1
    fi
  done
  echo "Analyzing permissions..."
  diff $TMP/release/scs-stat $TMP/release/scs-actual
  if [ $? -ne 0 ]; then VALID=1; fi
  test $VALID -eq 0 && echo -e "\nSystem audit PASSED" || echo -e "\nSystem audit FAILED"
  exit $VALID
}

# check system configuration for validity (does it look like it will deploy OK?)
#
function system_check {
  system_exists "$1" || err "Unknown or missing system name"
  local FILES System=$1 VALID=0 VERBOSE=0; shift
  local NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate \
        FNAME FPTH FTYPE FOWNER FGROUP FOCTAL FTARGET FDESC

  while [ $# -gt 0 ]; do case "$1" in
    -v|--verbose) VERBOSE=1;;
  esac; shift; done

  # ensure the temp directory exists
  mkdir -p $TMP

  # load the system
  # [FORMAT:system]
  IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$System," ${CONF}/system )"
  # look up the applications configured for the build assigned to this system
  if ! [ -z "$BUILD" ]; then
    # retrieve application related data
    for APP in $( build_application_list "$BUILD" ); do
      # get the file list per application
      FILES=( ${FILES[@]} $( application_file_list_unformatted $APP --environment $EN ) )
    done
  fi

  # generate the variables for this system once
  system_vars $NAME >$TMP/systemvars.$$

  if [ ${#FILES[*]} -gt 0 ]; then
    for ((i=0;i<${#FILES[*]};i++)); do
      # get the file path based on the unique name
      # [FORMAT:file]
      IFS="," read -r FNAME FPTH FTYPE FOWNER FGROUP FOCTAL FTARGET FDESC <<< "$( grep -E "^${FILES[i]}," ${CONF}/file )"
      # remove leading '/' to make path relative
      FPTH=$( printf -- "$FPTH" |perl -pe 's%^/%%' )
      # missing file
      if [ -z "$FNAME" ]; then printf -- "Error: '${FILES[i]}' is invalid. Critical error.\n" >&2; VALID=1; continue; fi
      # skip if path is null (implies an error occurred)
      if [ -z "$FPTH" ]; then printf -- "Error: '$FNAME' has no path (index $i). Critical error.\n" >&2; VALID=1; continue; fi
      # ensure the relative path (directory) exists
      mkdir -p $TMP/release/$( dirname $FPTH )
      # how the file is created differs by type
      if [ "$FTYPE" == "file" ]; then
        # generate the file for this environment
        if [ $VERBOSE -eq 1 ]; then
          file_cat ${FILES[i]} --environment $EN --system-vars $TMP/systemvars.$$ --verbose >$TMP/release/$FPTH
        else
          file_cat ${FILES[i]} --environment $EN --system-vars $TMP/systemvars.$$ >$TMP/release/$FPTH
        fi
        if [ $? -ne 0 ]; then printf -- "Error generating file or replacing template variables, constants, and resources for ${FILES[i]}.\n" >&2; VALID=1; continue; fi
      elif [ "$FTYPE" == "binary" ]; then
        # simply copy the file, if it exists
        test -f $CONF/env/$EN/binary/$FNAME
        if [ $? -ne 0 ]; then printf -- "Error: $FNAME does not exist for $EN.\n" >&2; VALID=1; fi
      elif [ "$FTYPE" == "copy" ]; then
        # copy the file using scp or fail
        scp $FTARGET $TMP/release/ >/dev/null 2>&1
        if [ $? -ne 0 ]; then printf -- "Error: $FNAME is not available at '$FTARGET'\n" >&2; VALID=1; fi
      fi
    done
  fi
  test $VALID -eq 0 && printf -- "System check PASSED\n" || printf -- "\nSystem check FAILED\n"
  return $VALID
}

# output a list of constants and values assigned to a system
#
function system_constant_list {
  local NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate C APP
  generic_choose system "$1" C && shift
  # load the system
  # [FORMAT:system]
  IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$C," ${CONF}/system )"
  mkdir -p $TMP; test -f $TMP/clist && :>$TMP/clist || touch $TMP/clist
  # 1. applications @ environment
  for APP in $( build_application_list "$BUILD" ); do
    # [FORMAT:value/env/app]
    constant_list_dedupe $TMP/clist $CONF/env/$EN/by-app/$APP >$TMP/clist.1
    cat $TMP/clist.1 >$TMP/clist
  done
  # 2. environments @ location
  # [FORMAT:value/loc/constant]
  constant_list_dedupe $TMP/clist $CONF/env/$EN/by-loc/$LOC >$TMP/clist.1; cat $TMP/clist.1 >$TMP/clist
  # 3. environments (global)
  # [FORMAT:value/env/constant]
  constant_list_dedupe $TMP/clist $CONF/env/$EN/constant >$TMP/clist.1; cat $TMP/clist.1 >$TMP/clist
  # 4. applications (global)
  for APP in $( build_application_list "$BUILD" ); do
    constant_list_dedupe $TMP/clist $CONF/value/by-app/$APP >$TMP/clist.1
    cat $TMP/clist.1 >$TMP/clist
  done
  # 5. global
  constant_list_dedupe $TMP/clist $CONF/value/constant >$TMP/clist.1; cat $TMP/clist.1 >$TMP/clist
  cat $TMP/clist
  rm -f $TMP/clist{,.1}
}

# convert a system to a different type
#
function system_convert {
  system_exists "$1" || err "Unknown or missing system name"

  # scope variables
  local NAME=$1 BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY curType newType \
        Confirm=1 Distribute=0 backingImage RL Hypervisor HypervisorAll HypervisorIP \
        VMPath HV HVIP HVPATH NETNAME Force=0 List File DryRun=0 Count HV_FINAL_INT \
        HV_BUILD_INT SystemBuildDate BUILDNET OS ARCH DISK RAM PARENT RDISK RRAM RP \
        UUID MAC SystemLock; shift

  # process arguments
  while [ $# -gt 0 ]; do case $1 in
    --backing)    newType=backing;;
    --distribute) Distribute=1;;
    --dry-run)    DryRun=1;;
    --force)      Force=1;;
    --network)    NETNAME="$2"; shift;;
    --no-prompt)  Confirm=0;;
    --overlay)    newType=overlay; backingImage="$2"; shift;;
    --single)     newType=single;;
    *)            err;;
  esac; shift; done

  # validate
  if [ "$newType" == "overlay" ]; then system_exists "$backingImage" || err "Unknown or missing backing system"; fi

  # load the system
  # [FORMAT:system]
  IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$NAME," ${CONF}/system )"

  # check lock
  if [[ "$SystemLock" != "n" ]]; then err "System locked; please unlock to make changes"; fi

  # get current type
  curType=$( system_type $NAME )

  # get the network by the system IP
  if [ -z "$NETNAME" ]; then
    NETNAME=$( network_list --match $IP ); if [ -z "$NETNAME" ]; then err "Unable to identify a registered network for the system"; fi
  fi

  # special cases
  if [ "$curType" == "physical" ]; then err "I am not nearly advanced enough to virtualize a physical server (yet)"; fi
  if [[ "$curType" == "$newType" && $Force -eq 0 ]]; then return 0; fi
  if [ -z "$newType" ]; then system_convert_help; return 1; fi

  # confirm operation (unless explicitly told not to)
  if [ $Confirm -ne 0 ]; then get_yn RL "Are you sure you want to convert $NAME from $curType to $newType (y/n)?" || return 0; fi

  if [ $DryRun -eq 0 ]; then start_modify; else echo "Dry Run - No changes will be made"; fi

  # locate system
  Hypervisor=$( hypervisor_locate_system $NAME )

  if [[ -z "$Hypervisor" && $Force -eq 1 ]]; then
    Hypervisor=$( hypervisor_locate_system $NAME --search-as-single )         ; if [ -z "$Hypervisor" ]; then err "Unable to locate hypervisor"; exit 1; fi
    HypervisorAll=$( hypervisor_locate_system $NAME --all --search-as-single ); if [ -z "$HypervisorAll" ]; then err "Unable to enumerate hypervisors"; exit 1; fi
    curType=single
  elif [ -z "$Hypervisor" ]; then
    err "Unable to locate hypervisor"; exit 1
  else
    HypervisorAll=$( hypervisor_locate_system $NAME --all )                   ; if [ -z "$HypervisorAll" ]; then err "Unable to enumerate hypervisors"; exit 1; fi
  fi

  # overlay to backing is the same as single to backing
  if [[ "$curType" == "overlay" && "$newType" == "backing" ]]; then curType=single; fi

  # load primary hypervisor
  # [FORMAT:hypervisor]
  read -r HypervisorIP VMPath <<< "$( grep -E "^$Hypervisor," ${CONF}/hypervisor |awk 'BEGIN{FS=","}{print $2,$4}' )"

  for HV in $HypervisorAll; do
    # load hypervisor configuration
    # [FORMAT:hypervisor]
    read -r HVIP HVPATH <<< "$( grep -E "^$HV," ${CONF}/hypervisor |awk 'BEGIN{FS=","}{print $2,$4}' )"

    # shut off vm if running
    if [ $DryRun -eq 0 ]; then
      ssh_remote_command -d -q $HVIP "virsh destroy $NAME; test -d ${HVPATH}/${BACKING_FOLDER} || mkdir -p ${HVPATH}/${BACKING_FOLDER}"
    else
      echo ssh -l $SCS_RemoteUser $HVIP "virsh destroy $NAME; test -d ${HVPATH}/${BACKING_FOLDER} || mkdir -p ${HVPATH}/${BACKING_FOLDER}"
    fi
  done

  # enumerate disk images
  List="$( ssh_remote_command -d $HypervisorIP "find ${VMPath} -type f -regex '.*\\.img\$' | grep -E '/${NAME}(\\..+)?.img\$'" |tr '\n' ' ' )"

  case "$curType->$newType" in

    'single->backing')

      # move disk image
      for File in $List; do
        if [ $DryRun -eq 0 ]; then
          scslog "moving '$File' to ${VMPath}/${BACKING_FOLDER}"
          ssh_remote_command -d -q $HypervisorIP "mv $File ${VMPath}/${BACKING_FOLDER}; chattr +i ${VMPath}/${BACKING_FOLDER}/$File"
        else
          echo ssh -l $SCS_RemoteUser $HypervisorIP "mv $File ${VMPath}/${BACKING_FOLDER}; chattr +i ${VMPath}/${BACKING_FOLDER}/$File"
        fi
      done
      if [ $DryRun -eq 0 ]; then List="$( ssh_remote_command -d $HypervisorIP "find ${VMPath} -type f -regex '.*\\.img\$' | grep -E '/${NAME}(\\..+)?.img\$'" |tr '\n' ' ' )"; fi

      # undefine vm
      for HV in $HypervisorAll; do
        # load hypervisor configuration
        # [FORMAT:hypervisor]
        read -r HVIP <<< "$( grep -E "^$HV," ${CONF}/hypervisor |awk 'BEGIN{FS=","}{print $2}' )"

        # undefine vm
        if [ $DryRun -eq 0 ]; then
          ssh_remote_command -d -q $HVIP "virsh undefine $NAME; test -f /etc/libvirt/qemu/$NAME.xml && rm -f /etc/libvirt/qemu/$NAME.xml"
        else
          echo ssh -l $SCS_RemoteUser $HVIP "virsh undefine $NAME; test -f /etc/libvirt/qemu/$NAME.xml && rm -f /etc/libvirt/qemu/$NAME.xml"
        fi
      done

      # redistribute vm (as needed)
      if [[ $Distribute -eq 1 && $DryRun -eq 0 ]]; then system_distribute $NAME; fi
      if [ $DryRun -eq 0 ]; then scslog "converted system $NAME from $curType -> $newType"; fi

      ;;

    'single->overlay')
      err "not implemented... and potentially hazardous"
      ;;

    'backing->single'|'backing->overlay')

      # verify no other systems overlay on this one
      for File in $List; do
        Count=$( ssh_remote_command -d $HypervisorIP "find ${VMPath} -type f -regex '.*\\.img' -exec qemu-img info {} \\; |grep ^backing |grep ${File} |wc -l |awk '{print \$1}'" )
        if [ $DryRun -eq 0 ]; then
          if [ $Count -gt 0 ]; then errlog "found $Count system overlay images on '$File': aborting"; exit 1; fi
        else
          echo ssh -l $SCS_RemoteUser $HypervisorIP "find ${VMPath} -type f -regex '.*\\.img' -exec qemu-img info {} \\; |grep ^backing |grep ${File} |wc -l |awk '{print \$1}'"
          echo "found $Count system overlay images on '$File': anything over 0 will normally cause an error"
        fi
      done

      # move images out of backing folder
      for File in $List; do
        if [ $DryRun -eq 0 ]; then
          ssh_remote_command -d $HypervisorIP "chattr -i ${File}; mv ${File} ${VMPath}/"
        else
          echo ssh -o "StrictHostKeyChecking no" -l $SCS_RemoteUser $HypervisorIP "chattr -i ${File}; mv ${File} ${VMPath}/"
        fi
      done
      List="$( ssh_remote_command -d $HypervisorIP "find ${VMPath} -type f -regex '.*\\.img\$' | grep -E '/${NAME}(\\..+)?.img\$'" |tr '\n' ' ' )"

      #  - lookup the build network for this system
      network_list --build $LOC |grep -E '^available' | grep -qE " $NETNAME( |\$)"
      if [ $? -eq 0 ]; then
        BUILDNET=$NETNAME
      else
        BUILDNET=$( network_list --build $LOC |grep -E '^default' |awk '{print $2}' )
      fi

      #  - get the network interfaces on the hypervisor
      # [FORMAT:hv-network]
      HV_BUILD_INT=$( grep -E "^$BUILDNET,$Hypervisor," ${CONF}/hv-network |perl -pe 's/^[^,]*,[^,]*,//' )
      HV_FINAL_INT=$( grep -E "^$NETNAME,$Hypervisor," ${CONF}/hv-network |perl -pe 's/^[^,]*,[^,]*,//' )
      [[ -z "$HV_BUILD_INT" || -z "$HV_FINAL_INT" ]] && err "Selected hypervisor '$Hypervisor' is missing one or more interface mappings for the selected networks."

      #  - load the architecture and operating system for the build
      # [FORMAT:build]
      IFS="," read -r OS ARCH DISK RAM PARENT <<< "$( grep -E "^$BUILD," ${CONF}/build |perl -pe 's/^[^,]*,[^,]*,[^,]*,//' )"
      ROOT=$( build_root $BUILD )
      # [FORMAT:build]
      IFS="," read -r OS ARCH RDISK RRAM RP <<< "$( grep -E "^$ROOT," ${CONF}/build |perl -pe 's/^[^,]*,[^,]*,[^,]*,//' )"
      test -z "$OS" && err "Error loading build"

      # set disk/ram
      if [ -z "$DISK" ]; then DISK=$RDISK; fi
      if [ -z "$RAM" ]; then RAM=$RRAM; fi

      #  - get disk size and memory
      test -z "$DISK" && DISK=$DEF_HDD
      test -z "$RAM" && RAM=$DEF_MEM

      scslog "following validation for $NAME - assigned ram '$RAM' and disk '$DISK'"

      #  - get globally unique mac address and uuid for the new server
      read -r UUID MAC <<< "$( hypervisor_qemu_uuid -q |perl -pe 's/^[^:]*: //' |tr '\n' ' ' )"

      # create new vm
      if [ $DryRun -eq 0 ]; then
        scslog "starting system build for $NAME on $Hypervisor at $BUILDIP"
        echo "Creating virtual machine..."
  #    scslog "Creating VM on $Hypervisor: /usr/local/utils/kvm-install.sh --arch $ARCH --ip ${BUILDIP}/${NETMASK} --gateway $GATEWAY --dns $DNS --interface $HV_BUILD_INT --no-console --no-reboot --os $OS --quiet --ram $RAM --mac $MAC --uuid $UUID --no-install --base ${VMPATH}/${BACKING_FOLDER}${OVERLAY}.img $NAME"
  # need ... buildip/mask, gateway, dns, interface
        scslog "Creating VM on $Hypervisor: /usr/local/utils/kvm-install.sh --arch $ARCH --no-console --no-reboot --os $OS --quiet --ram $RAM --mac $MAC --uuid $UUID --no-install --use-existing --disk-path ${VMPath}/${NAME}.img $NAME"
        ssh_remote_command -d -n $HypervisorIP "/usr/local/utils/kvm-install.sh --arch $ARCH --no-console --no-reboot --os $OS --quiet --ram $RAM --mac $MAC --uuid $UUID --no-install --use-existing --disk-path ${VMPath}/${NAME}.img $NAME"
        if [ $? -ne 0 ]; then
          echo ssh -n -l $SCS_RemoteUser $HypervisorIP "/usr/local/utils/kvm-install.sh --arch $ARCH --no-console --no-reboot --os $OS --quiet --ram $RAM --mac $MAC --uuid $UUID --no-install --use-existing --disk-path ${VMPath}/${NAME}.img $NAME"
          err "Error creating VM!"
        fi
      else
        echo ssh -n -l $SCS_RemoteUser $HypervisorIP "/usr/local/utils/kvm-install.sh --arch $ARCH --no-console --no-reboot --os $OS --quiet --ram $RAM --mac $MAC --uuid $UUID --no-install --use-existing --disk-path ${VMPath}/${NAME}.img $NAME"
      fi

      # check for secondary disks
      for File in $List; do
        if [ "$File" == "${VMPath}/${NAME}.img" ]; then continue; fi
        if [ $DryRun -eq 0 ]; then
          system_vm_disk_create $NAME --alias "$( printf -- "$( basename $File )" |perl -pe 's/^'${NAME}'\.//; s/\.img$//' )" --disk $File --use-existing --hypervisor $Hypervisor
          if [ $? -eq 0 ]; then scslog "successfully added secondary disk to $NAME"; else scslog "error adding secondary disk to $NAME"; fi
        else
          system_vm_disk_create $NAME --alias "$( printf -- "$( basename $File )" |perl -pe 's/^'${NAME}'\.//; s/\.img$//' )" --disk $File --use-existing --hypervisor $Hypervisor --dry-run
        fi
      done

      if [ $DryRun -eq 0 ]; then
        # start new virtual machine
        ssh_remote_command -d -n -q $HypervisorIP "virsh start $NAME"
      fi

      # update system configuration
      # [FORMAT:system]
      IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$NAME," ${CONF}/system )"
      # save changes
      # [FORMAT:system]
      perl -i -pe "s/^$C,.*/${NAME},${BUILD},${IP},${LOC},${EN},${VIRTUAL},n,${OVERLAY},${SystemLock},${SystemBuildDate}/" ${CONF}/system
      commit_file system

      if [ $DryRun -eq 0 ]; then scslog "converted system $NAME from $curType -> $newType"; fi

      ;;

    'overlay->single')
      err "not implemented... and potentially hazardous"
      ;;

    *)
      err "Unknown transition: $curType->$newType"
      ;;
  esac
  return 0
}
function system_convert_help { cat <<_EOF >&2
Usage: $0 system <name> --convert [--single|--backing|--overlay <backing_system>] [--distribute] [--dry-run] [--no-prompt]

Converts a virtual-machine to a different base type. The only 100% safe use case is converting a single (full deploy) to a backing image.

It may be safe to convert an overlay to single or backing provided we can figure out non-destrutive logic to merge the overlay into
the backing image, especially in the case where the backing image is shared with other systems.

WARNING: This function can be massively destructive if used improperly.
         E.g. converting the backing image for an entire DC to single or overlay could blow up everything all at once...
_EOF
}

# define a new system
#
# system:
#    name,build,ip,location,environment,virtual,backing_image,overlay\n
#
function system_create {
  local NAME BUILD LOC EN IP NETNAME VIRTUAL BASE_IMAGE OVERLAY_Q OVERLAY
  start_modify
  # get user input and validate
  get_input NAME "Hostname" --auto "$1"
  # validate unique name
  grep -qE "^$NAME," $CONF/system && err "System already defined."
  get_input BUILD "Build" --null --options "$( build_list_unformatted |replace )" --auto "$2"
  get_input LOC "Location" --options "$( location_list_unformatted |replace )" --auto "$3"
  get_input EN "Environment" --options "$( environment_list_unformatted |replace )" --auto "$4"
  while [[ "$IP" != "auto" && "$IP" != "dhcp" && $( exit_status valid_ip "$IP" ) -ne 0 ]]; do get_input IP "Primary IP (address, dhcp, or auto to auto-select)" --auto "$5"; done
  # automatic IP selection
  if [ "$IP" == "auto" ]; then
    get_input NETNAME "Network (loc-zone-alias)" --options "$( network_list_unformatted |grep -E "^${LOC}-" |awk '{print $1"-"$2 }' |replace )" --auto "$6"
    shift
    IP=$( network_ip_list_available $NETNAME --limit 1 )
    valid_ip $IP || err "Automatic IP selection failed"
  fi
  get_yn VIRTUAL "Virtual Server (y/n)" --auto "$6"
  if [ "$VIRTUAL" == "y" ]; then
    get_yn BASE_IMAGE "Use as a backing image for overlay (y/n)?" --auto "$7"
    get_yn OVERLAY_Q "Overlay on another system (y/n)?" --auto "$8"
    if [ "$OVERLAY_Q" == "y" ]; then
      get_input OVERLAY "Overlay System (or auto to select when provisioned)" --options "auto,$( system_list_unformatted --backing --exclude-parent $NAME |replace )" --auto "$9"
    else
      OVERLAY=""
    fi
  else
    BASE_IMAGE="n"
    OVERLAY=""
  fi
  # conditionally assign/reserve IP
  if [[ "$IP" != "dhcp" && ! -z "$( network_ip_locate $IP )" ]]; then network_ip_assign $IP $NAME || printf -- '%s\n' "Error - unable to assign the specified IP" >&2; fi
  # add
  # [FORMAT:system]
  printf -- "${NAME},${BUILD},${IP},${LOC},${EN},${VIRTUAL},${BASE_IMAGE},${OVERLAY},n,\n" >>$CONF/system
  commit_file system
}
function system_create_help {
  echo "Usage: $0 system create [hostname] [build] [location] [environment] [(n.n.n.n|auto)] [loc-zone-alias] [virtual:y/n] [backing_image:y/n] [overlay:y/n] [overlay:auto|<name>]"
}

function system_delete {
  system_exists "$1" || err "Unknown or missing system name"
  local NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate

  # load the system
  # [FORMAT:system]
  IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$1," ${CONF}/system )"

  # check lock
  if [[ "$SystemLock" != "n" ]]; then err "System locked; please unlock to make changes"; fi

  # verify this is not a backing image for other servers
  # [FORMAT:system]
  grep -qE ",$1,.*\$" ${CONF}/system
  if [ $? -eq 0 ]; then
    printf -- "%s\n" "Warning - this system is the backing image for one or more other virtual machines"
    get_yn R "Are you SURE you want to delete it (y/n)?" || exit
  fi

  generic_delete system $1 || return

  # free IP address assignment
  network_ip_unassign $IP >/dev/null 2>&1
}

# deploy release to system
#
# optional:
#   --install	automatically install on remote system after deployment
#
function system_deploy {
  local FILE Install=0 System="$1"; shift
  system_exists "$System" || err "Unknown or missing system name"
  while [ $# -gt 0 ]; do case $1 in
    --install) Install=1;;
    *) system_deploy_help >&2; exit 1;;
  esac; shift; done
  check_host_alive $System
  if [ $? -ne 0 ]; then printf -- "Unable to connect to remote system '$System'\n"; exit 1; fi
  printf -- "Generating release...\n"
  FILE=$( system_release $System 2>/dev/null |tail -n1 )
  if [ -z "$FILE" ]; then printf -- "Error generating release for '$System'\n"; exit 1; fi
  if ! [ -f "$FILE" ]; then printf -- "Unable to read release file\n"; exit 1; fi
  printf -- "Copying release to remote system...\n"
  scp -i $SCS_KeyFile $FILE $SCS_RemoteUser@$System: >/dev/null 2>&1
  if [ $? -ne 0 ]; then printf -- "Error copying release to '$System'\n"; exit 1; fi
  printf -- "Cleaning up...\n"
  rm -f $FILE
  if [ $Install -eq 0 ]; then
    printf -- "\nInstall like this:\n  ssh -l $SCS_RemoteUser $System \"/bin/bash /root/$( basename $FILE ) --install\"\n\n"
  else
    printf -- "Installing on remote server... "
    ssh_remote_command $System "/bin/bash /root/$( basename $FILE ) --install"
    if [ $? -eq 0 ]; then echo "success"; else echo "error!"; fi
  fi
}
function system_deploy_help { cat <<_EOF
Generate the complete configuration for a system, package it, and push to /root/ on the remote server.

Usage: $0 system <name> --deploy [--install]

If --install is also provided then the configuration will be applied to the remote system immediately.
_EOF
}

# destroy and permantantly delete a system
#
function system_deprovision {
  system_exists "$1" || err "Unknown or missing system name"
  # load the system

  local NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY HV HVIP VMPATH F LIST DRY_RUN=0 \
        HVFIRST SystemBuildDate SystemLock

  # [FORMAT:system]
  IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$1," ${CONF}/system )"; shift

  # check for dry-run flag
  if [ "$1" == "--dry-run" ]; then DRY_RUN=1; fi
  if [ "$1" == "--yes-i-am-sure" ]; then SURE=1; else SURE=0; fi

  # check lock
  if [[ "$SystemLock" != "n" && $DRY_RUN -eq 0 ]]; then err "System locked; please unlock to make changes"; fi

  # verify virtual machine
  test "$VIRTUAL" == "y" || err "This is not a virtual machine"

  # confirm
  if [ $SURE -ne 1 ]; then
    if [ $DRY_RUN -ne 1 ]; then
      printf -- '%s\nWARNING: This action WILL CAUSE DATA LOSS!\n%s\n\n' '******************************************' '******************************************'
    else
      printf -- '*** DRY-RUN *** DRY-RUN *** DRY-RUN ***\n\n'
    fi
    get_yn RL "Are you sure you want to shut off, destroy, and permanently delete the system '$NAME' (y/n)?" || return
    # confirm for overlay
    if [[ "$BASE_IMAGE" == "y" && $DRY_RUN -ne 1 ]]; then
      printf -- '\nWARNING: THIS SYSTEM IS A BASE_IMAGE FOR OTHER SERVERS - THIS ACTION IS IRREVERSABLE AND *WILL* DESTROY ALL OVERLAY SYSTEMS!!!\n\n'
      get_yn RL "Are you *absolutely certain* you want to permanently destroy this base image (y/n)?" || return
    fi
  fi

  # locate
  HV=$( hypervisor_locate_system $NAME )
  test -z "$HV" && err "Unable to locate hypervisor for this system"
  while ! [ -z "$HV" ]; do
    # load hypervisor settings
    # [FORMAT:hypervisor]
    read -r HVIP VMPATH <<< "$( grep -E '^'$HV',' ${CONF}/hypervisor |awk 'BEGIN{FS=","}{print $1,$4}' )"
    # test connection
    check_host_alive $HVIP || err "Unable to connect to hypervisor '$HV'@'$HVIP'"
    # get disks
    if [ "$BASE_IMAGE" == "y" ]; then
      LIST="$( ssh_remote_command -d $HVIP "ls ${VMPATH}/${BACKING_FOLDER}${NAME}.*img" )"
    else
      LIST="/etc/libvirt/qemu/$NAME.xml $( system_vm_disks $NAME )"
    fi
    scslog "removing from $HV: $LIST"
    # destroy
    if [ $DRY_RUN -ne 1 ]; then
      ssh_remote_command -d -q $HVIP "virsh destroy $NAME; sleep 1; virsh undefine $NAME"
    else
      echo ssh -l $SCS_RemoteUser $HVIP "virsh destroy $NAME; sleep 1; virsh undefine $NAME"
      test -z "$HVFIRST" && HVFIRST="$HV"
    fi
    # delete files / cleanup
    for F in $LIST; do
      if [[ "$F" == "/" || "$F" == "" ]]; then continue; fi
      if [ $DRY_RUN -ne 1 ]; then
        ssh_remote_command -d -n $HVIP "test -f $F && chattr -i $F && rm -f $F"
      else
        echo ssh -n -o "StrictHostKeyChecking no" -l $SCS_RemoteUser $HVIP "test -f $F && chattr -i $F && rm -f $F"
      fi
    done
    HV=$( hypervisor_locate_system $NAME )
    if [[ $DRY_RUN -eq 1 && "$HV" == "$HVFIRST" ]]; then HV=""; fi
  done

  printf -- '\n%s has been removed\n' "$NAME"
  scslog "$NAME has been deprovisioned"
  return 0
}

# ensure a backing image is distributed to all available hypervisors
#
# optional:
#   --hypervisor <name>	distribute to a specific hypervisor, ignoring other checks
#   --location <name>	limit distribution to environments at a specific location
#
function system_distribute {
  system_exists "$1" || err "Unknown or missing system name"

  # load the system
  local NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemBuildDate \
        Network HVList HV HVIP Hypervisor HypervisorIP VMPath HVPath \
        File FileList DryRun=0 Location LocalTransfer=1 SystemLock

  # [FORMAT:system]
  IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$1," ${CONF}/system )"; shift

  # check lock
  if [[ "$SystemLock" != "n" ]]; then err "System locked; please unlock to make changes"; fi

  while [ $# -gt 0 ]; do case $1 in
    --dry-run) DryRun=1;;
    --hypervisor) HVList="$2"; shift;;
    --location) Location="$2"; shift;;
    *) system_distribute_help; return 1;;
  esac; shift; done

  # verify virtual machine
  test "$VIRTUAL" == "y" || err "This is not a virtual machine"
  test "$BASE_IMAGE" == "y" || err "This is not a backing image"

  if ! [ -z "$HVList" ]; then hypervisor_exists $HVList || err "Invalid hypervisor"; fi

  if ! [[ -d $TMPLarge ]]; then mkdir $TMPLarge >/dev/null 2>&1 || err "Unable to create temporary folder"; fi

  # get the network by the system IP
  if [ "$IP" != "dhcp" ]; then
    Network=$( network_list --match $IP )
    if [ -z "$Network" ]; then err "Unable to identify a registered network for the system"; fi
  fi

  # identify the current location of the system
  Hypervisor=$( hypervisor_locate_system $NAME --quick )
  test -z "$Hypervisor" && err "Unable to locate the current host of this system"

  if [ $DryRun -ne 0 ]; then printf -- "DRY-RUN: No files or systems will be modified\n" >&2; fi

  # load hypervisor configuration
  # [FORMAT:hypervisor]
  read -r HypervisorIP VMPath <<< "$( grep -E "^$Hypervisor," ${CONF}/hypervisor |awk 'BEGIN{FS=","}{print $2,$4}' )"
  if [[ "$HypervisorIP" == "" || "$VMPath" == "" ]]; then err "Error loading hypervisor configuration"; fi

  # enumerate disk images
  List="$( ssh_remote_command -d $HypervisorIP "find ${VMPath}/${BACKING_FOLDER} -type f -regex '.*\\.img\$' | grep -E '/${NAME}(\\..+)?.img\$'" |tr '\n' ' ' )"
  if [ $DryRun -ne 0 ]; then printf -- "Located system files:\n%s\n" $List; fi

  # list hypervisors
  if [ -z "$HVList" ]; then
    if [[ -z "$Network" && -z "$Location" ]]; then
      HVList=$( hypervisor_list --environment $EN --enabled | tr '\n' ' ' )
    elif [ -z "$Location" ]; then
      HVList=$( hypervisor_list --network $Network --environment $EN --enabled | tr '\n' ' ' )
    elif [ -z "$Network" ]; then
      HVList=$( hypervisor_list --location $Location --environment $EN --enabled | tr '\n' ' ' )
    else
      HVList=$( hypervisor_list --network $Network --location $Location --environment $EN --enabled | tr '\n' ' ' )
    fi
  fi
  if [ $DryRun -ne 0 ]; then printf -- "Located hypervisor: %s\n" $HVList; else scslog -v "redistributing system $NAME to $( echo $HVList |tr ' ' ',' )"; fi

  # copy image
  for HV in $HVList; do

    if [ "$HV" == "$Hypervisor" ]; then continue; fi

    # load hypervisor configuration
    # [FORMAT:hypervisor]
    read -r HVIP HVPath <<< "$( grep -E "^$HV," ${CONF}/hypervisor |awk 'BEGIN{FS=","}{print $2,$4}' )"

    # test connection
    check_host_alive $HVIP || continue

    # test if a remote to remote transfer is possible
    ssh_remote_command -d $HypervisorIP "ssh $HV uptime >/dev/null 2>&1" && LocalTransfer=0 || LocalTransfer=1

    if [ $DryRun -ne 0 ]; then
      ssh_remote_command -d -q $HVIP "test -d ${HVPath}/${BACKING_FOLDER} || mkdir -p ${HVPath}/${BACKING_FOLDER}"
    fi

    for File in $List; do
      ssh_remote_command -d $HVIP "test -f ${HVPath}/${BACKING_FOLDER}$( basename $File )"
      if [ $? -eq 0 ]; then
        scslog -v "system already exists on $HV"
        continue
      fi
      if [ $DryRun -ne 0 ]; then
        echo "redistributing $File from $Hypervisor to $HV..."
        if [ $LocalTransfer -eq 0 ]; then
          echo "  ssh -o \"StrictHostKeyChecking no\" -l $SCS_RemoteUser $HypervisorIP \"scp ${File} $HV:${HVPath}/${BACKING_FOLDER}$( basename $File )\""
        else
          echo "  srcp -t ${TMPLarge} $HypervisorIP:${File} $HVIP:${HVPath}/${BACKING_FOLDER}$( basename $File )"
        fi
        echo "  ssh -o \"StrictHostKeyChecking no\" -l $SCS_RemoteUser $HVIP \"chattr +i ${HVPath}/${BACKING_FOLDER}$( basename $File )\""
      else
        scslog -v "transferring to ${HV}..."
        if [ $LocalTransfer -eq 0 ]; then
          ssh_remote_command -d -q $HypervisorIP "scp ${File} $HV:${HVPath}/${BACKING_FOLDER}$( basename $File )"
        else
          srcp -t ${TMPLarge} $HypervisorIP:${File} $HVIP:${HVPath}/${BACKING_FOLDER}$( basename $File ) >/dev/null 2>&1
        fi
        ssh_remote_command -d $HVIP "chattr +i ${HVPath}/${BACKING_FOLDER}$( basename $File )"
      fi
    done

  done

  # update location
  if [ $DryRun -eq 0 ]; then
    scslog -v "redistribution completed"
    hypervisor_locate_system $NAME --all
  fi
}
function system_distribute_help { cat <<_EOF
Distribute a backing image to all enabled and available hypervisors in the same environment.

Usage: $0 system <name> --distribute [--location <name>] [--dry-run]
_EOF
}

# checks if a system is defined
#
function system_exists {
  test $# -eq 1 || return 1
  # [FORMAT:system]
  grep -qE "^$1," $CONF/system || return 1
}

# general system help
#
function system_help { cat <<_EOF
NAME

SYNOPSIS
	scs system <value> [--audit|--check|--convert|--deploy|--deprovision|--distribute|--lock|
                            --provision|--push-build-scripts|--register-key|--release|--start-remote-build|
                            --type|--unlock|--uptime|--vars|--vm-add-disk|--vm-disks]

DESCRIPTION
	System management functions.  This section embodies the entire spirit and purpose of this tool since it directly
	manages, audits, and deploys the configured systems.

	A system is associated directly or indirectly with all other resource types.  It is the 'thing' an assembled
	configuration is deployed or installed to; it is built or managed and must be accessible from the management
	server with a root ssh key.

OPTIONS
	system <value> --audit [--no-prompt]
		Audit the generated system configuration with the deployed configuration.  This will only analyze the
		managed files and directories configured for the system (see system show <name> for a complete list).
		Both permissions and content are reviewed.  SCS will return PASS (exit code 0) if both file content
		and permissions match exactly for all managed files.  SCS will return FAIL (exit code 1) if any file
		differs from the generated value.

		By default the user will be prompted to review the changes in vimdiff (y), diff (d), or skip (n).  If
		the '--no-prompt' argument is provided the no user interaction is required.

	system <value> --check [--verbose]
		Run a check against the scs configuration to ensure a valid configuration can be generated for the
		specified system.  This runs through the process of building the managed configuration files and
		filling in variables wherever they appear.  This is useful for validating that all variables are
		defined for a system in an environment.

		If the '--verbose' (or -v) option is provided then all undefined variables will be enumerated so they
		can be defined.  By default only the result of the operation is output.

	system <value> --convert [--backing] [--distribute] [--dry-run] [--force] [--network <loc-zone-alias>]
                                 [--no-prompt] [--overlay <backing_image>] [--single]
		Convert a system to a different type.  This can be a highly dangerous operation if not used with care.
		This function is mostly used by the system provisioning processes to create and manage backing images,
		but is exposed through the UI to enable automation of various management processes.

		Extreme care should be taken when change system types due to potential non-obvious dependencies.  If,
		for example, an entire environment is build on a single backing image and that backing image is
		converted to a system, all other systems will cease functioning.

		System types include:

			single	: Normal standalone virtual machine.

			backing	: Backing image.  This is a disk image that is not attached to a virtual machine
				  and designated for other system images to overlay on (using qemu).

			overlay	: A virtual machine whose primary disk image is an overlay on another image.

		--backing    : Convert TO a backing image

		--distribute : Distribute converted image to hypervisors (this is pretty much for backing images)

		--dry-run    : Do not make any actual changes, just show what would be done.

		--force      : Force execution even when some validation checks fail.

		--network    : Requires the network name; required in order to convert to overlay or single.

		--no-prmopt  : Do not confirm change.

		--overlay    : Convert TO an overlay (not implemented at this time)

		--single     : Convert TO a single (normal virtual machine)

	system <value> --deploy [--install]
		Build the configuration for a system, package in a tarball, and scp to the remote system at /root/.

		If the '--install' option is provided, automatically deploy the configuration files and permissions.

	system <value> --deprovision [--dry-run] [--yes-i-am-sure]
		Delete a deployed virtual-machine.  If it is running it is immediately destroyed and the permanently
		removed.  This action should be used with extreme care.

		The '--dry-run' option will execute without making any changes to the remote system.

		The '--yes-i-am-sure' will bypass confirmation of the action.  This is very dangerous but useful for
		scripting.

	system <value> --distribute [--dry-run] [--hypervisor "<name1> <name2> ..."] [--location <name>]
		Redistribute all attached disk images for a system to other hypervisors.  This should be used to
		copy backing images to other hosts. SCS will try to do a remote to remote (direct) copy, but that
		requires each hypervisor to have a root key set up for each other hypervisor.  If this fails then
		the disk image(s) will be copied to the local system and then copied up to each destination host.

		--dry-run    : Do not make changes, just show what would be done.

		--hypervisor : A list of configured hypervisors can be provided to copy the image TO.

		--location   : If provided, all hypervisors at the specified location will be loaded into the copy
		               copy TO list.

	system <value> --lock
		Lock a system to prevent changes.

	system <value> --provision [--distribute] [--foreground] [--hypervisor <name>] [--network <loc-zone-alias>]
		                   [--skip-distribute]
		Provision (create/install) a configured virtual machine.  By default a hypervisor will be
		automatically selected (if possible).  If the system is configured to be an overlay and the overlay
		is not provisioned or is set to auto an overlay will be automatically built and/or selected as
		needed.

		--distribute : Automatically redistribute the built vm (useful for backing images) to other
		               configured hypervisors at the same location after it is built

		--foreground : Normally the provisioning process will detach and run in the background after all
		               settings and configuration have been validated.  This option will keep the process
		               in the foreground.  This can be useful for scripting.

		--hypervisor : Force deployment on the specified hypervisor.  The hypervisor must be registered
		               and enabled.  If this option is not specified a hypervisor will be chosen
		               automatically for those available at the location and environment the system being
		               deployed to.

		--network    : If the system IP is set to auto the user will be prompted to provide the network
		               in order for the IP to be automatically selected.  The network can be specified
		               from the command line with this option to avoid the prompt.

		--skip-distribute : If the build VM was to be automatically distributed to other hypervisors after
		                    it is built, bypass and do not distribute it.

	system <value> --push-build-scripts [/path/to/scripts]
		Copy the system build scripts to the remote server.  By default they are pulled from the local
		system at /home/wstrucke/ESG/system-builds.  The path to the scripts can be provided as an
		argument if necessary or desired.  This function is called automatically during the system
		provision process.

	system <value> --register-key [--sudo <name>] <user> </path/to/private_key>
		Register an existing public/private key pair for key-based authentication to a remote system under
		the specified user account.  You must have the password and authorization to log in to the remote
		server.

		If --sudo is provided, log into the system as <sudo_user> and use the provided password (you will
		be prompted for it) to elevate privileges to access the target account.

	system <value> --release
		Generate the release (configuration) in a tarball for the specified system.  The release is copied
		to the scs release directory.

	system <value> --start-remote-build <current_ip> [<role>]
		Executes the system build scripts on the remote system at the provided IP address.  If a role is
		provided it will be added as an argument to the role script.  The remote system will be instructed
		to shut itself off after running the build.  This function is called during the system provision
		process.

		The build scripts are called at 'ESG/system-builds/role.sh' on the remote system.

	system <value> --type
		Outputs the known type of the configured system, one of 'physical', 'backing', 'single', or
		'overlay'.

	system <value> --unlock
		Unlock a system to allow changes.

	system <value> --uptime
		Connect to the remote system and run 'uptime'. This is purely diagnostic.

	system <value> --vars
		Assemble the complete list of variables defined for the system.  This is exactly what is compiled
		on demand anytime a system configuration is built and can be referenced to identify what settings
		are available.

	system <value> --vm-add-disk [--alias <name>] [--backing </path/to/name.img>] [--disk </path/to/disk.img>] [--use-existing] [--hypervisor <name>] [--size <size_in_gb>] [--type <type>] [--destroy] [--dry-run]
		Create a new disk on the hypervisor for a system and attach it (or attach an existing disk). This
		function is called automatically by the system provision process for an overlay when the backing
		system also has multiple disk images.

		--alias   : Provide an alias for the disk image.  This is only used on the hypervisor file system
		            as a component of the new image file name. (i.e. 'system.alias.img')

		--backing : Specify an existing backing image for the new system.  If a backing image is specified
		            then the disk size argument is ignored (since it must match the backing imge).

		--disk    : Path to store the disk image at.  If an image exists at this location and use-existing
		            or destroy is not specified then this will generate an error and fail.

		--use-existing : When a disk image is provided (or inferred) and the image already exists, do not
		                 overwrite and just attach it as-is to the system.

		--hypervisor : Specify the hypervisor to connect to for this operation.  If this argument is not
		               provided then the hypervisor will be determined automatically.

		--size    : Size in GB of the created disk image.  The image will be thin-provisioned.

		--type    : Override the default type of image to create.  Valid options include:
		            'ide', 'scsi', 'usb', 'virtio', and 'xen'.

		--destroy : If a disk image exists at the generated or specified path, remove it first.  Use with
		            caution.

		--dry-run : Do not make any changes, just output what would be done.

	system <value> --vm-disks
		Connect to the hypervisor for the system and list all configured disk images.

EXAMPLES

RETURN CODE
	scs returns 0 on success and non-zero on error.

AUTHOR
	William Strucke <wstrucke@gmail.com>

COPYRIGHT
	Copyright © 2014 William Strucke. License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.
	This is free software: you are free to change and redistribute it.  There is NO WARRANTY, to the extent permitted by law.

SEE ALSO
	$0 help
_EOF
}

# lock a system to prevent changes
#
function system_lock {
  system_exists $1 || return 1
  start_modify
  # [FORMAT:system]
  perl -i -pe "s/^($1,)(([^,]*,){7})[^,]*,(.*)/\\1\\2y,\\4/" ${CONF}/system
  if [[ $? -ne 0 ]]; then err "Error updating configuration"; fi
  echo "$1 locked"
  commit_file system
}

# get the parent of a system
#
function system_parent {
  local NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemBuildDate SystemLock
  # [FORMAT:system]
  IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$1," ${CONF}/system )"
  printf -- "$OVERLAY\n"
  test -z "$OVERLAY" && return 1 || return 0
}

# create a system
#
# optional:
#  --network <name>
#  --[skip-]distribute
#  --foreground          # stay in the foreground instead of launching a background process
#  --hypervisor <name>   # bypass auto-selection of a hypervisor for the build
#
function system_provision {
  local NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY REDIST NETNAME NETMASK \
        GATEWAY DNS REPO_ADDR REPO_PATH REPO_URL LIST BackingList SystemBuildDate \
        BuildParent BUILDNET VMPath Foreground=0 Hypervisor OS ARCH DISK RAM PARENT \
        HV_FINAL_INT HV_BUILD_INT SystemLock

  # abort handler
  test -f $ABORTFILE && err "Abort file in place - please remove $ABORTFILE to continue."

  # select and validate the system
  generic_choose system "$1" C && shift

  # phase handler
  while [ $# -gt 0 ]; do case "$1" in
    --distribute)       REDIST=y;;
    --foreground)       Foreground=1;;
    --hypervisor)       Hypervisor="$2"; shift;;
    --network)          NETNAME="$2"; shift;;
    --phase-2)          exec 1>>$SCS_Background_Log 2>&1; system_provision_phase2 $C ${@:2}; return;;
    --skip-distribute)  REDIST=n;;
    *)                  err "Invalid argument";;
  esac; shift; done

  # [FORMAT:system]
  IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$C," ${CONF}/system )"

  # check lock
  if [[ "$SystemLock" != "n" ]]; then err "System locked; please unlock to make changes"; fi

  #  - verify system is not already deployed
  if [ "$( hypervisor_locate_system $NAME )" != "" ]; then err "Error: $NAME is already deployed. Please deprovision or clean up the hypervisors. Use 'scs hypervisor --locate-system $NAME' for more details."; fi

  # verify hypervisor
  if ! [ -z "$Hypervisor" ]; then hypervisor_exists $Hypervisor || err "Invalid hypervisor specified"; fi

  scslog "system build requested for $NAME"

  # check redistribute
  if [[ -z "$REDIST" && "$BASE_IMAGE" == "y" ]]; then get_yn REDIST "Would you like to automatically distribute the built image to other active hypervisors (y/n)?"; else REDIST=n; fi

  if [ "$IP" != "dhcp" ]; then
    # verify the system's IP is not in use
    network_ip_check $IP $NAME || err "System is alive; will not redeploy."
    #  - look up the network for this IP
    NETNAME=$( network_list --match $IP )
    test -z "$NETNAME" && err "No network was found matching this system's IP address"
  elif ! [ -z "$NETNAME" ]; then
    network_exists "$NETNAME" || err "Invalid network"
  else
    network_list
    printf -- "\n"
    get_input NETNAME "Network (loc-zone-alias)"
    printf -- "\n"
    network_exists "$NETNAME" || err "Missing network or invalid format. Please ensure you are entering 'location-zone-alias'."
  fi

  #  - lookup the build network for this system
  network_list --build $LOC |grep -E '^available' | grep -qE " $NETNAME( |\$)"
  if [ $? -eq 0 ]; then
    BUILDNET=$NETNAME
  else
    BUILDNET=$( network_list --build $LOC |grep -E '^default' |awk '{print $2}' )
  fi
  scslog "build network: $BUILDNET"

  if [ -z "$OVERLAY" ]; then
    # this is a single or backing system build (not overlay)

    #  - lookup network details for the build network (used in the kickstart configuration)
    #   --format: location,zone,alias,network,mask,cidr,gateway_ip,static_routes,dns_ip,vlan,description,repo_address,repo_fs_path,repo_path_url,build,default-build,ntp_ip\n
    # [FORMAT:network]
    read -r NETMASK GATEWAY DNS REPO_ADDR REPO_PATH REPO_URL <<< "$( grep -E "^${BUILDNET//-/,}," ${CONF}/network |awk 'BEGIN{FS=","}{print $5,$7,$9,$12,$13,$14}' )"
    valid_ip $GATEWAY || err "Build network does not have a defined gateway address"
    valid_ip $DNS || err "Build network does not have a defined DNS server"
    valid_mask $NETMASK || err "Build network does not have a valid network mask"
    if [[ -z "$REPO_ADDR" || -z "$REPO_PATH" || -z "$REPO_URL" ]]; then err "Build network does not have a valid repository configured ($BUILDNET)"; fi

    if [ -z "$Hypervisor" ]; then
      scslog "locating hypervisor"
      #  - locate available HVs
      LIST=$( hypervisor_list --network $NETNAME --network $BUILDNET --location $LOC --environment $EN --enabled | tr '\n' ' ' )
      test -z "$LIST" && err "There are no configured hypervisors capable of building this system"

      #  - poll list of HVs for availability then rank for free storage, free mem, and load
      Hypervisor=$( hypervisor_rank --avoid $( printf -- $NAME |perl -pe 's/[0-9]+[abv]*$//' ) $LIST )
      test -z "$Hypervisor" && err "There are no available hypervisors at this time"
    fi
    scslog "selected $Hypervisor"

  else

    # this is an overlay build
    if [ "$OVERLAY" == "auto" ]; then system_resolve_autooverlay $NAME; fi

    # [FORMAT:system]
    IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$NAME," ${CONF}/system )"

    # must set these values since they are passed to phase2 (not used for overlays so the value can be anything without a space)
    REPO_ADDR="-"; REPO_PATH="-"

    if [ -z "$Hypervisor" ]; then
      # list hypervisors capable of hosting this system
      # -- if none, build it ?
      LIST=$( hypervisor_list --network $NETNAME --network $BUILDNET --location $LOC --environment $EN --backing $OVERLAY --enabled | tr '\n' ' ' )

      if [ -z "$LIST" ]; then
        # no hypervisors were found matching the specified criteria.  check if some match with all *except* overlay AND if the overlay system
        #   does not exist than just ignore and continue since the entire chain can be built later
        LIST=$( hypervisor_list --backing $OVERLAY --enabled | tr '\n' ' ' )
        test ! -z "$LIST" && err "The selected backing image '$OVERLAY' is built and deployed to set of hypervisors that does not intersect with those otherwise capable of building this server.  Please copy the overlay or select a different backing image."

        LIST=$( hypervisor_list --network $NETNAME --network $BUILDNET --location $LOC --environment $EN --enabled | tr '\n' ' ' )
        test -z "$LIST" && err "There are no configured hypervisors capable of building this system"
      fi

      #  - poll list of HVs for availability then rank for free storage, free mem, and load
      Hypervisor=$( hypervisor_rank --avoid $( printf -- $NAME |perl -pe 's/[0-9]+[abv]*$//' ) $LIST )
      test -z "$Hypervisor" && err "There are no available hypervisors at this time"
    fi

  fi

  #  - get the build and dest interfaces on the hypervisor
  # [FORMAT:hv-network]
  HV_BUILD_INT=$( grep -E "^$BUILDNET,$Hypervisor," ${CONF}/hv-network |perl -pe 's/^[^,]*,[^,]*,//' )
  HV_FINAL_INT=$( grep -E "^$NETNAME,$Hypervisor," ${CONF}/hv-network |perl -pe 's/^[^,]*,[^,]*,//' )
  [[ -z "$HV_BUILD_INT" || -z "$HV_FINAL_INT" ]] && err "Selected hypervisor '$Hypervisor' is missing one or more interface mappings for the selected networks."

  # get the hypervisor vmpath
  # [FORMAT:hypervisor]
  read -r VMPath <<< "$( grep -E "^$Hypervisor," ${CONF}/hypervisor |awk 'BEGIN{FS=","}{print $4}' )"

  # verify configuration
  scslog "generating system release"
  system_release $NAME >/dev/null 2>&1 || err "Error generating release, please correct missing variables or configuration files required for deployment"
  scslog "release generated successfully"
#  FILE=$( system_release $NAME |tail -n1 )
#  test -s "$FILE" || err "Error generating release, please correct missing variables or configuration files required for deployment"

  echo "obtaining write lock..." >>$SCS_Background_Log
  start_modify
  echo "success" >>$SCS_Background_Log

  #  - assign a temporary IP as needed
  if [[ "$NETNAME" != "$BUILDNET" || "$IP" == "dhcp" ]]; then
    echo "attempting to assign a build address in network '$BUILDNET'" >>$SCS_Background_Log

    BUILDIP=""
    while [ -z "$BUILDIP" ]; do
      echo "(loop) 0 check_abort" >>$SCS_Background_Log
      check_abort
      echo "(loop) 0 network_ip_list_available \"$BUILDNET\" --limit 1" >>$SCS_Background_Log
      BUILDIP=$( network_ip_list_available "$BUILDNET" --limit 1 )
      echo "(loop) 1 ip=$BUILDIP" >>$SCS_Background_Log
      if [ $( exit_status valid_ip "$BUILDIP" ) -ne 0 ]; then BUILDIP=""; continue; fi
      echo "(loop) 2 ip=$BUILDIP" >>$SCS_Background_Log
      # verify the build IP is not in use
      if [ $( exit_status network_ip_check "$BUILDIP" "$NAME" ) -ne 0 ]; then BUILDIP=""; continue; fi
      echo "(loop) 3 ip=$BUILDIP name=$NAME" >>$SCS_Background_Log
    done

    # assign/reserve IP
    echo "calling network_ip_assign $BUILDIP $NAME" >>$SCS_Background_Log
    network_ip_assign $BUILDIP $NAME || errlog "Unable to assign IP address"

    echo "assigned $BUILDIP to $NAME" >>$SCS_Background_Log
  else
    BUILDIP=$IP
    echo "set buildip=$BUILDIP" >>$SCS_Background_Log
  fi

  #  - load the architecture and operating system for the build
  scslog "reading system architecture and build information"
  # [FORMAT:build]
  IFS="," read -r OS ARCH DISK RAM PARENT <<< "$( grep -E "^$BUILD," ${CONF}/build |perl -pe 's/^[^,]*,[^,]*,[^,]*,//' )"
  ROOT=$( build_root $BUILD )
  # [FORMAT:build]
  IFS="," read -r OS ARCH RDISK RRAM RP <<< "$( grep -E "^$ROOT," ${CONF}/build |perl -pe 's/^[^,]*,[^,]*,[^,]*,//' )"
  test -z "$OS" && err "Error loading build"

  scslog "prior to validation, using build $BUILD for system $NAME - assigned ram '$RAM' and disk '$DISK'"

  # set disk/ram
  if [ -z "$DISK" ]; then DISK=$RDISK; fi
  if [ -z "$RAM" ]; then RAM=$RRAM; fi

  #  - get disk size and memory
  test -z "$DISK" && DISK=$DEF_HDD
  test -z "$RAM" && RAM=$DEF_MEM

  scslog "following validation for $NAME - assigned ram '$RAM' and disk '$DISK'"

  #  - get globally unique mac address and uuid for the new server
  read -r UUID MAC <<< "$( hypervisor_qemu_uuid -q |perl -pe 's/^[^:]*: //' |tr '\n' ' ' )"

  if [ -z "$OVERLAY" ]; then
    # this is a single or backing system build (not overlay)

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

    echo "Using build server at '$REPO_ADDR' for system $NAME@$BUILDIP in $BUILDNET" >>$SCS_Background_Log
    parse_template ${TMP}/${NAME}.cfg ${TMP}/${NAME}.const

    # hotfix for centos 5 -- this is the only package difference between i386 and x86_64
    if [[ "$OS" == "centos5" && "$ARCH" == "x86_64" ]]; then perl -i -pe "s/kernel-PAE/kernel/" ${TMP}/${NAME}.cfg; fi
    #  - send custom kickstart file over to the local sm-web repo/mirror
    ssh_remote_command -d -n -q $REPO_ADDR "mkdir -p $REPO_PATH"
    scp -i $SCS_KeyFile -B ${TMP}/${NAME}.cfg $SCS_RemoteUser@$REPO_ADDR:$REPO_PATH/ >/dev/null 2>&1 || err "Unable to transfer kickstart configuration to build server ($REPO_ADDR:$REPO_PATH/${NAME}.cfg)"
    KS="http://${REPO_ADDR}/${REPO_URL}/${NAME}.cfg"

    #  - kick off provision system
    echo "Creating virtual machine..."
    scslog "starting system build for $NAME on $Hypervisor at $BUILDIP"
    scslog "Creating VM on $Hypervisor: /usr/local/utils/kvm-install.sh --arch $ARCH --disk $DISK --ip ${BUILDIP}/${NETMASK} --gateway $GATEWAY --dns $DNS --interface $HV_BUILD_INT --no-console --no-reboot --os $OS --quiet --ram $RAM --mac $MAC --uuid $UUID --ks $KS $NAME"
    ssh_remote_command -d -n $Hypervisor "/usr/local/utils/kvm-install.sh --arch $ARCH --disk $DISK --ip ${BUILDIP}/${NETMASK} --gateway $GATEWAY --dns $DNS --interface $HV_BUILD_INT --no-console --no-reboot --os $OS --quiet --ram $RAM --mac $MAC --uuid $UUID --ks $KS $NAME"
    if [ $? -ne 0 ]; then
      echo ssh -n -l $SCS_RemoteUser $Hypervisor "/usr/local/utils/kvm-install.sh --arch $ARCH --disk $DISK --ip ${BUILDIP}/${NETMASK} --gateway $GATEWAY --dns $DNS --interface $HV_BUILD_INT --no-console --no-reboot --os $OS --quiet --ram $RAM --mac $MAC --uuid $UUID --ks $KS $NAME"
      err "Error creating VM!"
    fi

    #  - update hypervisor-system map
    hypervisor_locate_system $NAME >/dev/null 2>&1

  fi

  # clear any host entry
  purge_known_hosts --name "$NAME" --ip "$IP"
  purge_known_hosts --ip "$BUILDIP"

  if [ $Foreground -eq 0 ]; then
    #  - background task to monitor deployment (try to connect nc, sleep until connected, max wait of 3600s)
    nohup $0 --config "${CONF}" system $NAME --provision --phase-2 "$Hypervisor" "$BUILDIP" "$HV_BUILD_INT" "$HV_FINAL_INT" "$BUILDNET" "$NETNAME" "$REPO_ADDR" "$REPO_PATH" "$REDIST" "$ARCH" "$DISK" "$OS" "$RAM" "$MAC" "$UUID" </dev/null >/dev/null 2>&1 &
  else
    scslog "starting phase 2 in foreground process"
    echo "system_provision_phase2 \"$NAME\" \"$Hypervisor\" \"$BUILDIP\" \"$HV_BUILD_INT\" \"$HV_FINAL_INT\" \
         \"$BUILDNET\" \"$NETNAME\" \"$REPO_ADDR\" \"$REPO_PATH\" \"$REDIST\" \"$ARCH\" \"$DISK\" \"$OS\" \
         \"$RAM\" \"$MAC\" \"$UUID\"" >&2
    system_provision_phase2 "$NAME" "$Hypervisor" "$BUILDIP" "$HV_BUILD_INT" "$HV_FINAL_INT" "$BUILDNET" "$NETNAME" "$REPO_ADDR" "$REPO_PATH" "$REDIST" "$ARCH" "$DISK" "$OS" "$RAM" "$MAC" "$UUID"
  fi

  #  - phase 1 complete
  scslog "build phase 1 complete"
  echo "Build for $NAME at $LOC $EN has been started successfully and will continue in the background."

  # update last build date
  # [FORMAT:system]
  IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$NAME," ${CONF}/system )"

  # [FORMAT:system]
  perl -i -pe "s/^$NAME,.*/${NAME},${BUILD},${IP},${LOC},${EN},${VIRTUAL},${BASE_IMAGE},${OVERLAY},${SystemLock},$( date +'%s' )/" ${CONF}/system

  commit_file system
  return 0
}
function system_provision_help { cat <<_EOF
Instantiate a virtual machine or base image for a defined system.

Usage: $0 system <name> --provision [--network <name>] [--[skip-]distribute]

Fields:
  <name>		Name of the defined system
  --network <name>	optional name of the network to deploy to - this is only useful for systems
			  configured to use DHCP since the user will be prompted for a network in order
			  to auto-assign an IP address
  --distribute		optional - for base images, answers 'yes' to distribute the image to all hypervisors
  --skip-distribute	optional - for base images, answers 'no' to distribute the image to all hypervisors

_EOF
}


# build phase 2
#
function system_provision_phase2 {
  local NAME HV BUILDIP HV_BUILD_INT HV_FINAL_INT BUILDNET NETNAME REPO_ADDR \
        REPO_PATH REDIST SystemBuildDate BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY \
        HVIP VMPATH DHCP ARCH DISK OS RAM MAC UUID DHCPIP NETMASK GATEWAY DNS List File \
        SystemLock

  # load arguments passed in from phase1
  echo "Args: $@" >&2
  read -r NAME HV BUILDIP HV_BUILD_INT HV_FINAL_INT BUILDNET NETNAME REPO_ADDR REPO_PATH REDIST ARCH DISK OS RAM MAC UUID <<< "$@"

  # [FORMAT:system]
  IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$NAME," ${CONF}/system )"
  system_exists $NAME
  if [ $? -ne 0 ]; then errlog "error staring build phase 2 - system '$NAME' does not exist - check $HV"; exit 1; fi

  # [FORMAT:hypervisor]
  read -r HVIP VMPATH <<< "$( grep -E "^$HV," ${CONF}/hypervisor |awk 'BEGIN{FS=","}{print $2,$4}' )"

  # [FORMAT:network]
  DHCP=$( network_show $BUILDNET 2>/dev/null |grep DHCP |awk '{print $3}' )
  if ! [ -z "$DHCP" ]; then valid_ip $DHCP || err "Invalid DHCP server"; fi

  scslog "starting build phase 2 for $NAME on $HV ($HVIP) at $BUILDIP"

  if ! [ -z "$OVERLAY" ]; then
    # this is an overlay system

    #  - lookup network details for the build network (used in the kickstart configuration)
    #   --format: location,zone,alias,network,mask,cidr,gateway_ip,static_routes,dns_ip,vlan,description,repo_address,repo_fs_path,repo_path_url,build,default-build,ntp_ip\n
    # [FORMAT:network]
    read -r NETMASK GATEWAY DNS <<< "$( grep -E "^${BUILDNET//-/,}," ${CONF}/network |awk 'BEGIN{FS=","}{print $5,$7,$9}' )"
    valid_ip $GATEWAY || errlog "Build network does not have a defined gateway address"
    valid_ip $DNS || errlog "Build network does not have a defined DNS server"
    valid_mask $NETMASK || errlog "Build network does not have a valid network mask"

    # build the parent system as needed
    hypervisor_locate_system $OVERLAY >/dev/null 2>&1

    if [ $? -ne 0 ]; then
      if [ "$REDIST" == "y" ]; then
        system_provision $OVERLAY --network $BUILDNET --distribute --foreground --hypervisor $HV
      else
        system_provision $OVERLAY --network $BUILDNET --skip-distribute --foreground --hypervisor $HV
      fi
    fi

    scslog "ok, getting around to building the overlay for $NAME - assigned ram '$RAM' and disk '$DISK' - this should match the earlier value"

    #  - kick off provision system
    scslog "starting system build for $NAME on $HV at $BUILDIP"
    echo "Creating virtual machine..."
    scslog "Creating VM on $HV: /usr/local/utils/kvm-install.sh --arch $ARCH --ip ${BUILDIP}/${NETMASK} \
            --gateway $GATEWAY --dns $DNS --interface $HV_BUILD_INT --no-console --no-reboot --os $OS \
            --quiet --ram $RAM --mac $MAC --uuid $UUID --no-install --base ${VMPATH}/${BACKING_FOLDER}${OVERLAY}.img $NAME"

    ssh_remote_command -d -n $HV "/usr/local/utils/kvm-install.sh --arch $ARCH --ip ${BUILDIP}/${NETMASK} --gateway $GATEWAY --dns $DNS --interface $HV_BUILD_INT --no-console --no-reboot --os $OS --quiet --ram $RAM --mac $MAC --uuid $UUID --no-install --base ${VMPATH}/${BACKING_FOLDER}${OVERLAY}.img $NAME"
    if [ $? -ne 0 ]; then
      echo ssh -n -l $SCS_RemoteUser $HV "/usr/local/utils/kvm-install.sh --arch $ARCH --ip ${BUILDIP}/${NETMASK} \
           --gateway $GATEWAY --dns $DNS --interface $HV_BUILD_INT --no-console --no-reboot --os $OS \
           --ram $RAM --mac $MAC --uuid $UUID --no-install --base ${VMPATH}/${BACKING_FOLDER}${OVERLAY}.img $NAME"
      err "Error creating VM!"
    fi

    # check for secondary disks
    List="$( ssh_remote_command -d $HV "ls ${VMPATH}/${BACKING_FOLDER}${OVERLAY}.*img" )"
    for File in $List; do
      if [ "$File" == "${VMPATH}/${BACKING_FOLDER}${OVERLAY}.img" ]; then continue; fi
      system_vm_disk_create $NAME --alias "$( printf -- "$( basename $File )" |perl -pe 's/^'${OVERLAY}'\.//; s/\.img$//' )" --backing $File
      if [ $? -eq 0 ]; then scslog "successfully added secondary disk to $NAME using backing image $( basename $File )"; else scslog "error adding secondary disk to $NAME using backing image $( basename $File )"; fi
    done

    # start new virtual machine
    ssh_remote_command -d -n -q $HV "virsh start $NAME"

    if ! [ -z "$DHCP" ]; then

      DHCPIP=""
      scslog "attempting to trace DHCP IP"
      echo "ssh -l $SCS_RemoteUser $DHCP cat /var/lib/dhcpd/dhcpd.leases |grep -avE '^(#|\$)' |grep -av server-duid |tr '\\n' ' ' |perl -pe 's/}/}\\n/g' |grep -ai "$MAC" |awk '{print \$2}' |tail -n1" >>$SCS_Background_Log

      # get DHCP lease
      while [ -z "$DHCPIP" ]; do
        check_abort
        sleep 5
        DHCPIP="$( ssh_remote_command -d $DHCP cat /var/lib/dhcpd/dhcpd.leases |grep -avE '^(#|$)' |grep -av server-duid |tr '\n' ' ' |perl -pe 's/}/}\n/g' |grep -ai "$MAC" |awk '{print $2}' |tail -n1 )"
	if [[ -n "$DHCPIP" && "$( exit_status valid_ip "$DHCPIP" )" -ne 0 ]]; then
          errlog "found an invalid IP address in /var/lib/dhcpd/dhcpd.leases on server $DHCP for physical address $MAC, aborting"
        fi
      done

      if ! [ -z "$DHCPIP" ]; then
        purge_known_hosts --ip $DHCPIP
        DHCPNETNAME=$( network_ip_locate $BUILDIP )
        # [FORMAT:network]
        read DHCPCIDR <<< "$( grep -E "^${DHCPNETNAME//-/,}," ${CONF}/network |awk 'BEGIN{FS=","}{print $6}' )"
        scslog "found DHCP address '$DHCPIP' for system with physical address '$MAC'"
        while [ "$( exit_status check_host_alive $DHCPIP )" -ne 0 ]; do sleep 5; check_abort; done
        while [ "$( exit_status ssh_remote_command -d -n $DHCPIP uptime )" -ne 0 ]; do sleep 5; check_abort; done
        ssh_remote_command -d -n -q $DHCPIP "ESG/system-builds/install.sh configure-system --ip ${BUILDIP}/${DHCPCIDR} --skip-restart >/dev/null 2>&1; halt"
        scslog "successfully moved system to assigned build address"
      fi
    fi
  fi

  # wait a moment before even trying to connect
  sleep 15

  #  - connect to hypervisor, wait until vm is off, then start it up again
  ssh_remote_command -d -n -q $HVIP "while [ \"\$( /usr/bin/virsh dominfo $NAME |grep -i state |grep -i running |wc -l |awk '{print \$1}' )\" -gt 0 ]; do sleep 5; done; sleep 5; /usr/bin/virsh start $NAME"
  scslog "successfully started $NAME"

  #  - check for abort
  check_abort

  #  - wait for vm to come up
  sleep 15
  scslog "waiting for $NAME at $BUILDIP"
  while [ "$( exit_status check_host_alive $BUILDIP )" -ne 0 ]; do sleep 5; check_abort; done
  scslog "ssh connection succeeded to $NAME"
  while [ "$( exit_status ssh_remote_command -d -n $BUILDIP uptime )" -ne 0 ]; do sleep 5; check_abort; done
  scslog "$NAME verified UP"

  #  - load the role
  # [FORMAT:build]
  ROLE=$( grep -E "^$BUILD," ${CONF}/build |awk 'BEGIN{FS=","}{print $2}' )

  #  - install_build
  system_push_build_scripts $BUILDIP >/dev/null 2>&1 || errlog "Error pushing build scripts to remote server $NAME at $IP"
  scslog "build scripts deployed to $NAME"

  #  - sysbuild_install (do not change the IP here)
  system_start_remote_build $NAME $BUILDIP $ROLE >/dev/null 2>&1 || errlog "Error starting remote build on $NAME at $IP"
  scslog "started remote build"

  if [ -z "$OVERLAY" ]; then
    #  - clean up kickstart file
    check_host_alive $REPO_ADDR
    [ $? -eq 0 ] && ssh_remote_command -d -q $REPO_ADDR "rm -f ${REPO_PATH}/${NAME}.cfg"
  fi

  #  - connect to hypervisor, wait until vm is off, then start it up again
  ssh_remote_command -d -n -q $HV "while [ \"\$( /usr/bin/virsh dominfo $NAME |grep -i state |grep -i running |wc -l |awk '{print \$1}' )\" -gt 0 ]; do sleep 5; done; sleep 5; /usr/bin/virsh start $NAME"
  scslog "successfully started $NAME"

  #  - check for abort
  check_abort

  #  - wait for vm to come up
  sleep 15
  while [ "$( exit_status check_host_alive $BUILDIP )" -ne 0 ]; do sleep 5; check_abort; done
  scslog "ssh connection succeeded to $NAME"
  purge_known_hosts --ip $BUILDIP
  while [ "$( exit_status ssh_remote_command -d -n $BUILDIP uptime )" -ne 0 ]; do sleep 5; check_abort; done
  scslog "$NAME verified UP"

  # deploy system configuration
  scslog "generating release..."
  FILE=$( system_release $NAME 2>/dev/null |tail -n1 )
  if [ -z "$FILE" ]; then errlog "Error generating release for '$NAME'"; return 1; fi
  if ! [ -f "$FILE" ]; then errlog "Unable to read release file for '$NAME'"; return 1; fi
  scslog "copying release to remote system..."
  scp -i $SCS_KeyFile -q -o "StrictHostKeyChecking no" $FILE $SCS_RemoteUser@$BUILDIP: >/dev/null 2>&1
  if [ $? -ne 0 ]; then errlog "Error copying release to '$NAME'@$BUILDIP"; return 1; fi
  rm -f $FILE
  ssh_remote_command -d -n -q $BUILDIP "/bin/bash /root/$( basename $FILE ) --install"

  # !!FIXME!!
  #  * - ship over latest code release
  #  - install code

  #  - check for abort
  check_abort

  # update system ip as needed
  if [ "$BUILDIP" != "$IP" ]; then
    scslog "Changing $NAME system IP from $BUILDIP to $IP (not applying yet)"
    if [ "$IP" != "dhcp" ]; then
      local CIDR NETNAME=$( network_ip_locate $IP )
      # [FORMAT:network]
      read CIDR <<< "$( grep -E "^${NETNAME//-/,}," ${CONF}/network |awk 'BEGIN{FS=","}{print $6}' )"
      ssh_remote_command -d -n -q $BUILDIP "ESG/system-builds/install.sh configure-system --ip ${IP}/${CIDR} --skip-restart >/dev/null 2>&1"
    else
      ssh_remote_command -d -n -q $BUILDIP "ESG/system-builds/install.sh configure-system --ip dhcp --skip-restart >/dev/null 2>&1"
    fi
    sleep 5
    # update ip assignment
    scslog "Updating IP assignments"
    network_ip_unassign $BUILDIP >/dev/null 2>&1
    if [ "$IP" != "dhcp" ]; then network_ip_assign $IP $NAME --force >/dev/null 2>&1; fi
    purge_known_hosts --ip $BUILDIP
    purge_known_hosts --name $NAME --ip $IP
  fi

  if [ "$BASE_IMAGE" == "y" ]; then
    # flush hardware address, ssh host keys, and device mappings to anonymize system
    ssh_remote_command -d -n -q $BUILDIP "ESG/system-builds/install.sh configure-system --flush >/dev/null 2>&1; halt"
  else
    # power down vm
    ssh_remote_command -d -n -q $BUILDIP "halt"
  fi

  # wait for power off
  ssh_remote_command -d -n -q $HVIP "while [ \"\$( /usr/bin/virsh dominfo $NAME |grep -i state |grep -i running |wc -l |awk '{print \$1}' )\" -gt 0 ]; do sleep 5; done"
  scslog "successfully stopped $NAME"

  #  - check for abort
  check_abort

  # update build interface as needed
  if [ "$HV_BUILD_INT" != "$HV_FINAL_INT" ]; then
    scslog "changing system network interface from '$HV_BUILD_INT' to '$HV_FINAL_INT'"
    echo "ssh -n -l $SCS_RemoteUser $HVIP \"sed -e 's/'$HV_BUILD_INT'/'$HV_FINAL_INT'/g' -i /etc/libvirt/qemu/${NAME}.xml; virsh define /etc/libvirt/qemu/${NAME}.xml\"" >>$SCS_Background_Log
    ssh_remote_command -d -n -q $HVIP "sed -e 's/'$HV_BUILD_INT'/'$HV_FINAL_INT'/g' -i /etc/libvirt/qemu/${NAME}.xml; virsh define /etc/libvirt/qemu/${NAME}.xml"
  fi

  if [ "$BASE_IMAGE" != "y" ]; then
    #  - start vm
    scslog "starting $NAME on $HV"
    ssh_remote_command -d -n -q $HVIP "virsh start $NAME"

    if [ "$IP" != "dhcp" ]; then
      #  - update /etc/hosts and push-hosts (system_update_push_hosts)
      scslog "updating hosts"
      system_update_push_hosts $NAME $IP >>$SCS_Background_Log 2>&1
      scslog "hosts updated"

      #  - wait for vm to come up
      sleep 15
      while [ "$( exit_status check_host_alive $IP )" -ne 0 ]; do sleep 5; check_abort; done
      scslog "ssh connection succeeded to $NAME"
      while [ "$( exit_status ssh_remote_command -d -n $IP uptime )" -ne 0 ]; do sleep 5; check_abort; done
      scslog "$NAME verified UP"
    else
      scslog "$NAME is configured to use DHCP and can not be traced at this time"
    fi
  else

    # this is a base_image - move built image file, deploy to other HVs (as needed), and undefine system
    scslog "converting VM to backing image"

    if [ "$REDIST" == "y" ]; then
      system_convert $NAME --backing --distribute --no-prompt --force --network $NETNAME
    else
      system_convert $NAME --backing --no-prompt --force --network $NETNAME
    fi

  fi

  scslog "**** system build complete for $NAME ****"
}

# deploy the current system build scripts to a remote server
#   this function replaces 'install_build' previously found in /root/.bashrc
#
function system_push_build_scripts {
  if [[ $# -lt 1 || $# -gt 2 ]]; then echo -e "Usage: install_build hostname|ip [path]\n"; return 1; fi
  if [ "$( whoami )" != "root" ]; then echo "You must be root"; return 2; fi
  if ! [ -z "$2" ]; then
    test -d "$2" || return 3
    SRCDIR="$2"
  else
    SRCDIR=$BUILDSRC
  fi
  test -d "$SRCDIR" || return 4
  check_host_alive $1
  if [ $? -ne 0 ]; then
    echo "Remote host did not respond to initial request; attempting to force network discovery..." >&2
    ping -c 2 -q $1 >/dev/null 2>&1
    check_host_alive $1 || return 5
  fi
  cat ~/.ssh/known_hosts >~/.ssh/known_hosts.$$
  perl -i -ne "print unless /$( printf -- "$1" |perl -pe 's/\./\\./g' )/" ~/.ssh/known_hosts
  ssh_remote_command -d -n $1 mkdir ESG 2>/dev/null
  echo "running command: scp -i $SCS_KeyFile -o \"StrictHostKeyChecking no\" -p -r \"$SRCDIR\" $SCS_RemoteUser@$1:ESG/" >>$SCS_Background_Log 2>&1
  scp -i $SCS_KeyFile -o "StrictHostKeyChecking no" -p -r "$SRCDIR" $SCS_RemoteUser@$1:ESG/ >/dev/null 2>&1 || echo "Error transferring files" >&2
  cat ~/.ssh/known_hosts.$$ >~/.ssh/known_hosts
  /bin/rm ~/.ssh/known_hosts.$$
  return 0
}

# register an ssh key on a managed system
#
function system_register_key {
  local IP
  system_exists "$1" || err "Unknown or missing system name."
  if [[ $# -lt 3 && $# -gt 6 ]]; then system_register_key_help >&2; exit 1; fi
  IP=$( system_show $1 --brief |grep ^IP: |cut -d' ' -f2 )
  valid_ip $IP || err "The specified system has an invalid IP address."
  if [ $# -eq 5 ]; then
    if [ "$2" != "--sudo" ]; then system_register_key_help >&2; exit 1; fi
    if [[ "$6" == "--debug" ]]; then
      register_ssh_key --host "$IP" --sudo "$3" --user "$4" --key "$5" --debug
    else
      register_ssh_key --host "$IP" --sudo "$3" --user "$4" --key "$5"
    fi
  else
    if [[ "$4" == "--debug" ]]; then
      register_ssh_key --host "$IP" --user "$2" --key "$3" --debug
    else
      register_ssh_key --host "$IP" --user "$2" --key "$3"
    fi
  fi
}
function system_register_key_help { cat <<_EOF
Usage: $0 system <name> --register-key [--sudo <sudo_user>] <user-name> <private-key-file>

Register an existing public/private key pair for key-based authentication
to a remote system under the specified user account.  You must have
the password and authorization to log in to the remote server.

If --sudo is provided, log into the system as <sudo_user> and use
the provided password (you will be prompted for it) to elevate
privileges to access the target account.
_EOF
}

function system_resolve_autooverlay {
  local NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemBuildDate BuildParent \
        BuildGrandParent BackingList ParentName SystemLock

  system_exists $1 || err

  start_modify

  # [FORMAT:system]
  IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$1," ${CONF}/system )"

  # check lock
  if [[ "$SystemLock" != "n" ]]; then err "System locked; please unlock to make changes"; fi

  # auto-select backing image
  BackingList="$( system_list_unformatted --backing --build $BUILD --sort-by-build-date --exclude-parent $NAME --location $LOC --environment $EN |tr '\n' ' ' )"

  if [ -z "$BackingList" ]; then

    # automatically create backing systems
    BuildParent=$( build_parent $BUILD )
    BuildGrandParent=$( build_parent $BuildParent)
    ParentName="${BuildParent}_$( date +'%s' )"

    if [ -z "$BuildGrandParent" ]; then
      # this is the full build
      system_create $ParentName $BuildParent $LOC $EN dhcp y y n >/dev/null 2>&1
    else
      system_create $ParentName $BuildParent $LOC $EN dhcp y y y auto >/dev/null 2>&1
      # recursion ;)
      system_resolve_autooverlay $ParentName
    fi

  else
    ParentName=$( printf -- "$BackingList" |awk '{print $1}' )
  fi

  # save changes
  # [FORMAT:system]
  perl -i -pe "s/^$NAME,.*/${NAME},${BUILD},${IP},${LOC},${EN},${VIRTUAL},${BASE_IMAGE},${ParentName},${SystemLock},${SystemBuildDate}/" ${CONF}/system

  commit_file system
}

function system_list {
  if [[ "$1" == "--no-format" || "$1" == "-1" ]]; then shift; system_list_unformatted $@; return; fi
  local LIST NUM
  LIST="$( system_list_unformatted $@ |tr '\n' ' ' )"
  NUM=$( printf -- "$LIST" |wc -w |tr -d ' ' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined system${S}."
  test $NUM -eq 0 && return
  printf -- "$LIST\n" |tr ' ' '\n' |sort |fold_list |perl -pe 's/^/   /'
}

# system:
#   name,build,ip,location,environment,virtual,backing_image,overlay\n
#
# optional:
#   --backing                   show systems of type backing image
#   --build <string>            show systems using build <string>, or having it in the build lineage
#   --environment <string>      show systems in environment <string>
#   --exclude-parent <string>   do not show systems with parent (or inherited parent) system named <string>
#   --grep <string>             show systems matching <string>
#   --location <string>         show systems at location <string>
#   --overlay                   show systems of type overlay
#   --sort-by-build-date        sort output by build date (descending) instead of alphabetically
#
function system_list_unformatted {
  local Backing=0 Overlay=0 Build BuildList LIST N NL M SortByDate=0 System PassTests Parent

  if [ $# -eq 0 ]; then

    # [FORMAT:system]
    awk 'BEGIN{FS=","}{print $1}' ${CONF}/system
    return

  else

    LIST="$( awk 'BEGIN{FS=","}{print $1}' ${CONF}/system |tr '\n' ' ' )"

    while [ $# -gt 0 ]; do case "$1" in

      --backing)
        NL=""
        for N in $LIST; do
          # [FORMAT:system]
          grep -qE '^'$N',([^,]*,){5}y,[^,]*,.*$' ${CONF}/system && NL="$NL $N"
        done
        LIST="$NL"
        ;;

      --build)
        NL=""
        Parent="$( build_parent $2 )"
        if [[ -n $Parent ]]; then
          BuildList="$( build_lineage_unformatted $( build_parent $2 ) |awk '{print NL}' |tr ',' ' ' )"
        else
          BuildList="$2"
        fi
        for N in $LIST; do
          # [FORMAT:system]
          grep -qE '^'$N','$2',.*$' ${CONF}/system
          if [ $? -eq 0 ]; then NL="$NL $N"; else
            for M in $BuildList; do
              if [ "$M" == "$2" ]; then continue; fi
              grep -qE '^'$N','$M',.*$' ${CONF}/system
              if [ $? -eq 0 ]; then NL="$NL $N"; break; fi
            done
          fi
        done
        LIST="$NL"
        shift
        ;;

      --environment)
        NL=""
        for N in $LIST; do
          # [FORMAT:system]
          grep -qE '^'$N',([^,]*,){3}'$2',.*$' ${CONF}/system && NL="$NL $N"
        done
        LIST="$NL"
        shift
        ;;

      --exclude-parent)
        NL=""
        for N in $LIST; do
          System=$N; PassTests=1
          while ! [ -z "$System" ]; do
            if [ "$System" == "$2" ]; then PassTests=0; break; fi
            System=$( system_parent $System )
          done
          if [ $PassTests -eq 1 ]; then NL="$NL $N"; fi
        done
        LIST="$NL"
        ;;

      --grep)
        LIST="$( printf -- "$LIST" |tr ' ' '\n' |grep -i "$2" |tr '\n' ' ' )"
        shift
        ;;

      --location)
        NL=""
        for N in $LIST; do
          # [FORMAT:system]
          grep -qE '^'$N',([^,]*,){2}'$2',.*$' ${CONF}/system && NL="$NL $N"
        done
        LIST="$NL"
        shift
        ;;

      --overlay)
        NL=""
        for N in $LIST; do
          # [FORMAT:system]
          grep -qE '^'$N',([^,]*,){6}[^,]+,.*$' ${CONF}/system && NL="$NL $N"
        done
        LIST="$NL"
        ;;

      --sort-by-build-date) SortByDate=1;;

    esac; shift; done

    if [ $SortByDate -eq 0 ]; then
      for N in $LIST; do printf -- "$N\n"; done |sort
    else
      # [FORMAT:system]
      for N in $LIST; do
        grep -E "^$N," ${CONF}/system |awk 'BEGIN{FS=","}{print $1,$10}'
      done |sort -rnk2 |awk '{print $1}'
    fi

  fi
}

# generate the complete deployment archive and self-extracting installation script for a system
#
# requires:
#   $1  system name
#
function system_release {
  system_exists "$1" || err "Unknown or missing system name"
  # load the system
  local NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY FILES ROUTES FPTH SystemBuildDate \
        AllFiles HasRoutes=0 AUDITSCRIPT RELEASEFILE RELEASESCRIPT STATFILE MyDate Branch \
        SystemLock DeleteFiles
  # [FORMAT:system]
  IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$1," ${CONF}/system )"
  # create the temporary directory to store the release files
  mkdir -p $TMP/release $RELEASEDIR
  MyDate="$( date +'%Y%m%d-%H%M%S' )"
  AUDITSCRIPT="$TMP/release/scs-audit.sh"
  RELEASEFILE="$NAME-release-$MyDate.cpio.gz"
  RELEASESCRIPT="$TMP/$NAME-release-$MyDate.bsx"
  STATFILE="$TMP/release/scs-stat"
  FILES=()
  AllFiles=()
  DeleteFiles=()

  pushd $CONF >/dev/null 2>&1
  Branch=$( git branch |grep ^* |cut -d' ' -f2 )
  popd >/dev/null 2>&1

  # create the audit script
  printf -- "#!/bin/bash\n# scs audit script for $NAME [$Branch], generated on $( hostname ) at $MyDate\n#\n\n" >$AUDITSCRIPT
  printf -- "# warn if not target host\ntest \"\$( hostname )\" == \"$NAME\" || echo \"WARNING - running on alternate system - can not reliably check ownership!\"\n\n" >>$AUDITSCRIPT
  printf -- "PASS=0\n" >>$AUDITSCRIPT

  # create the installation script
  printf -- "#!/bin/bash\n# scs installation script for $NAME, generated on $( date )\n#\n\n" >$RELEASESCRIPT
  printf -- "# usage\n#\nfunction usage {\n  echo \"Usage: \$0 [--audit|--extract </path/>|--install]\"\n  exit 1\n}\n\n" >>$RELEASESCRIPT
  printf -- "# set defaults\nAudit=0\nExtract=\"\"\nInstall=0\n\n" >>$RELEASESCRIPT
  printf -- "while [[ \$# -gt 0 ]]; do case \$1 in\n  --audit) Audit=1;;\n  --extract) Extract=\"\$2\";;\n  --install) Install=1;;\nesac; shift; done\n\n" >>$RELEASESCRIPT
  printf -- "# safety first\nif [[ \"\$( hostname )\" != \"$NAME\" && -z \"\$Extract\" ]]; then exit 2; fi\n\n" >>$RELEASESCRIPT
  printf -- "# validate settings\nif [[ ( \$(( \$Audit + \$Install )) -eq 0 || \$(( \$Audit + \$Install )) -gt 1 ) && -z \"\$Extract\" ]]; then usage; fi\n" >>$RELEASESCRIPT
  printf -- "if [[ \"\$Extract\" == \"/\" ]]; then echo \"Invalid extraction path.\"; exit 1; fi\n\n" >>$RELEASESCRIPT
  printf -- "# self-extracting archive\nif [[ -n \"\$Extract\" ]]; then TMPDIR=\"\$Extract\"; else TMPDIR=/root/scs-release-$MyDate; fi\nexport TMPDIR\nmkdir -m0700 \$TMPDIR >/dev/null 2>&1\n" >>$RELEASESCRIPT
  printf -- "ARCHIVE=\$( awk '/^__PAYLOAD__/ {print NR + 1; exit 0; }' \$0 )\n\n" >>$RELEASESCRIPT

  # the script needs to know where it is to read itself
  printf -- "# get absolute path to self\npushd \$( dirname \$0 ) >/dev/null\nSCRIPTPATH=\"\$( pwd -P )/\$( basename \$0)\"\npopd >/dev/null\n\n" >>$RELEASESCRIPT

  # self-extracting archive
  printf -- "# extract\ncd \$TMPDIR\ntail -n+\$ARCHIVE \$SCRIPTPATH |gzip -dc - |cpio -idm 2>/dev/null\ncd - >/dev/null 2>&1\n" >>$RELEASESCRIPT
  printf -- "# exit here if extract only\nif [[ -n \"\$Extract\" ]]; then\n  echo \"Archive successfully extracted to \$TMPDIR\"\n  exit 0\nfi\n\n" >>$RELEASESCRIPT

  # audit only function
  printf -- "# audit option\nif [[ \$Audit -eq 1 ]]; then\n  cd /\n  /bin/bash \$TMPDIR/scs-audit.sh\n  Result=\$?\n  rm -rf \$TMPDIR\n  cd - >/dev/null 2>&1\n  exit \$Result\nfi\n\n" >>$RELEASESCRIPT

  printf -- "logger -t scs \"starting installation for ${LOC}:${EN} $NAME [$Branch], generated on $MyDate\"\n\n" >>$RELEASESCRIPT
  touch ${RELEASESCRIPT}.tail

  # create the stat file
  touch $STATFILE
  # look up the applications configured for the build assigned to this system
  if ! [ -z "$BUILD" ]; then
    # retrieve application related data
    for APP in $( build_application_list "$BUILD" ); do
      # get the file list per application
      FILES=( ${FILES[@]} $( application_file_list_unformatted $APP --environment $EN ) )
    done
  fi

  # check for static routes for this system
  ROUTES=$( network_routes_by_ip $IP )
  if [ -s "$ROUTES" ]; then
    mkdir -p $TMP/release/etc/sysconfig/
    cat $ROUTES >$TMP/release/etc/sysconfig/static-routes
    rm -f $ROUTES
    HasRoutes=1
    # audit
    FPTH=etc/sysconfig/static-routes
    printf -- "if [ -f \"$FPTH\" ]; then\n" >>$AUDITSCRIPT
    printf -- "  if [ \"\$( stat -c'%%a %%U:%%G' \"$FPTH\" )\" != \"644 root:root\" ]; then PASS=1; echo \"'\$( stat -c'%%a %%U:%%G' \"$FPTH\" )' != '644 root:root' on $FPTH\"; fi\n" >>$AUDITSCRIPT
    printf -- "else\n  echo \"Error: $FPTH does not exist!\"\n  PASS=1\nfi\n" >>$AUDITSCRIPT
    # release
    printf -- "# set permissions on 'static-routes'\nchown root:root /$FPTH\nchmod 644 /$FPTH\n" >>${RELEASESCRIPT}.tail
    # stat
    printf -- "/$FPTH root root 644 file\n" >>$STATFILE
    # backup
    AllFiles[${#AllFiles[@]}]='/etc/sysconfig/static-routes'
  fi

  # generate the variables for this system one time
  system_vars $NAME >$TMP/systemvars.$$

  # generate the release configuration files
  if [ ${#FILES[*]} -gt 0 ]; then
    for ((i=0;i<${#FILES[*]};i++)); do
      # get the file path based on the unique name
      # [FORMAT:file]
      IFS="," read -r FNAME FPTH FTYPE FOWNER FGROUP FOCTAL FTARGET FDESC <<< "$( grep -E "^${FILES[i]}," ${CONF}/file )"
      if [[ "$FTYPE" != "directory" && "$FTYPE" != "delete" ]]; then
        # add to allfiles array
        AllFiles[${#AllFiles[@]}]="$FPTH"
      fi
      # remove leading '/' to make path relative
      FPTH=$( printf -- "$FPTH" |perl -pe 's%^/%%' )
      # alternate octal representation
      FOCT=$( printf -- $FOCTAL |perl -pe 's%^0%%' )
      # skip if path is null (implies an error occurred)
      test -z "$FPTH" && continue
      # ensure the relative path (directory) exists
      mkdir -p $TMP/release/$( dirname $FPTH )
      # how the file is created differs by type
      if [ "$FTYPE" == "file" ]; then
        # generate the file for this environment
        file_cat ${FILES[i]} --environment $EN --system-vars $TMP/systemvars.$$ --silent >$TMP/release/$FPTH || err "Error generating $EN file for ${FILES[i]}"
      elif [ "$FTYPE" == "directory" ]; then
        mkdir -p $TMP/release/$FPTH
      elif [ "$FTYPE" == "symlink" ]; then
        # tar will preserve the symlink so go ahead and create it
        ln -s $FTARGET $TMP/release/$FPTH
        # special case -- symlinks always stat as 0777
        FOCT=777
      elif [ "$FTYPE" == "binary" ]; then
        # simply copy the file, if it exists
        test -f $CONF/env/$EN/binary/$FNAME || err "Error - binary file '$FNAME' does not exist for $EN."
        cat $CONF/env/$EN/binary/$FNAME >$TMP/release/$FPTH
      elif [ "$FTYPE" == "copy" ]; then
        # copy the file using scp or fail
        scp $FTARGET $TMP/release/$FPTH >/dev/null 2>&1 || err "Error - an unknown error occurred copying source file '$FTARGET'."
      elif [ "$FTYPE" == "download" ]; then
        # add download to command script
        printf -- "# download '$FNAME'\n" >>${RELEASESCRIPT}.tail
        printf -- "curl -f -k -L --retry 1 --retry-delay 10 -s --url \"$FTARGET\" -o \"/$FPTH\" >/dev/null 2>&1 || logger -t scs \"error downloading '$FNAME'\"\n" >>${RELEASESCRIPT}.tail
      elif [ "$FTYPE" == "delete" ]; then
        # add delete to command script
        printf -- "# delete '$FNAME' if it exists\n" >>${RELEASESCRIPT}.tail
        printf -- "if [[ ! -z \"$FPTH\" && \"$FPTH\" != \"/\" && -e \"/$FPTH\" ]]; then /bin/rm -rf \"/$FPTH\"; logger -t scs \"deleting path '/$FPTH'\"; fi\n" >>${RELEASESCRIPT}.tail
        # add audit check
        printf -- "if [[ ! -z \"$FPTH\" && \"$FPTH\" != \"/\" && -e \"/$FPTH\" ]]; then PASS=1; echo \"File should not exist: '/$FPTH'\"; fi\n" >>$AUDITSCRIPT
        # add to backup
        DeleteFiles[${#DeleteFiles[@]}]="$FPTH"
      fi
      # stage permissions for audit and processing
      if [ "$FTYPE" != "delete" ]; then
        # audit
        if [[ "$FTYPE" == "directory" ]]; then
          printf -- "if [ -d \"$FPTH\" ]; then\n" >>$AUDITSCRIPT
          printf -- "  if [ \"\$( stat -c'%%a %%U:%%G' \"$FPTH\" )\" != \"$FOCT $FOWNER:$FGROUP\" ]; then PASS=1; echo \"'\$( stat -c'%%a %%U:%%G' \"$FPTH\" )' != '$FOCT $FOWNER:$FGROUP' on $FPTH\"; fi\n" >>$AUDITSCRIPT
          printf -- "else\n  echo \"Error: $FPTH does not exist!\"\n  PASS=1\nfi\n" >>$AUDITSCRIPT
        elif [[ "$FTYPE" == "symlink" ]]; then
          printf -- "if [ -L \"$FPTH\" ]; then\n" >>$AUDITSCRIPT
          printf -- "  if [ \"\$( stat -c'%%a %%U:%%G' \"$FPTH\" )\" != \"$FOCT root:root\" ]; then PASS=1; echo \"'\$( stat -c'%%a %%U:%%G' \"$FPTH\" )' != '$FOCT root:root' on $FPTH\"; fi\n" >>$AUDITSCRIPT
          printf -- "else\n  echo \"Error: $FPTH does not exist!\"\n  PASS=1\nfi\n" >>$AUDITSCRIPT
        else
          printf -- "if [ -f \"$FPTH\" ]; then\n" >>$AUDITSCRIPT
          printf -- "  if [ \"\$( stat -c'%%a %%U:%%G' \"$FPTH\" )\" != \"$FOCT $FOWNER:$FGROUP\" ]; then PASS=1; echo \"'\$( stat -c'%%a %%U:%%G' \"$FPTH\" )' != '$FOCT $FOWNER:$FGROUP' on $FPTH\"; fi\n" >>$AUDITSCRIPT
          printf -- "else\n  echo \"Error: $FPTH does not exist!\"\n  PASS=1\nfi\n" >>$AUDITSCRIPT
        fi
        if [ "$FTYPE" == "symlink" ]; then
          printf -- "# set permissions on '$FNAME'\nchown -h root:root /$FPTH\n" >>${RELEASESCRIPT}.tail
        else
          printf -- "# set permissions on '$FNAME'\nchown $FOWNER:$FGROUP /$FPTH\nchmod $FOCTAL /$FPTH\n" >>${RELEASESCRIPT}.tail
        fi
        # stat
        if [ "$FTYPE" == "symlink" ]; then
          printf -- "/$FPTH -> $FTARGET root root 777 $FTYPE\n" |perl -pe 's/binary$/file/' >>$STATFILE
        else
          printf -- "/$FPTH $FOWNER $FGROUP ${FOCT//^0/} $FTYPE\n" |perl -pe 's/(binary|copy|download)$/file/' >>$STATFILE
        fi
      fi
    done
    # finalize audit script
    printf -- "\nif [ \$PASS -eq 0 ]; then echo \"Audit PASSED\"; else echo \"Audit FAILED\"; fi\nexit \$PASS\n" >>$AUDITSCRIPT
    chmod +x $AUDITSCRIPT

    # create backup
    printf -- "# create backup\ntest -d /var/backups || mkdir -p /var/backups\nFileName=\"\$( hostname )-scs-backup-\$( date +%%y%%m%%d-%%H%%M ).tar\"\n" >>$RELEASESCRIPT
    printf -- "tar -cf /var/backups/\$FileName %s 2>/dev/null\n" "${AllFiles[*]}" >>$RELEASESCRIPT
    for ((i=0;i<${#DeleteFiles[@]};i++)); do
      printf -- "if [[ -d \"${DeleteFiles[i]}\" ]]; then tar -rf /var/backups/\$FileName %s 2>/dev/null; fi\n" "${DeleteFiles[i]}" >>$RELEASESCRIPT
    done
    printf -- "gzip /var/backups/\$FileName 2>/dev/null\n\n" >>$RELEASESCRIPT

    # cleanup old backups
    if [[ $SCS_NumRemoteBackups -gt 0 ]]; then
      printf -- "cd /var/backups || exit 1\nCount=\$( ls -1 \$( hostname )-scs-backup-* | wc -l )\n" >>$RELEASESCRIPT
      printf -- "if [[ \$Count -gt ${SCS_NumRemoteBackups} ]]; then\n  ls -1 \$( hostname )-scs-backup-* | head -n\$( expr \$Count - $SCS_NumRemoteBackups) | xargs rm -f {}\nfi\n\n" >>$RELEASESCRIPT
    fi

    # do not deploy stat/audit scripts
    printf -- "rm -f \$TMPDIR/scs-{stat,audit.sh}\n\n" >>$RELEASESCRIPT

    # do not replace symlinks (which happens with a direct tar xzf)
    #
    # rsync options being used for your convenience:
    #
    #       -c, --checksum              skip based on checksum, not mod-time & size
    #       -r, --recursive             recurse into directories
    #       -l, --links                 copy symlinks as symlinks
    #       -K, --keep-dirlinks         treat symlinked dir on receiver as dir
    #
    printf -- "/usr/bin/rsync -crlK \$TMPDIR/ / >/dev/null 2>&1\n" >>$RELEASESCRIPT
    printf -- "rm -rf \$TMPDIR\n\n" >>$RELEASESCRIPT

    # finalize installation script
    printf -- "\nlogger -t scs \"installation complete\"\n" >>${RELEASESCRIPT}.tail
    cat ${RELEASESCRIPT}.tail >>$RELEASESCRIPT
    rm -f ${RELEASESCRIPT}.tail
    chmod +x $RELEASESCRIPT

    # generate the release
    pushd $TMP/release >/dev/null 2>&1
    find . -depth -print0 |cpio -o0H newc 2>/dev/null |gzip -9 >$RELEASEDIR/$RELEASEFILE
    popd >/dev/null 2>&1

    # add archive to script
    printf -- "\n\nexit 0\n\n__PAYLOAD__\n" >>$RELEASESCRIPT
    cat $RELEASEDIR/$RELEASEFILE>>$RELEASESCRIPT
    mv $RELEASESCRIPT $RELEASEDIR/

    printf -- "Complete. Generated release:\n$RELEASEDIR/$NAME-release-$MyDate.bsx\n"
  else
    # some operations (such as system_provision) require the release file, even if it's empty
    pushd $TMP/release >/dev/null 2>&1
    find . -depth -print0 | cpio -o0 | gzip -9 >$RELEASEDIR/$RELEASEFILE
    popd >/dev/null 2>&1
    printf -- "No managed configuration files.\n%s\n" "$RELEASEDIR/$RELEASEFILE"
  fi
}

# output list of resources assigned to a system
#
function system_resource_list {
  generic_choose system "$1" C && shift
  # load the system
  local NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemBuildDate SystemLock
  # [FORMAT:system]
  IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$C," ${CONF}/system )"
  for APP in $( build_application_list "$BUILD" ); do
    # get any localized resources for the application
    # [FORMAT:resource]
    grep -E ",application,$LOC:$EN:$APP," ${CONF}/resource |cut -d',' -f1,2,5
  done
  # add any host assigned resources to the list
  # [FORMAT:resource]
  grep -E ",host,$NAME," ${CONF}/resource |cut -d',' -f1,2,5
}

function system_show {
  system_exists "$1" || err "Unknown or missing system name"
  local FILES=() NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY BRIEF=0 SystemBuildDate \
        SystemLock
  [ "$2" == "--brief" ] && BRIEF=1
  # load the system
  # [FORMAT:system]
  IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$1," ${CONF}/system )"
  # if overlay is null then there is no overlay
  test -z "$OVERLAY" && OVERLAY="N/A"
  # output the status/summary
  printf -- "Name: %s\nBuild: %s\nIP: %s\nLocation: %s\nEnvironment: %s\nVirtual: %s\nBase Image: %s\nOverlay: %s\nLocked: %s\nLast Build: %s\n" \
    "$NAME" "$BUILD" "$IP" "$LOC" "$EN" "$VIRTUAL" "$BASE_IMAGE" "$OVERLAY" "$SystemLock" "$( date +'%c' -d @${SystemBuildDate} 2>/dev/null )"
  test $BRIEF -eq 1 && return
  # show other systems using this as a base image
  if [[ "$BASE_IMAGE" == "y" ]]; then
    # [FORMAT:system]
    NUM=$( grep -cE "^([^,]*,){7}$NAME," ${CONF}/system )
    if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
    echo -e "\nThere ${A} ${NUM} overlay${S}."
    if [ $NUM -gt 0 ]; then
      # [FORMAT:system]
      grep -E "^([^,]*,){7}$NAME," ${CONF}/system |perl -pe 's/,.*//; s/^/   /'
    fi
  fi
  # look up the applications configured for the build assigned to this system
  if ! [ -z "$BUILD" ]; then
    NUM=$( build_application_list "$BUILD" |wc -l |awk '{print $1}' )
    if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
    echo -e "\nThere ${A} ${NUM} linked application${S}."
    if [ $NUM -gt 0 ]; then
      build_application_list "$BUILD" |perl -pe 's/^/   /'
      # retrieve application related data
      # [FORMAT:application]
      for APP in $( grep -E ",${BUILD}," ${CONF}/application |awk 'BEGIN{FS=","}{print $1}' ); do
        # get the file list per application
        FILES=( ${FILES[@]} $( application_file_list_unformatted $APP --environment $EN ) )
      done
    fi
  fi
  # pull system resources
  RSRC=( $( system_resource_list "$NAME" ) )
  # show assigned resources (by host, application + environment)
  if [ ${#RSRC[*]} -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo -e "\nThere ${A} ${#RSRC[*]} linked resource${S}."
  if [ ${#RSRC[*]} -gt 0 ]; then for ((i=0;i<${#RSRC[*]};i++)); do
    printf -- "${RSRC[i]}\n" |awk 'BEGIN{FS=","}{print $2,$1,$3}'
  done; fi |column -t |perl -pe 's/^/   /'
  # output linked configuration file list
  if [ ${#FILES[*]} -gt 0 ]; then
    printf -- "\nManaged configuration files:\n"
    for ((i=0;i<${#FILES[*]};i++)); do
      # [FORMAT:file]
      grep -E "^${FILES[i]}," $CONF/file |awk 'BEGIN{FS=","}{print $1,$2}'
    done |sort |uniq |column -t |perl -pe 's/^/   /'
  else
    printf -- "\nNo managed configuration files."
  fi
  printf -- '\n'
}

# start the system build (scripts) on the remote system
#
# arguments:
#   $1	system-name
#   $2	remote-ip (current address)
#
# optional:
#   $3	role
#
function system_start_remote_build {
  if [[ $# -eq 0 || -z "$1" ]]; then err "Usage: $0 system <name> --start-remote-build current-ip [role]"; fi

  system_exists $1 || err "Unknown or missing system name"
  valid_ip $2      || err "An invalid IP was provided"

  # confirm availabilty
  check_host_alive $2 || errlog "Host is down. Aborted."

  # remove any stored keys for the current and target IPs since this is a new build
  purge_known_hosts --name $1 --ip $2

  # kick-off install and return
  if [ -z "$3" ]; then
    scslog "$2 nohup ESG/system-builds/role.sh --name $1 --shutdown >/dev/null 2>&1 </dev/null &"
    ssh_remote_command -d $2 "nohup ESG/system-builds/role.sh scs-build --name $1 --shutdown >/dev/null 2>&1 </dev/null &" >>$SCS_Background_Log 2>&1
  else
    scslog "$2 nohup ESG/system-builds/role.sh --name $1 --shutdown $3 >/dev/null 2>&1 </dev/null &"
    ssh_remote_command -d $2 "nohup ESG/system-builds/role.sh scs-build --name $1 --shutdown $3 >/dev/null 2>&1 </dev/null &" >>$SCS_Background_Log 2>&1
  fi
}

# print the type of the system: physical, single, backing, or overlay
#
function system_type {
  system_exists "$1" || err "Unknown or missing system name"

  # scope variables
  local NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemBuildDate SystemLock

  # load the system
  # [FORMAT:system]
  IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$1," ${CONF}/system )"

  if [ "$VIRTUAL" == "n" ];    then printf -- "physical\n"; return; fi
  if [ "$BASE_IMAGE" == "y" ]; then printf -- "backing\n"; return; fi
  if [ -z "$OVERLAY" ];        then printf -- "single\n"; return; fi
                                    printf -- "overlay\n"
}

# unlock a system to allow changes
#
function system_unlock {
  system_exists $1 || return 1
  start_modify
  # [FORMAT:system]
  perl -i -pe "s/^($1,)(([^,]*,){7})[^,]*,(.*)/\\1\\2n,\\4/" ${CONF}/system
  if [[ $? -ne 0 ]]; then err "Error updating configuration"; fi
  echo "$1 unlocked"
  commit_file system
}

function system_update {
  local C NAME BUILD ORIGIP LOC EN ORIGVIRTUAL ORIGBASE_IMAGE ORIGOVERLAY SystemBuildDate \
        IP NETNAME ORIGNAME SystemLock
  start_modify
  generic_choose system "$1" C && shift

  # [FORMAT:system]
  IFS="," read -r NAME BUILD ORIGIP LOC EN ORIGVIRTUAL ORIGBASE_IMAGE ORIGOVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$C," ${CONF}/system )"
  ORIGNAME="$NAME"

  # check lock
  if [[ "$SystemLock" != "n" ]]; then err "System locked; please unlock to make changes"; fi

  get_input NAME "Hostname" --default "$NAME"
  get_input BUILD "Build" --default "$BUILD" --null --options "$( build_list_unformatted |replace )"
  while [[ "$IP" != "auto" && "$IP" != "dhcp" && $( exit_status valid_ip "$IP" ) -ne 0 ]]; do get_input IP "Primary IP (address, dhcp, or auto to auto-select)" --default "$ORIGIP"; done
  # automatic IP selection
  if [ "$IP" == "auto" ]; then
    get_input NETNAME "Network (loc-zone-alias)" --options "$( network_list_unformatted |grep -E "^${LOC}-" |awk '{print $1"-"$2 }' |replace )" --auto "$6"
    shift
    IP=$( network_ip_list_available $NETNAME --limit 1 )
    valid_ip $IP || err "Automatic IP selection failed"
  fi
  get_input LOC "Location" --default "$LOC" --options "$( location_list_unformatted |replace )"
  get_input EN "Environment" --default "$EN" --options "$( environment_list_unformatted |replace )"
  # changing these settings can be non-trivial for a system that is already deployed...
  get_yn VIRTUAL "Virtual Server (y/n)" --default "$ORIGVIRTUAL"
  if [ "$ORIGVIRTUAL" != "$VIRTUAL" ]; then
    printf -- '%s\n' "This setting should ONLY be changed if it was set in error."
    get_yn R "Are you SURE you want to change the type of system (y/n)?" || exit
  fi
  if [ "$VIRTUAL" == "y" ]; then
    get_yn BASE_IMAGE "Use as a backing image for overlay (y/n)?" --default "$ORIGBASE_IMAGE"
    if [ "$ORIGBASE_IMAGE" != "$BASE_IMAGE" ]; then
      printf -- '%s\n' "This setting should ONLY be changed if it was set in error. Changing this setting if another system is built on this one WILL cause a major production issue."
      get_yn R "Are you SURE you want to change the type of system (y/n)?" || exit
    fi
    if [ -z "$ORIGOVERLAY" ]; then ORIGOVERLAY_Q="n"; else ORIGOVERLAY_Q="y"; fi
    get_yn OVERLAY_Q "Overlay on another system (y/n)?" --default "$ORIGOVERLAY_Q"
    if [ "$ORIGOVERLAY_Q" != "$OVERLAY_Q" ]; then
      printf -- '%s\n' "This setting should ONLY be changed if it was set in error. Changing this setting after the system is built WILL cause a major production issue."
      get_yn R "Are you SURE you want to change the type of system (y/n)?" || exit
    fi
    if [ "$OVERLAY_Q" == "y" ]; then
      get_input OVERLAY "Overlay System (or auto to select when provisioned)" --options "auto,$( system_list_unformatted --backing --exclude-parent $NAME |replace )" --default "$ORIGOVERLAY"
    else
      OVERLAY=""
    fi
  else
    BASE_IMAGE="n"
    OVERLAY=""
  fi

  # handle single or overlay -> backing image
  if [[ "$ORIGBASE_IMAGE" != "$BASE_IMAGE" && "$BASE_IMAGE" == "y" && $( exit_status valid_ip $IP ) -eq 0 && $( exit_status check_host_alive $IP ) -eq 0 ]]; then

    if [ "$( ssh_remote_command -d $IP "hostname" )" != "$NAME" ]; then
      scslog "refusing to change system type since the system at the registered IP does not match the host name"
      echo "refusing to change system type since the system at the registered IP does not match the host name" >&2
      BASE_IMAGE=$ORIGBASE_IMAGE
    else
      #  - look up the network for this IP
      NETNAME=$( network_list --match $IP )
      test -z "$NETNAME" && err "No network was found matching this system's IP address"
      # flush hardware address, ssh host keys, and device mappings to anonymize system
      ssh_remote_command -d -n -q $IP "ESG/system-builds/install.sh configure-system --ip dhcp --flush --skip-restart >/dev/null 2>&1; halt"
      #ssh -o "StrictHostKeyChecking no" -n $HVIP "while [ \"\$( /usr/bin/virsh dominfo $NAME |grep -i state |grep -i running |wc -l |awk '{print \$1}' )\" -gt 0 ]; do sleep 5; done" >/dev/null 2>&1
      #scslog "successfully stopped $NAME"
      sleep 15
      # this is a base_image - move built image file, deploy to other HVs (as needed), and undefine system
      scslog "converting VM to backing image"
      system_convert $NAME --backing --no-prompt --force --network $NETNAME
      if [ $? -eq 0 ]; then IP=dhcp; scslog "successfully converted vm"; else scslog "conversion failed"; fi
    fi

  fi

  # conditionally assign/reserve IP
  if [[ "$IP" != "dhcp" && ! -z "$( network_ip_locate $IP )" ]]; then network_ip_assign $IP $NAME || printf -- '%s\n' "Error - unable to assign the specified IP" >&2; fi

  # save changes
  # [FORMAT:system]
  perl -i -pe "s/^$ORIGNAME,.*/${NAME},${BUILD},${IP},${LOC},${EN},${VIRTUAL},${BASE_IMAGE},${OVERLAY},${SystemLock},${SystemBuildDate}/" ${CONF}/system
  # handle IP change
  if [ "$IP" != "$ORIGIP" ]; then
    if [ "$ORIGIP" != "dhcp" ]; then network_ip_unassign $ORIGIP; fi
    if [[ "$IP" != "dhcp" && ! -z "$( network_ip_locate $IP )" ]]; then network_ip_assign $IP $NAME || printf -- '%s\n' "Error - unable to assign the specified IP" >&2; fi
  fi
  commit_file system
}

# update /etc/hosts, lpad hosts, and deploy
#
# $1 = hostname
# $2 = ip
#
function system_update_push_hosts {
  test -z "$PUSH_HOSTS" && return
  local ENTRY kh=/etc/hosts

  printf -- " $PUSH_HOSTS " |grep -q " $( hostname ) "
  if [ $? -ne 0 ]; then echo "This system is not authorized to update /etc/hosts" >&2; return 3; fi

  # hostname and IP should either both be unique, or both registered together
  ENTRY=$( grep -E '[ '$'\t'']'$1'[ '$'\t'']' $kh );        H=$?
  echo "$ENTRY" |grep -qE '^'${2//\./\\.}'[ '$'\t'']';      I=$?
  grep -qE '^'${2//\./\\.}'[ '$'\t'']' $kh;                 J=$?

  (
  flock -x -w 600 201
  if [ $? -ne 0 ]; then errlog "Unable to obtain lock on $kh"; return; fi

  if [ $(( $H + $I )) -eq 0 ]; then
    # found together; this is an existing host
    echo "Host entry exists."
  elif [ $(( $H + $J )) -eq 2 ]; then
    echo "Adding host entry..."
    cat $kh >$kh.sysbuild
    echo -e "$2\t$1\t\t$1.${DOMAIN_NAME}" >>$kh
    diff $kh{.sysbuild,}; echo
    # sync
    test -x /usr/local/etc/push-hosts.sh && /usr/local/etc/push-hosts.sh
  elif [ $H -eq 0 ]; then
    echo "The host name you provided ($1) is already registered with a different IP address in $kh. Aborted." >&2
    return 1
  elif [ $J -eq 0 ]; then
    echo "The IP address you provided ($2) is already registered with a different host name in $kh. Aborted." >&2
    return 1
  fi
  ) 201>>$kh

  (
  flock -x -w 30 202
  if [ $? -ne 0 ]; then errlog "Unable to obtain lock on /usr/local/etc/lpad/hosts/managed-hosts"; return; fi

  # add host to lpad as needed
  test -f /usr/local/etc/lpad/hosts/managed-hosts || return 0
  grep -qE '^'$1':' /usr/local/etc/lpad/hosts/managed-hosts
  if [ $? -ne 0 ]; then
    echo "Adding lpad entry..."
    echo "$1:linux" >>/usr/local/etc/lpad/hosts/managed-hosts
  fi
  ) 202>>/usr/local/etc/lpad/hosts/managed-hosts

  return 0
}

# connect to the remote system and run uptime
#
function system_uptime {
  system_exists "$1" || err "Unknown or missing system name"
  ssh_remote_command $1 uptime
}

# generate all system variables and settings
#
function system_vars {
  system_exists "$1" || err "Unknown or missing system name"
  # load the system
  local NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY ZONE ALIAS \
        NET MASK BITS GW HAS_ROUTES DNS VLAN DESC REPO_ADDR REPO_PATH \
        REPO_URL BUILD DEFAULT_BUILD NTP SystemBuildDate SystemLock
  # [FORMAT:system]
  IFS="," read -r NAME BUILD IP LOC EN VIRTUAL BASE_IMAGE OVERLAY SystemLock SystemBuildDate <<< "$( grep -E "^$1," ${CONF}/system )"
  # output system data
  echo -e "system.name $NAME\nsystem.build $BUILD\nsystem.ip $IP\nsystem.location $LOC\nsystem.environment $EN"
  # output network data, if available
  local SYSNET=$( network_list --match $IP )
  if [ ! -z "$SYSNET" ]; then
    # [FORMAT:network]
    IFS="," read -r LOC ZONE ALIAS NET MASK BITS GW HAS_ROUTES DNS VLAN DESC REPO_ADDR REPO_PATH REPO_URL BUILD DEFAULT_BUILD NTP DHCP <<< "$( grep -E "^${SYSNET//-/,}," ${CONF}/network )"
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
  OIFS=$IFS; IFS=$'\n'
  for CNST in $( system_constant_list $NAME ); do
    IFS="," read -r CN VAL <<< "$CNST"
    echo "constant.$( printf -- "$CN" |tr 'A-Z' 'a-z' ) $VAL"
  done
  IFS=$OIFS
}

# create and attach a new disk to an existing virtual machine
#
function system_vm_disk_create {
  #grep -q "CONFIG_HOTPLUG_PCI_ACPI=y" /boot/config-$( uname -r )

  if [ $# -lt 2 ]; then system_vm_disk_create_help; return 1; fi

  local Args Alias Backing Destroy=0 Disk DryRun=0 Size=40 Type=virtio VM \
        Hypervisor AllHypervisors HypervisorIP VMPath HypervisorEnabled \
        Disk_Type_List DevID NewDevID Existing=0

  VM="$1"; shift
  Disk_Type_List="ide scsi usb virtio xen"

  while [ $# -gt 0 ]; do case $1 in
    -a|--alias) Alias="$2"; shift;;
    -b|--backing) Backing="$2"; shift;;
    -d|--disk) Disk="$2"; shift;;
    -e|--use-existing) Existing=1;;
    -h|--hypervisor) Hypervisor="$2"; shift;;
    -s|--size) Size="$2"; shift;;
    -t|--type) Type="$2"; shift;;
    --destroy) Destroy=1;;
    --dry-run) DryRun=1;;
  esac; shift; done

  system_exists $VM || return 1
  [ -z "$Alias" ] && return 1
  printf -- " $Disk_Type_List " |grep -q " $Type " || err "Invalid bus (disk type). Must be one of $Disk_Type_List."
  [ "$Size" != "${Size//[^0-9]/}" ] && err "Disk size must be a numeric integer"
  [ $Size -lt 1 ] && err "Disk size must be at least 1 GB"
  [ $Size -gt 2000 ] && err "Disk size must be less than 2 TB (this limit is arbitrary)"
  printf -- "${Alias}${VM}${Disk}${Backing}" |grep -q "*" && err "Invalid character in system name, alias, or path."

  if [ -z "$Hypervisor" ]; then Hypervisor="$( hypervisor_locate_system $VM )"; else hypervisor_exists $Hypervisor || err "Invalid hypervisor"; fi
  #AllHypervisors="$( hypervisor_locate_system $VM --all |tr '\n' ' ' )"

  [ -z "$Hypervisor" ] && err "Unable to locate hypervisor for the specified system"
  # [FORMAT:hypervisor]
  read HypervisorIP VMPath HypervisorEnabled <<<"$( grep -E "^$Hypervisor," ${CONF}/hypervisor |awk 'BEGIN{FS=","}{print $2,$4,$7}' )"
  [ "$HypervisorEnabled" == "y" ] || err "The primary hypervisor for this system is not enabled"

  if ! [ -z "$Backing" ]; then
    ssh_remote_command -d -q $HypervisorIP "test -f $Backing"
    if [ $? -ne 0 ]; then err "Specified backing disk does not exist"; fi
  fi

  [ -z "$Disk" ] && Disk="${VMPath}/${VM}.${Alias}.img"
  ssh_remote_command -d -q $HypervisorIP "test -f $Disk"
  if [ $? -eq 0 ]; then
    if [ $Destroy -eq 1 ]; then
      ssh_remote_command -d -q $HypervisorIP "/bin/rm -f $Disk"
    elif [ $Existing -eq 0 ]; then
      err "The specified disk already exists on $Hypervisor"
    fi
  fi

  DevID=$( ssh_remote_command -d $HypervisorIP "virsh dumpxml $VM |grep target |grep bus |sed -e \"s/.*dev='//; s/'.*//\" |sort |tail -n1" )
  NewDevID="$( printf -- "${DevID}" |perl -pe 's/.$//' )$( printf -- "${DevID: -1}" |tr 'a-y' 'b-z' )"

  if [ $Existing -eq 0 ]; then
    if ! [ -z "$Backing" ]; then Args="-b $Backing "; Size=""; else Size="${Size}G"; fi

    if [ $DryRun -eq 1 ]; then
      echo "DRY-RUN: Create disk..."
      echo "qemu-img create ${Args}-f qcow2 ${Disk} ${Size}"
      echo
    else
      ssh_remote_command -d -q $HypervisorIP "qemu-img create ${Args}-f qcow2 ${Disk} ${Size}"
      test $? -eq 0 || err "Error creating disk"
    fi
  fi

  if [ $DryRun -eq 1 ]; then

    echo "virsh attach-device $VM /tmp/$VM.scs_add_disk.$$.xml --persistent"
    echo
    cat <<_EOF
<disk type='file' device='disk'>
  <driver name='qemu' type='qcow2' cache='writeback'/>
  <source file='${Disk}'/>
  <target dev='${NewDevID}' bus='${Type}'/>
</disk>
_EOF

  else
    cat <<_EOF |ssh -o "StrictHostKeyChecking no" -l $SCS_RemoteUser -i $SCS_KeyFile $HypervisorIP "cat >/tmp/$VM.scs_add_disk.$$.xml"
<disk type='file' device='disk'>
  <driver name='qemu' type='qcow2' cache='writeback'/>
  <source file='${Disk}'/>
  <target dev='${NewDevID}' bus='${Type}'/>
</disk>
_EOF

    ssh_remote_command -d -q $HypervisorIP "virsh attach-device $VM /tmp/$VM.scs_add_disk.$$.xml --persistent"
    test $? -eq 0 || err "Error attaching device - see $Hypervisor:/tmp/$VM.scs_add_disk.$$.xml"
    echo "Successfully attached disk"
    scslog "attached $Size disk '$Alias' to $VM on $Hypervisor"

  fi

  return 0
}
function system_vm_disk_create_help { cat <<_EOF
Usage: ... --alias <name> --vm <name> [--backing </path/to/image.img>] [--disk </path/to/disk.img>] [--size N (in GB)] [--destroy] [--dry-run]

_EOF
}

# output the virtual machine disk configuration for the system
#
function system_vm_disks {
  system_exists "$1" || err "Unknown or missing system name"
  # get the host
  local HV=$( hypervisor_locate_system $1 --quick )
  test -z "$HV" && return
  # get the hypervisor IP
  # [FORMAT:hypervisor]
  local IP=$( grep -E '^'$HV',' ${CONF}/hypervisor |awk 'BEGIN{FS=","}{print $2}' )
  # verify connectivity
  check_host_alive $IP || return
  # get the disk configuration from the hypervisor
  local PARENT="/" XMLPATH
  while read_dom; do
    [ -z "$TAG_NAME" ] && continue
    if [ "${TAG_NAME:0:1}" == "/" ]; then
      PARENT="$( printf -- '%s' "$PARENT" |perl -pe 's%[^/]*/$%%' )"
      continue
    fi
    if [ "$TYPE" == "OPEN" ]; then PARENT="${PARENT}${TAG_NAME}/"; XMLPATH=$PARENT; else XMLPATH="${PARENT}${TAG_NAME}/"; fi
    #echo "Path: '$XMLPATH', Tag: '$TAG_NAME', Attributes: '$ATTRIBUTES', Type: '$TYPE', Content: '$CONTENT'"
    if [ "$XMLPATH" == "/domain/devices/disk/source/" ]; then
      printf -- '%s\n' "$ATTRIBUTES" |perl -pe "s/'//g; s/file=//"
    fi
  done <<< "$( ssh_remote_command -d $IP virsh dumpxml $1 )"
}


#Section: SETTINGS
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
ABORTFILE=/tmp/scs-abort-all
#
# name of subfolder to move backing images in to (no leading slash, include trailing slash)
BACKING_FOLDER=backing_images/
#
# path to build scripts
BUILDSRC=/home/wstrucke/ESG/system-builds
#
# local root for scs storage files, settings, and git repository
CONF=/usr/local/etc/lpad/app-config
#
# default size of a new system's HDD in GB
DEF_HDD=40
#
# default amount of RAM for a new system in MB
DEF_MEM=1024
#
# site domain name (for hosts)
DOMAIN_NAME=2checkout.com
#
# use the user's default editor if one is set
EditProgram=${EDITOR:=vim}
#
# tcp ports to check to validate an ip address is not allocated (space seperated list)
#   tcp/22 (ssh) is always checked
IP_Check_Ports="80 443 8080 8443"
#
# path to kickstart templates (centos6-i386.tpl, etc...)
KSTEMPLATE=/home/wstrucke/ESG/system-builds/kickstart-files/templates
#
# list of architectures for builds -- each arch in the list must be available
#   for each OS version (below)
OSARCH="i386,x86_64"
#
# list of operating systems for builds
OSLIST="centos4,centos5,centos6"
#
# management servers with authoritative host files (space seperated list)
PUSH_HOSTS="hqpcore-bkup01 bkup-21"
#
# local path to store release archives
RELEASEDIR=${SCS_RELEASES:=/bkup1/scs-release}; mkdir $RELEASEDIR >/dev/null 2>&1 || RELEASEDIR=~/scs-release
#
# the version of the schema for this release
SchemaVersion=0.1
#
# path to activity log
SCS_Activity_Log=/var/log/scs_activity.log; test -w $SCS_Activity_Log   || SCS_Activity_Log=scs_activity.log
#
# path to background task log
SCS_Background_Log=/var/log/scs_bg.log    ; test -w $SCS_Background_Log || SCS_Background_Log=scs_bg.log
#
# path to error log
SCS_Error_Log=/var/log/scs_error.log      ; test -w $SCS_Error_Log      || SCS_Error_Log=scs_error.log
#
# number of backups to keep on each remote system when deploying config (a value of 0 will keep all)
SCS_NumRemoteBackups=${SCS_REMOTE_BACKUPS:=10}
#
# default private key for systems management (ssh/scp)
SCS_KeyFile=${SCS_IDENTITY:=/root/.ssh/id_rsa}
#
# remote user on all systems for management access
SCS_RemoteUser=${SCS_REMOTE_USER:=root}
#
# shared repository setting (enable or disable "locking")
SCS_SharedLocalRepo=${SCS_SHARED_REPO:=1}
#
# application version
SCS_Version="1.0.0"
#
# path to the temp file for patching configuration files
TMP=${SCS_TEMP:=/tmp/scs.$$}
#
# path to a large local folder for temporary file transfers
TMPLarge=${SCS_TEMP_LARGE:=/bkup1}        ; test -d $TMPLarge || TMPLarge=~/scs-large-tmp


#Section: MAIN
 #     #    #    ### #     #
 ##   ##   # #    #  ##    #
 # # # #  #   #   #  # #   #
 #  #  # #     #  #  #  #  #
 #     # #######  #  #   # #
 #     # #     #  #  #    ##
 #     # #     # ### #     #

# define global variables
GitVer=$( git version 2>/dev/null |perl -pe 's/.* ([0-9\.]*)( .*|$)/\1/' )
HostOS=$( [[ "$( uname -v )" =~ "Darwin" ]] && echo mac || echo linux )
USERNAME=""

if [[ "$HostOS" == "mac" ]]; then
  # turn off special handling of ._* files in tar, etc.
  export COPYFILE_DISABLE=true
  export COPY_EXTENDED_ATTRIBUTES_DISABLE=true
fi

# precaution
if [[ -z "$TMP" || "$TMP" == "/" ]]; then echo "Invalid temporary directory. Please use a variation of '/tmp/scs.\$\$'." >&2; exit 1; fi

trap cleanup_and_exit EXIT INT

# initialize
which git >/dev/null 2>&1 || err "Please install git or correct your PATH"

# the path to the configuration is configurable as an argument
if [[ "$1" == "-c" || "$1" == "--config" ]]; then
  test -d "$( dirname $2 )" && CONF="$2" && shift 2 || usage
else
  if [[ -n $SCS_CONF ]]; then
    CONF=$SCS_CONF
  fi
fi
echo "using configuration at '$CONF' for application at '$0'" >>$SCS_Activity_Log

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
case "$SUBJ" in
  abort) scs_abort $@; exit 0;;
  cancel|unlock) cancel_modify $@; exit 0;;
  commands) scs_commands; exit 0;;
  commit) stop_modify $@; exit 0;;
  diff) git_diff $@; exit 0;;
  dir) echo ${CONF}; exit 0;;
  help) help $@; exit 0;;
  lock) start_modify; exit 0;;
  log) git_log; exit 0;;
  pdir) dirname $( deref $0 ); exit 0;;
  status) git_status --exit $@;;
esac

# validate schema
check_schema

# output usage only if no arguments were provided
test $# -ge 1 || usage

# get verb
VERB="$( expand_verb_alias "$( echo "$1" |tr 'A-Z' 'a-z' )")"; shift

# if no verb is provided default to list, since it is available for all subjects
if [ -z "$VERB" ]; then VERB="list"; fi

# help
if [ "$VERB" == "help" ]; then help $SUBJ; exit 0; fi

# warn if lock file exists
test -f $ABORTFILE && printf -- '\E[31;47m%s\E[0m\n' "***** WARNING: ABORT ENABLED *****"

if [[ "$VERB" == "lineage" && "$SUBJ" == "build" ]]; then build_lineage $@; echo; exit 0; fi

# validate subject and verb
printf -- " application build constant environment file hypervisor location network resource system " |grep -q " $SUBJ "
[[ $? -ne 0 || -z "$SUBJ" ]] && usage
if [[ "$SUBJ" != "resource" && "$SUBJ" != "location" && "$SUBJ" != "system" && "$SUBJ" != "network" && "$SUBJ" != "hypervisor" ]]; then
  printf -- " create delete list show update edit file application constant environment cat undefine define " |grep -q " $VERB "
  [[ $? -ne 0 || -z "$VERB" ]] && usage
fi
[[ "$VERB" == "edit" && "$SUBJ" != "file" ]] && usage
[[ "$VERB" == "cat" && "$SUBJ" != "file" ]] && usage
[[ "$VERB" == "file" && "$SUBJ" != "application" ]] && usage
[[ "$VERB" == "application" && "$SUBJ" != "environment" ]] && usage
[[ "$VERB" == "constant" && (( "$SUBJ" != "environment" && "$SUBJ" != "application" )) ]] && usage
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
