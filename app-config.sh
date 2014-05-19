#!/bin/sh
#
# Manage application configuration files
#
# William Strucke [wstrucke@gmail.com]
# Version 1.0.0, May 2014
#
# Configuration Storage:
#   /usr/local/etc/lpad/app-config/
#     application                                          file
#     constant                                             file
#     environment                                          file
#     file                                                 file
#     location                                             file
#     network                                              file
#     resource                                             file
#     template                                             directory containing global application templates
#     <location>/                                          directory
#     <location>/network                                   file to list networks available at the location
#     <location>/<environment>                             directory
#     <location>/<environment>/constant                    file
#     <location>/<environment>/<application>               directory
#     <location>/<environment>/<application>/constant      file
#
# Locks are taken by using git branches
#
# A constant is a variable with a static value globally, per environment, or per application in an environment. (Scope)
# A constant has a globally unique name with a fixed value in the scope it is defined in and is in only one scope (never duplicated).
#
# A resource is a pre-defined type with a globally unique value (e.g. an IP address).  That value can be assigned to one or more hosts or applications.
#

#
# Assists you in generating or updating the patches that are deployed to
#  application servers to be installed with the local update-config
#  script
#
# Patches are stored in LPAD and pushed out with the install-config lpad
#  script.
#
#  /usr/local/etc/lpad/app-patches
#
# Templates are stored in LPAD and downloaded by the app server on
#  demand from sm-web.  The authoritative source for the patches
#  is in lpad at:
#
#  /usr/local/etc/lpad/app-templates
#

# first run function to init the configuration store
#
function initialize_configuration {
  test -d $CONF && exit 2
  mkdir -p $CONF/template
  git init --quiet $CONF
  touch $CONF/{application,constant,environment,file,location,network,resource}
  cd $CONF || err
  git add *
  git commit -a -m'initial commit' >/dev/null 2>&1
  cd - >/dev/null 2>&1
  return 0
}

function cleanup_and_exit {
  test -d $TMP && rm -rf $TMP
#  echo "Make sure to delete $TMP"
  printf -- "\n"
  exit 0
}

# error / exit function
#
function err {
  popd >/dev/null 2>&1
  test ! -z "$1" && echo $1 >&2 || echo "An error occurred" >&2
  test x"${BASH_SOURCE[0]}" == x"$0" && exit 1 || return 1
}

# get the user name of the administrator running this script
#
# sets the variable USERNAME
#
function get_user {
  if ! [ -z "$USERNAME" ]; then return; fi
  if ! [ -z "$SUDO_USER" ]; then U=${SUDO_USER}; else
    read -p "You have accessed root with a non-standard environment. What is your username? [root]? " U
    U=$( echo "$U" |tr 'A-Z' 'a-z' ); [ -z "$U" ] && U=root
  fi
  test -z "$U" && err "A user name is required to make modifications."
  USERNAME="$U"
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
    git branch $USERNAME
    git checkout $USERNAME >/dev/null 2>&1
  else
    git branch |grep -E '^\*' |grep -q $USERNAME || err "Another change is in progress, aborting."
  fi
  return 0
}

# merge changes back into master and remove the branch
#
function stop_modify {
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
  git rebase master >/dev/null 2>&1 || err "Error rebasing to master"
  if [ `git status -s |wc -l 2>/dev/null` -ne 0 ]; then
    git commit -a -m'final rebase' >/dev/null 2>&1 || err "Error committing rebase"
  fi
  git checkout master >/dev/null 2>&1 || err "Error switching to master"
  git merge $USERNAME >/dev/null 2>&1
  if [ $? -ne 0 ]; then git stash >/dev/null 2>&1; git checkout $USERNAME >/dev/null 2>&1; err "Error merging changes into master."; fi
  git commit -a -m"$USERNAME completed modifications at `date`" >/dev/null 2>&1
  git branch -d $USERNAME >/dev/null 2>&1
  popd >/dev/null 2>&1
}

