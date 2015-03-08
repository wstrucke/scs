#!/bin/sh

# update schema to version 0.1
#
# requires:
#   $1	/path/to/configuration
#
function err { echo "$1"; exit 1; }

if [[ $# -ne 1 || ! -d "$1" ]]; then err "Missing argument"; fi

pushd $1 >/dev/null 2>&1 || err "Unable to switch to configuration directory"

# update system
#   old--format: name,build,ip,location,environment,virtual,backing_image,overlay,build_date\n
#   new--format: name,build,ip,location,environment,virtual,backing_image,overlay,locked,build_date\n
#
# verify format before change
if [[ -s system && $( sed 's/[^,]//g' system |awk '{print length}' |sort |uniq |wc -l ) -gt 1 ]]; then err "inconsistent or invalid system format before change"; fi
if [[ -s system && $( sed 's/[^,]//g' system |awk '{print length}' |sort |uniq ) -ne 8 ]]; then err "unable to validate system format before change"; fi
#
# add 'locked' option - default is 'n' for all systems
perl -i -pe 's/^(([^,]*,){8})(.*)$/\1n,\3/' system
#
# verify format following change
if [[ -s system && $( sed 's/[^,]//g' system |awk '{print length}' |sort |uniq ) -ne 9 ]]; then
  err "unable to validate system format after change. run \`git checkout system\` to repair the file"
fi
#
# complete
echo "...system updated: add locked, default value 'n'"

# update schema version
echo "0.1" >schema

exit 0