# cancel changes and switch back to master
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
  test $? -ne 0 && err "Error -- this is not your branch."
  # confirm
  get_yn DF "Are you sure you want to discard outstanding changes (y/n)? "
  if [ "$DF" == "y" ]; then
    git clean -f >/dev/null 2>&1
    git reset --hard >/dev/null 2>&1
    git checkout master >/dev/null 2>&1
    git branch -d $USERNAME >/dev/null 2>&1
  fi
  popd >/dev/null 2>&1
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
#
function get_input {
  test $# -lt 2 && return
  LC=1; RL=""; P="$2"; V="$1"; D=""; NUL=0; OPT=""; shift; shift
  while [ $# -gt 0 ]; do case $1 in
    --default) D="$2"; shift;;
    --nc) LC=0;;
    --null) NUL=1;;
    --options) OPT="$2"; shift;;
    *) err;;
  esac; shift; done
  # collect input until a valid entry is provided
  while [ -z "$RL" ]; do
    # output the prompt
    printf -- "$P"
    # output the list of valid options if one was provided
    test ! -z "$OPT" && printf -- " (`printf -- "$OPT" |sed 's/,/, /g'`)"
    # output the default option if one was provided
    test ! -z "$D" && printf -- " [$D]: " || printf -- ": "
    # collect the input and force it to lowercase unless requested not to
    read RL; if [ $LC -eq 1 ]; then RL=$( printf -- "$RL" |tr 'A-Z' 'a-z' ); fi
    # if no input was provided and there is a default value, set the input to the default
    [[ -z "$RL" && ! -z "$D" ]] && RL="$D"
    # if no input was provied and null values are allowed, stop collecting input here
    [[ -z "$RL" && $NUL -eq 1 ]] && break
    # if there is a list of limited options clear the provided input unless it matches the list
    if ! [ -z "$OPT" ]; then printf -- ",$OPT," |grep -q ",$RL," || RL=""; fi
  done
  # set the provided variable value to the validated input
  eval "$V='$RL'"
}
#
# requires:
#  $1 variable name (no spaces)
#  $2 prompt
#
function get_yn {
  test $# -lt 2 && return
  RL=""; while [[ "$RL" != "y" && "$RL" != "n" ]]; do get_input RL "$2"; done
  eval "$1='$RL'"
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
  grep -qE '^'$C',' ${CONF}/$1 || err "Unknown $1"
  get_yn RL "Are you sure (y/n)? "
  if [ "$RL" == "y" ]; then sed -i '/^'$C',/d' ${CONF}/$1; fi
  commit_file $1
  refresh_dirs
}

# refresh the directory structure to add/remove location/environment/application paths
#
function refresh_dirs {
  #echo "Refresh not implemented" >&2
  return
}

function application_create {
  start_modify
  # get user input and validate
  get_input NAME "Name"
  get_input ALIAS "Alias"
  get_input BUILD "Build"
  get_yn CLUSTER "LVS Support (y/n)"
  # validate unique name
  grep -qE '^'$NAME',' $CONF/application && err "Application already defined."
  grep -qE ','$ALIAS',' $CONF/application && err "Alias invalid or already defined."
  # confirm before adding
  printf -- "\nDefining a new application named '$NAME', alias '$ALIAS', installed on the '$BUILD' build"
  [ "$CLUSTER" == "y" ] && printf -- " with " || printf -- " without "
  printf -- "cluster support.\n"
  while [[ "$ACK" != "y" && "$ACK" != "n" ]]; do read -p "Is this correct (y/n): " ACK; ACK=$( printf "$ACK" |tr 'A-Z' 'a-z' ); done
  # add
  [ "$ACK" == "y" ] && printf -- "${NAME},${ALIAS},${BUILD},${CLUSTER}\n" >>$CONF/application
  commit_file application
  refresh_dirs
}

function application_delete {
  generic_delete application $1
}

function application_list {
  NUM=$( wc -l $CONF/application |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined application${S}."
  test $NUM -eq 0 && return || echo
  cat $CONF/application |awk 'BEGIN{FS=","}{print $1}' |sort
}

function application_show {
  test $# -eq 1 || err "Provide the application name"
  APP="$1"
  grep -qE '^'$APP',' $CONF/application || err "Invalid application"
  read APP ALIAS BUILD CLUSTER <<< $( grep -E '^'$APP',' ${CONF}/application |tr ',' ' ' )
  printf -- "Name: $APP\nAlias: $ALIAS\nBuild: $BUILD\nCluster Support: $CLUSTER"
}

function application_update {
  start_modify
  if [ -z "$1" ]; then
    application_list
    printf -- "\n"
    get_input APP "Application to Modify"
  else
    APP="$1"
  fi
  grep -qE '^'$APP',' $CONF/application || err "Invalid application"
  printf -- "\n"
  read APP ALIAS BUILD CLUSTER <<< $( grep -E '^'$APP',' ${CONF}/application |tr ',' ' ' )
  get_input NAME "Name" --default $APP
  get_input ALIAS "Alias" --default $ALIAS
  get_input BUILD "Build" --default $BUILD
  get_yn CLUSTER "LVS Support (y/n)"
  sed -i 's/^'$APP',.*/'${NAME}','${ALIAS}','${BUILD}','${CLUSTER}'/' ${CONF}/application
  commit_file application
}

function constant_create {
  start_modify
  # get user input and validate
  get_input NAME "Name" --nc
  get_input DESC "Description" --nc
  # force uppercase for constants
  NAME=$( printf -- "$NAME" | tr 'a-z' 'A-Z' )
  # validate unique name
  grep -qE '^'$NAME',' $CONF/constant && err "Constant already defined."
  # add
  printf -- "${NAME},${DESC//,/ }\n" >>$CONF/constant
  commit_file constant
}

function constant_delete {
  generic_delete constant $1
}

function constant_list {
  NUM=$( wc -l ${CONF}/constant |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined constant${S}."
  test $NUM -eq 0 && return || echo
  cat ${CONF}/constant |awk 'BEGIN{FS=","}{print $1}' |sort
}

function constant_show {
  test $# -eq 1 || err "Provide the constant name"
  C="$( printf -- "$1" |tr 'a-z' 'A-Z' )"
  grep -qE '^'$C',' ${CONF}/constant || err "Unknown constant"
  read NAME DESC <<< $( grep -E '^'$C',' ${CONF}/constant |tr ',' ' ' )
  printf -- "Name: $NAME\nDescription: $DESC"
}

function constant_update {
  start_modify
  if [ -z "$1" ]; then
    constant_list
    printf -- "\n"
    get_input C "Constant to Modify"
  else
    C="$1"
  fi
  C=$( printf -- "$C" |tr 'a-z' 'A-Z' )
  grep -qE '^'$C',' ${CONF}/constant || err "Unknown constant"
  printf -- "\n"
  read NAME DESC <<< $( grep -E '^'$C',' ${CONF}/constant |tr ',' ' ' )
  get_input NAME "Name" --default $NAME
  get_input DESC "Description" --default "$DESC"
  sed -i 's/^'$C',.*/'${NAME}','"${DESC//,/ }"'/' ${CONF}/constant
  commit_file constant
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
  grep -qE '^'$NAME',' ${CONF}/environment && err "Environment already defined."
  grep -qE ','$ALIAS',' ${CONF}/environment && err "Environment alias already in use."
  # add
  printf -- "${NAME},${ALIAS},${DESC//,/ }\n" >>${CONF}/environment
  commit_file environment
  refresh_dirs
}

function environment_delete {
  generic_delete environment $1
}

function environment_list {
  NUM=$( wc -l ${CONF}/environment |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined environment${S}."
  test $NUM -eq 0 && return || echo
  cat ${CONF}/environment |awk 'BEGIN{FS=","}{print $1}' |sort
}

function environment_show {
  test $# -eq 1 || err "Provide the environment name"
  grep -qE '^'$1',' ${CONF}/environment || err "Unknown environment" 
  read NAME ALIAS DESC <<< $( grep -E '^'$1',' ${CONF}/environment |tr ',' ' ' )
  printf -- "Name: $NAME\nAlias: $ALIAS\nDescription: $DESC"
}

function environment_update {
  start_modify
  if [ -z "$1" ]; then
    environment_list
    printf -- "\n"
    get_input C "Environment to Modify"
  else
    C="$1"
  fi
  grep -qE '^'$C',' ${CONF}/environment || err "Unknown environment"
  printf -- "\n"
  read NAME ALIAS DESC <<< $( grep -E '^'$C',' ${CONF}/environment |tr ',' ' ' )
  get_input NAME "Name" --default $NAME
  get_input ALIAS "Alias (One Letter, Unique)" --default $ALIAS
  get_input DESC "Description" --default "$DESC" --null --nc
  # force uppercase for site alias
  ALIAS=$( printf -- "$ALIAS" | tr 'a-z' 'A-Z' )
  sed -i 's/^'$C',.*/'${NAME}','${ALIAS}','"${DESC//,/ }"'/' ${CONF}/environment
  commit_file environment
}

function file_create {
  start_modify
  # get user input and validate
  get_input NAME "Name (for reference)" --nc
  get_input PTH "Full Path (for deployment)" --nc
  get_input DESC "Description" --nc --null
  # validate unique name
  grep -qE '^'$NAME',' ${CONF}/file && err "File already defined."
  # add
  printf -- "${NAME},${PTH//,/_},${DESC//,/ }\n" >>${CONF}/file
  # create base file
  pushd $CONF >/dev/null 2>&1 || err "Unable to change to '${CONF}' directory"
  mkdir template >/dev/null 2>&1
  touch template/${NAME}
  git add template/${NAME} >/dev/null 2>&1
  git commit -m"template created by ${USERNAME}" file template/${NAME} >/dev/null 2>&1 || err "Error committing new template to repository"
  popd >/dev/null 2>&1
}

function file_delete {
  start_modify
  if [ -z "$1" ]; then
    file_list
    printf -- "\n"
    get_input C "File to Delete"
  else
    C="$1"
  fi
  grep -qE '^'$C',' ${CONF}/file || err "Unknown file"
  printf -- "WARNING: This will remove any templates and stored configurations in all environments for this file!\n"
  get_yn RL "Are you sure (y/n)? "
  if [ "$RL" == "y" ]; then
    sed -i '/^'$C',/d' ${CONF}/file
    pushd $CONF >/dev/null 2>&1
    git rm template/${C} >/dev/null 2>&1
    git add file >/dev/null 2>&1
    git commit -m"template removed by ${USERNAME}" >/dev/null 2>&1 || err "Error committing removal to repository"
    popd >/dev/null 2>&1
    refresh_dirs
  fi
}

# general file editing function for both templates and applied template instances
#
# optional:
#   $1 name of the template to edit
#
function file_edit {
  start_modify
  if [ -z "$1" ]; then
    file_list
    printf -- "\n"
    get_input C "File to Edit"
  else
    C="$1"
  fi
  grep -qE '^'$C',' ${CONF}/file || err "Unknown file"
  vim ${CONF}/template/${C}
  wait
  pushd ${CONF} >/dev/null 2>&1
  if [ `git status -s template/${C} |wc -l` -ne 0 ]; then
    git commit -m"template updated by ${USERNAME}" template/${C} >/dev/null 2>&1 || err "Error committing template change"
  fi
  popd >/dev/null 2>&1
}

function file_list {
  NUM=$( wc -l ${CONF}/file |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined file${S}."
  test $NUM -eq 0 && return || echo
  cat ${CONF}/file |awk 'BEGIN{FS=","}{print $1,$2}' |sort |column -t
}

function file_show {
  test $# -eq 1 || err "Provide the file name"
  grep -qE '^'$1',' ${CONF}/file || err "Unknown file" 
  read NAME PTH DESC <<< $( grep -E '^'$1',' ${CONF}/file |tr ',' ' ' )
  printf -- "Name: $NAME\nPath: $PTH\nDescription: $DESC"
}

function file_update {
  start_modify
  if [ -z "$1" ]; then
    file_list
    printf -- "\n"
    get_input C "File to Modify"
  else
    C="$1"
  fi
  grep -qE '^'$C',' ${CONF}/file || err "Unknown file"
  printf -- "\n"
  read NAME PTH DESC <<< $( grep -E '^'$C',' ${CONF}/file |tr ',' ' ' )
  get_input NAME "Name (for reference)" --default $NAME
  get_input PTH "Full Path (for deployment)" --default "$PTH" --nc
  get_input DESC "Description" --default "$DESC" --null --nc
  if [ "$NAME" != "$C" ]; then
    # validate unique name
    grep -qE '^'$NAME',' ${CONF}/file && err "File already defined."
    # move file
    pushd ${CONF} >/dev/null 2>&1
    git mv template/$C template/$NAME >/dev/null 2>&1
    popd >/dev/null 2>&1
  fi
  sed -i 's%^'$C',.*%'${NAME}','${PTH//,/_}','"${DESC//,/ }"'%' ${CONF}/file
  commit_file file
}

function location_create {
  start_modify
  # get user input and validate
  get_input CODE "Location Code (three characters)"
  test `printf -- "$CODE" |wc -c` -eq 3 || err "Error - the location code must be exactly three characters."
  get_input NAME "Name" --nc
  get_input DESC "Description" --nc --null
  # validate unique name
  grep -qE '^'$CODE',' $CONF/location && err "Location already defined."
  # add
  printf -- "${CODE},${NAME//,/ },${DESC//,/ }\n" >>$CONF/location
  commit_file location
  refresh_dirs
}

function location_delete {
  generic_delete location $1
}

function location_list {
  NUM=$( wc -l ${CONF}/location |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined location${S}."
  test $NUM -eq 0 && return || echo
  cat ${CONF}/location |awk 'BEGIN{FS=","}{print $1}' |sort
}

function location_show {
  test $# -eq 1 || err "Provide the location name"
  grep -qE '^'$1',' ${CONF}/location || err "Unknown location" 
  read CODE NAME DESC <<< $( grep -E '^'$1',' ${CONF}/location |tr ',' ' ' )
  printf -- "Code: $CODE\nName: $NAME\nDescription: $DESC"
}

function location_update {
  start_modify
  if [ -z "$1" ]; then
    location_list
    printf -- "\n"
    get_input C "Location to Modify"
  else
    C="$1"
  fi
  grep -qE '^'$C',' ${CONF}/location || err "Unknown location"
  printf -- "\n"
  read CODE NAME DESC <<< $( grep -E '^'$C',' ${CONF}/location |tr ',' ' ' )
  get_input CODE "Location Code (three characters)" --default $CODE
  test `printf -- "$CODE" |wc -c` -eq 3 || err "Error - the location code must be exactly three characters."
  get_input NAME "Name" --nc --default $NAME
  get_input DESC "Description" --nc --null --default "$DESC"
  sed -i 's/^'$C',.*/'${CODE}','${NAME}','"${DESC//,/ }"'/' ${CONF}/location
  commit_file location
}

function network_create {
  start_modify
  # get user input and validate
  get_input LOC "Location Code"
  grep -qE '^'$LOC',' ${CONF}/location || err "Unknown location"
  get_input ZONE "Network Zone" --options core,edge
  get_input ALIAS "Site Alias"
  # validate unique name
  grep -qE '^'$LOC','$ZONE','$ALIAS',' $CONF/network && err "Network already defined."
  get_input DESC "Description" --nc --null
  get_input NET "Network"
  get_input MASK "Subnet Mask"
  get_input BITS "Subnet Bits"
  get_input GW "Gateway Address"
  get_input VLAN "VLAN Tag/Number"
  # add
  printf -- "${LOC},${ZONE},${ALIAS},${NET},${MASK},${BITS},${GW},${VLAN},${DESC//,/ }\n" >>$CONF/network
  test ! -d ${CONF}/${LOC} && mkdir ${CONF}/${LOC}
  printf -- "${ZONE},${ALIAS},${NET}/${BITS}\n" >>${CONF}/${LOC}/network
  commit_file network ${CONF}/${LOC}/network
  refresh_dirs
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
  grep -qE '^'${C//-/,}',' ${CONF}/network || err "Unknown network"
  get_yn RL "Are you sure (y/n)? "
  if [ "$RL" == "y" ]; then
    read LOC ZONE ALIAS DISC <<< $( grep -E '^'${C//-/,}',' ${CONF}/network |tr ',' ' ' )
    sed -i '/^'${C//-/,}',/d' ${CONF}/network
    sed -i '/^'${ZONE}','${ALIAS}',/d' ${CONF}/${LOC}/network
  fi
  commit_file network ${CONF}/${LOC}/network
  refresh_dirs
}

function network_list {
  NUM=$( wc -l ${CONF}/network |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined network${S}."
  test $NUM -eq 0 && return || echo
  ( printf -- "Site Alias Network\n"; cat ${CONF}/network |awk 'BEGIN{FS=","}{print $1"-"$2,$3,$4"/"$6}' |sort ) |column -t
}

function network_show {
  test $# -eq 1 || err "Provide the network name (loc-zone-alias)"
  test `printf -- "$1" |sed 's/[^-]*//g' |wc -c` -eq 2 || err "Invalid format. Please ensure you are entering 'location-zone-alias'."
  grep -qE '^'${1//-/,}',' ${CONF}/network || err "Unknown network"
  read LOC ZONE ALIAS NET MASK BITS GW VLAN DESC <<< $( grep -E '^'${1//-/,}',' ${CONF}/network |tr ',' ' ' )
  printf -- "Location Code: $LOC\nNetwork Zone: $ZONE\nSite Alias: $ALIAS\nDescription: $DESC\nNetwork: $NET\nSubnet Mask: $MASK\nSubnet Bits: $BITS\nGateway Address: $GW\nVLAN Tag/Number: $VLAN"
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
  grep -qE '^'${C//-/,}',' ${CONF}/network || err "Unknown network"
  printf -- "\n"
  read L Z A NET MASK BITS GW VLAN DESC <<< $( grep -E '^'${C//-/,}',' ${CONF}/network |tr ',' ' ' )
  get_input LOC "Location Code" --default $L
  grep -qE '^'$LOC',' ${CONF}/location || err "Unknown location"
  get_input ZONE "Network Zone" --options core,edge --default $Z
  get_input ALIAS "Site Alias" --default $A
  # validate unique name if it is changing
  if [ "$LOC-$ZONE-$ALIAS" != "$C" ]; then
    grep -qE '^'$LOC','$ZONE','$ALIAS',' $CONF/network && err "Network already defined."
  fi
  get_input DESC "Description" --nc --null --default "$DESC"
  get_input NET "Network" --default $NET
  get_input MASK "Subnet Mask" --default $MASK
  get_input BITS "Subnet Bits" --default $BITS
  get_input GW "Gateway Address" --default $GW
  get_input VLAN "VLAN Tag/Number" --default $VLAN
  sed -i 's/^'${C//-/,}',.*/'${LOC}','${ZONE}','${ALIAS}','${NET}','${MASK}','${BITS}','${GW}','${VLAN}','"${DESC//,/ }"'/' ${CONF}/network
  if [ "$LOC" == "$L" ]; then
    # location is not changing, safe to update in place
    sed -i 's/^'${Z}','${A}',.*/'${ZONE}','${ALIAS}','${NET}'\/'${BITS}'/' ${CONF}/${LOC}/network
    commit_file network ${CONF}/${LOC}/network
  else
    # location changed, remove from old location and add to new
    sed -i '/^'${ZONE}','${ALIAS}',/d' ${CONF}/${L}/network
    test ! -d ${CONF}/${LOC} && mkdir ${CONF}/${LOC}
    printf -- "${ZONE},${ALIAS},${NET}/${BITS}\n" >>${CONF}/${LOC}/network
    commit_file network ${CONF}/${LOC}/network ${CONF}/${L}/network
  fi
}

function resource_create {
  start_modify
  # get user input and validate
  get_input TYPE "Type" --options ip,cluster_ip
  get_input VAL "Value" --nc
  get_input DESC "Description" --nc --null
  # validate unique value
  grep -qE ','${VAL//,/}',' $CONF/resource && err "Error - not a unique resource value."
  # add
  printf -- "${TYPE},${VAL//,/},${DESC//,/ }\n" >>$CONF/resource
  commit_file resource
}

function resource_delete {
  start_modify
  if [ -z "$1" ]; then
    resource_list
    printf -- "\n"
    get_input C "Resource to Delete (value)"
  else
    C="$1"
  fi
  grep -qE ','${C}',' ${CONF}/resource || err "Unknown resource"
  get_yn RL "Are you sure (y/n)? "
  if [ "$RL" == "y" ]; then
    sed -i '/,'${C}',/d' ${CONF}/resource
  fi
  commit_file resource
}

function resource_list {
  NUM=$( wc -l ${CONF}/resource |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined resource${S}."
  test $NUM -eq 0 && return || echo
  cat ${CONF}/resource |awk 'BEGIN{FS=","}{print $1,$2}' |sort |column -t
}

function resource_show {
  test $# -eq 1 || err "Provide the resource value"
  grep -qE ','$1',' ${CONF}/resource || err "Unknown resource" 
  read TYPE VAL DESC <<< $( grep -E ','$1',' ${CONF}/resource |tr ',' ' ' )
  printf -- "Type: $TYPE\nValue: $VAL\nDescription: $DESC"
}

function resource_update {
  start_modify
  if [ -z "$1" ]; then
    resource_list
    printf -- "\n"
    get_input C "Resource value to Modify"
  else
    C="$1"
  fi
  grep -qE ','$C',' ${CONF}/resource || err "Unknown resource"
  printf -- "\n"
  read TYPE VAL DESC <<< $( grep -E ','$C',' ${CONF}/resource |tr ',' ' ' )
  get_input TYPE "Type" --options ip,cluster_ip --default $TYPE
  get_input VAL "Value" --nc --default $VAL
  # validate unique value
  if [ "$VAL" != "$C" ]; then
    grep -qE ','${VAL//,/}',' $CONF/resource && err "Error - not a unique resource value."
  fi
  get_input DESC "Description" --nc --null --default "$DESC"
  sed -i 's/.*,'$C',.*/'${TYPE}','${VAL//,/}','"${DESC//,/ }"'/' ${CONF}/resource
  commit_file resource
}

function usage {
  echo "Manage application/server configurations and base templates across all environments.

Usage $0 subject verb [--option1] [--option2] [...]
              $0 commit
              $0 cancel

Run commit when complete to finalize changes.

Subject:
  application
  constant
  environment
  file
  location
  network
  resource

Verbs - All Subjects:
  create
  delete
  list
  show
  update

Verbs - File:
  edit
" >&2
  exit 1
}


# variables
CONF=/usr/local/etc/lpad/app-config
USERNAME=""

# set local variables
APP=""
ENV=""
FILE=""
PATCHDIR=/usr/local/etc/lpad/app-patches
TEMPLATEDIR=/usr/local/etc/lpad/app-templates
TMP=/tmp/generate-patch.$$

trap cleanup_and_exit EXIT INT

# initialize
test "`whoami`" == "root" || err "What madness is this? Ye art not auth'riz'd to doeth that."
which git >/dev/null 2>&1 || err "Please install git or correct your PATH"
if ! [ -d $CONF ]; then
  read -p "Configuration not found - this appears to be the first time running this script.  Do you want to initialize the configuration (y/n)? " P
  P=$( echo "$P" |tr 'A-Z' 'a-z' )
  test "$P" == "y" && initialize_configuration || exit 1
fi
test $# -ge 1 || usage

# get subject and verb
SUBJ="$( echo "$1" |tr 'A-Z' 'a-z' )"; shift
VERB="$( echo "$1" |tr 'A-Z' 'a-z' )"; shift

# intercept non subject/verb commands
if [ "$SUBJ" == "commit" ]; then stop_modify; exit 0; fi
if [ "$SUBJ" == "cancel" ]; then cancel_modify; exit 0; fi

# if no verb is provided default to list, since it is available for all subjects
if [ -z "$VERB" ]; then VERB="list"; fi

# validate subject and verb
printf -- " application constant environment file location network resource " |grep -q " $SUBJ "
[[ $? -ne 0 || -z "$SUBJ" ]] && usage
printf -- " create delete list show update edit " |grep -q " $VERB "
[[ $? -ne 0 || -z "$VERB" ]] && usage
[[ "$VERB" == "edit" && "$SUBJ" != "file" ]] && usage

# call function with remaining arguments
eval ${SUBJ}_${VERB} $@


# --------
# END
exit 3
#
# --------

# parse remaining arguments
#while [ $# -ge 1 ]; do case $( echo $1 |tr 'A-Z' 'a-z' ) in
#  *) if [[ -z "$APP" || -z "$ENV" ]]; then usage; else FILE="$1"; fi;;
#esac; shift; done

#  affiliates|ctm|deskpro|e4x|ea|etl|expression-engine|finance|jasper|pentaho|prod-admin|purchase|purchase-api|rubix|v2|va) APP=$( echo $1 |tr 'A-Z' 'a-z' );;

# set file names based on convention
PATCHFILE="$ENV-$APP-$FILE"
TEMPLATE="$APP-$FILE"

# sanity check
test -d $PATCHDIR || err "Patch directory does not exist!"
test -d $TEMPLATEDIR || err "Template directory does not exist!"
test -s $TEMPLATEDIR/$TEMPLATE || err "Template '$TEMPLATE' does not exist!"

# put the template in a temporary folder and patch it, if a patch exists already
mkdir -m0700 -p $TMP
cat $TEMPLATEDIR/$TEMPLATE >$TMP/$TEMPLATE
if [ -s $PATCHDIR/$PATCHFILE ]; then
  patch -p0 $TMP/$TEMPLATE <$PATCHDIR/$PATCHFILE || err "Unable to patch template!"
  cat $TMP/$TEMPLATE >$TMP/$TEMPLATE.ORIG
  sleep 1
fi

# open the file for editing by the user
vim $TMP/$TEMPLATE
wait

# do nothing further if there were no changes made
if [ -s $PATCHDIR/$PATCHFILE ]; then
  if [ `md5sum $TMP/$TEMPLATE{.ORIG,} |cut -d' ' -f1 |uniq |wc -l` -eq 1 ]; then
    echo "No changes were made."; exit 0
  fi
fi

# generate a new patch file against the original template
diff -c $TEMPLATEDIR/$TEMPLATE $TMP/$TEMPLATE >$TMP/$PATCHFILE

# confirm changes if this isn't a new patch
if [ -s $PATCHDIR/$PATCHFILE ]; then
  echo -e "Please confirm the change to the patch:\n"
  diff $PATCHDIR/$PATCHFILE $TMP/$PATCHFILE
  echo -e "\n\n"
  read -p "Look OK? (y/n) " C
  C=$( echo $C |tr 'A-Z' 'a-z' )
  test "$C" != "y" && err "Aborted!"
fi

# write the new patch file
cat $TMP/$PATCHFILE >$PATCHDIR/$PATCHFILE
echo "Wrote $( wc -c $PATCHDIR/$PATCHFILE |cut -d' ' -f1 ) bytes to $PATCHFILE. Please make sure to commit your changes."

exit 0
