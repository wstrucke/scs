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
#     build                                                file
#     constant                                             file
#     environment                                          file
#     file                                                 file
#     file-map                                             application to file map
#     location                                             file
#     network                                              file
#     resource                                             file
#     system                                               file
#     template/                                            directory containing global application templates
#     template/patch/<environment>/                        directory containing template patches for the environment
#     <location>/                                          directory
#     <location>/network                                   file to list networks available at the location
#     <location>/<environment>/                            directory
#     <location>/<environment>/constant                    file
#     <location>/<environment>/<application>/              directory
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
  mkdir -p $CONF/template/patch
  git init --quiet $CONF
  touch $CONF/{application,constant,environment,file,file-map,location,network,resource,system}
  cd $CONF || err
  git add *
  git commit -a -m'initial commit' >/dev/null 2>&1
  cd - >/dev/null 2>&1
  return 0
}

function cleanup_and_exit {
  test -d $TMP && rm -rf $TMP
  test -f /tmp/app-config.$$ && rm -f /tmp/app-config.$$
  printf -- "\n"
  exit 0
}

function diff_master {
  pushd $CONF >/dev/null 2>&1
  git diff master
  popd >/dev/null 2>&1
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
    read -r -p "You have accessed root with a non-standard environment. What is your username? [root]? " U
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
  if [[ "$1" == "-m" && ! -z "$2" ]]; then MSG="$2"; else MSG="$USERNAME completed modifications at `date`"; fi
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
  git merge --squash $USERNAME >/dev/null 2>&1
  if [ $? -ne 0 ]; then git stash >/dev/null 2>&1; git checkout $USERNAME >/dev/null 2>&1; err "Error merging changes into master."; fi
  git commit -a -m"$MSG" >/dev/null 2>&1
  git branch -D $USERNAME >/dev/null 2>&1
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
  LC=1; RL=""; P="$2"; V="$1"; D=""; NUL=0; OPT=""; shift 2
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
    read -r RL; if [ $LC -eq 1 ]; then RL=$( printf -- "$RL" |tr 'A-Z' 'a-z' ); fi
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
  test ! -z "$2" && grep -qE "$M$2," ${CONF}/$1
  if [ $? -ne 0 ]; then
    eval $1_list "$4"
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
  refresh_dirs
}

function application_delete {
  generic_delete application $1
# should also remove entry from file-map here
#  sed -i "/^$F,$APP/d" $CONF/file-map
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
  test -z "$1" && shift
  generic_choose application "$1" APP && shift
  # get the requested file or abort
  generic_choose file "$1" F && shift
  # confirm
  get_yn RL "Are you sure (y/n)? "
  if [ "$RL" != "y" ]; then return; fi
  # remove the mapping if it exists
  grep -qE "^$F,$APP\$" $CONF/file-map || err "Error - requested file is not assocaited with $APP."
  sed -i "/^$F,$APP/d" $CONF/file-map
  commit_file file-map
}

function application_list {
  NUM=$( wc -l $CONF/application |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined application${S}."
  test $NUM -eq 0 && return
  cat $CONF/application |awk 'BEGIN{FS=","}{print $1}' |sort |sed 's/^/   /'
}

function application_show {
  test $# -eq 1 || err "Provide the application name"
  APP="$1"
  grep -qE "^$APP," $CONF/application || err "Invalid application"
  IFS="," read -r APP ALIAS BUILD CLUSTER <<< "$( grep -E "^$APP," ${CONF}/application )"
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
  grep -qE "^$APP," $CONF/application || err "Invalid application"
  printf -- "\n"
  IFS="," read -r APP ALIAS BUILD CLUSTER <<< "$( grep -E "^$APP," ${CONF}/application )"
  get_input NAME "Name" --default "$APP"
  get_input ALIAS "Alias" --default "$ALIAS"
  get_input BUILD "Build" --default "$BUILD" --null --options "$( build_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  get_yn CLUSTER "LVS Support (y/n)"
  sed -i 's/^'$APP',.*/'${NAME}','${ALIAS}','${BUILD}','${CLUSTER}'/' ${CONF}/application
  commit_file application
}

function build_create {
  start_modify
  # get user input and validate
  get_input NAME "Build"
  get_input ROLE "Role" --null
  get_input DESC "Description" --nc --null
  # validate unique name
  grep -qE "^$NAME," $CONF/build && err "Build already defined."
  # add
  printf -- "${NAME},${ROLE},${DESC//,/}\n" >>$CONF/build
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
  cat ${CONF}/build |awk 'BEGIN{FS=","}{print $1}' |sort
}

function build_show {
  test $# -eq 1 || err "Provide the build name"
  grep -qE "^$1," ${CONF}/build || err "Unknown build"
  IFS="," read -r NAME ROLE DESC <<< "$( grep -E "^$1," ${CONF}/build )"
  printf -- "Build: $NAME\nRole: $ROLE\nDescription: $DESC"
}

function build_update {
  start_modify
  generic_choose build "$1" C && shift
  IFS="," read -r NAME ROLE DESC <<< "$( grep -E "^$C," ${CONF}/build )"
  get_input NAME "Build" --default "$NAME"
  get_input ROLE "Role" --default "$ROLE" --null
  get_input DESC "Description" --default "$DESC" --nc --null
  sed -i 's/^'$C',.*/'${NAME}','${ROLE}','"${DESC//,/}"'/' ${CONF}/build
  commit_file build
}

function constant_create {
  start_modify
  # get user input and validate
  get_input NAME "Name" --nc
  get_input DESC "Description" --nc
  # force uppercase for constants
  NAME=$( printf -- "$NAME" | tr 'a-z' 'A-Z' )
  # validate unique name
  grep -qE "^$NAME," $CONF/constant && err "Constant already defined."
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
  test $NUM -eq 0 && return
  cat ${CONF}/constant |awk 'BEGIN{FS=","}{print $1}' |sort |sed 's/^/   /'
}

function constant_show {
  test $# -eq 1 || err "Provide the constant name"
  C="$( printf -- "$1" |tr 'a-z' 'A-Z' )"
  grep -qE "^$C," ${CONF}/constant || err "Unknown constant"
  IFS="," read -r NAME DESC <<< "$( grep -E "^$C," ${CONF}/constant )"
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
  grep -qE "^$C," ${CONF}/constant || err "Unknown constant"
  printf -- "\n"
  IFS="," read -r NAME DESC <<< "$( grep -E "^$C," ${CONF}/constant )"
  get_input NAME "Name" --default "$NAME"
  get_input DESC "Description" --default "$DESC"
  sed -i 's/^'$C',.*/'${NAME}','"${DESC//,/ }"'/' ${CONF}/constant
  commit_file constant
}

# manipulate applications at a specific environment at a specific location
#
# application [--add|--remove|--list]
# application --name <name> [--define|--undefine|--list-constant]
# application --name <name> [--assign-resource|--unassign-resource|--list-resource]
#
function environment_application {
  # get the requested location or abort
  generic_choose location "$1" LOC && shift
  # get the requested environment or abort
  generic_choose environment "$1" ENV && shift
  test -d ${CONF}/${LOC}/${ENV} || err "Error - please create $ENV at $LOC first."
  C="$1"; shift
  case "$C" in
    --add) environment_application_add $LOC $ENV $@;;
    --name) environment_application_byname $LOC $ENV $@;;
    --remove) environment_application_remove $LOC $ENV $@;;
    *) environment_application_list $LOC $ENV $@;;
  esac
}

function environment_application_add {
  LOC=$1; shift; ENV=$1; shift;
  # get the requested application or abort
  generic_choose application "$1" APP && shift
  # assign the application
  pushd $CONF >/dev/null 2>&1
  test -d ${LOC}/$ENV/$APP || mkdir ${LOC}/$ENV/$APP
  touch ${LOC}/$ENV/$APP/constant
  git add ${LOC}/$ENV/$APP/constant >/dev/null 2>&1
  git commit -m"${USERNAME} added $APP to $ENV at $LOC" ${LOC}/$ENV/$APP/constant >/dev/null 2>&1 || err "Error committing change to the repository"
  popd >/dev/null 2>&1
}

# manage applications in an environment at a location
#
# application --name <name> [--define|--undefine|--list-constant]
# application --name <name> [--assign-resource|--unassign-resource|--list-resource]
#
function environment_application_byname {
  LOC=$1; shift; ENV=$1; shift;
  # get the requested application or abort
  generic_choose application "$1" APP && shift
  test -d ${CONF}/${LOC}/${ENV}/${APP} || err "Error - please add $APP to $LOC $ENV before managing it."
  C="$1"; shift
  case "$C" in
    --define) environment_application_byname_define $LOC $ENV $APP $@;;
    --undefine) environment_application_byname_undefine $LOC $ENV $APP $@;;
    --list-constant) environment_application_byname_list_constant $LOC $ENV $APP $@;;
    --assign-resource) environment_application_byname_assign $LOC $ENV $APP $@;;
    --unassign-resource) environment_application_byname_unassign $LOC $ENV $APP $@;;
    --list-resource) environment_application_byname_list_resource $LOC $ENV $APP $@;;
  esac
}

function environment_application_byname_define {
  err 'Not implemented'
}

function environment_application_byname_undefine {
  err 'Not implemented'
}

function environment_application_byname_list_constant {
  err 'Not implemented'
}

function environment_application_byname_assign {
  LOC=$1; ENV=$2; APP=$3; shift 3
  # select an available resource to assign
  generic_choose resource "$1" RES "^cluster_ip,.*,not assigned," && shift
  # verify the resource is available for this purpose
  grep -E ",${RES//,/}," $CONF/resource |grep -qE '^cluster_ip,.*,not assigned,' || err "Error - invalid or unavailable resource."
  # assign resource, update index
  IFS="," read -r TYPE VAL ASSIGN_TYPE ASSIGN_TO DESC <<< "$( grep -E ",$RES," ${CONF}/resource )"
  sed -i 's/.*,'$RES',.*/'$TYPE','$VAL',application,'$LOC':'$ENV':'$APP','"$DESC"'/' ${CONF}/resource
  commit_file resource
}

function environment_application_byname_unassign {
  LOC=$1; ENV=$2; APP=$3; shift 3
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
  resource_list ",application,$1:$2:$3,"
}

function environment_application_list {
  test -d ${CONF}/$1/$2 && NUM=$( find ${CONF}/$1/$2/ -type d |sed 's%'"${CONF}/$1/$2"'/%%' |grep -vE '^(\.|template|$)' |wc -l ) || NUM=0
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined application${S} at $1 $2."
  test $NUM -eq 0 && return
  find ${CONF}/$1/$2/ -type d |sed 's%'"${CONF}/$1/$2"'/%%' |grep -vE '^(\.|template|$)' |sort |sed 's/^/   /'
}

function environment_application_remove {
  LOC=$1; shift; ENV=$1; shift;
  generic_choose application "$1" APP && shift
  printf -- "Removing $APP from $LOC $ENV, deleting all configurations, files, resources, constants, et cetera...\n"
  get_yn RL "Are you sure (y/n)? "; test "$RL" != "y" && return
  # assign the application
  pushd $CONF >/dev/null 2>&1
  test -d ${LOC}/$ENV/$APP && git rm -rf ${LOC}/$ENV/$APP >/dev/null 2>&1
  git commit -m"${USERNAME} removed $APP from $ENV at $LOC" >/dev/null 2>&1 || err "Error committing change to the repository"
  popd >/dev/null 2>&1
}

function environment_constant {
  err "Not Implemented"
  # constant [--define|--undefine|--list]
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
  mkdir -p $CONF/template/patch/${NAME} >/dev/null 2>&1
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
  test $NUM -eq 0 && return
  cat ${CONF}/environment |awk 'BEGIN{FS=","}{print $1}' |sort |sed 's/^/   /'
}

function environment_show {
  test $# -eq 1 || err "Provide the environment name"
  grep -qE "^$1," ${CONF}/environment || err "Unknown environment" 
  IFS="," read -r NAME ALIAS DESC <<< "$( grep -E "^$1," ${CONF}/environment )"
  printf -- "Name: $NAME\nAlias: $ALIAS\nDescription: $DESC"
  # also show installed locations
  NUM=$( find $CONF -name $NAME -type d |grep -v template |wc -l )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo -e "\n\nThere ${A} ${NUM} linked location${S}."
  if [ $NUM -gt 0 ]; then
    find $CONF -name $NAME -type d |grep -v template |sed -r 's%'$CONF'/(.{3}).*%   \1%'
  fi
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
  sed -i 's/^'$C',.*/'${NAME}','${ALIAS}','"${DESC//,/ }"'/' ${CONF}/environment
  # handle rename
  if [ "$NAME" != "$C" ]; then
    pushd ${CONF} >/dev/null 2>&1
    test -d template/patch/$C && git mv template/patch/$C template/patch/$NAME >/dev/null 2>&1
    for L in $( cat ${CONF}/location |awk 'BEGIN{FS=","}{print $1}' ); do
      test -d $L/$C && git mv $L/$C $L/$NAME >/dev/null 2>&1
    done
    popd >/dev/null 2>&1
  fi
  commit_file environment
}

function file_create {
  start_modify
  # get user input and validate
  get_input NAME "Name (for reference)" --nc
  get_input PTH "Full Path (for deployment)" --nc
  get_input DESC "Description" --nc --null
  # validate unique name
  grep -qE "^$NAME," ${CONF}/file && err "File already defined."
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
  generic_choose file "$1" C && shift
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
# should also remove entry from file-map here
#  sed -i "/^$F,$APP/d" $CONF/file-map
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
    diff $CONF/template/$ENV/$C $TMP/$C.patch
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
    vim ${CONF}/template/${C}
    wait
    pushd ${CONF} >/dev/null 2>&1
    if [ `git status -s template/${C} |wc -l` -ne 0 ]; then
      git commit -m"template updated by ${USERNAME}" template/${C} >/dev/null 2>&1 || err "Error committing template change"
    fi
    popd >/dev/null 2>&1
  fi
}

function file_list {
  NUM=$( wc -l ${CONF}/file |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined file${S}."
  test $NUM -eq 0 && return
  cat ${CONF}/file |awk 'BEGIN{FS=","}{print $1,$2}' |sort |column -t |sed 's/^/   /'
}

function file_show {
  test $# -eq 1 || err "Provide the file name"
  grep -qE "^$1," ${CONF}/file || err "Unknown file" 
  IFS="," read -r NAME PTH DESC <<< "$( grep -E "^$1," ${CONF}/file )"
  printf -- "Name: $NAME\nPath: $PTH\nDescription: $DESC"
}

function file_update {
  start_modify
  generic_choose file "$1" C && shift
  IFS="," read -r NAME PTH DESC <<< "$( grep -E "^$C," ${CONF}/file )"
  get_input NAME "Name (for reference)" --default "$NAME"
  get_input PTH "Full Path (for deployment)" --default "$PTH" --nc
  get_input DESC "Description" --default "$DESC" --null --nc
  if [ "$NAME" != "$C" ]; then
    # validate unique name
    grep -qE "^$NAME," ${CONF}/file && err "File already defined."
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
  grep -qE "^$CODE," $CONF/location && err "Location already defined."
  # add
  printf -- "${CODE},${NAME//,/ },${DESC//,/ }\n" >>$CONF/location
  commit_file location
  refresh_dirs
}

function location_delete {
  generic_delete location $1
}

function location_environment {
  # get the requested location or abort
  generic_choose location "$1" LOC && shift
  # get the command to process
  C="$1"; shift
  case "$C" in
    --assign) location_environment_assign $LOC $@;;
    --unassign) location_environment_unassign $LOC $@;;
    *) location_environment_list $LOC $@;;
  esac
}

function location_environment_assign {
  LOC=$1; shift
  # get the requested environment or abort
  generic_choose environment "$1" ENV && shift
  # assign the environment
  pushd $CONF >/dev/null 2>&1
  test -d ${LOC}/$ENV || mkdir ${LOC}/$ENV
  touch ${LOC}/$ENV/constant
  git add ${LOC}/$ENV/constant >/dev/null 2>&1
  git commit -m"${USERNAME} added $ENV to $LOC" ${LOC}/$ENV/constant >/dev/null 2>&1 || err "Error committing change to the repository"
  popd >/dev/null 2>&1
}

function location_environment_list {
  test -d ${CONF}/$1 && NUM=$( find ${CONF}/$1/ -type d |sed 's%'"${CONF}/$1"'/%%' |grep -vE '^(\.|template|$)' |wc -l ) || NUM=0
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined environment${S} at $1."
  test $NUM -eq 0 && return
  find ${CONF}/$1/ -type d |sed 's%'"${CONF}/$1"'/%%' |grep -vE '^(\.|template|$)' |sort |sed 's/^/   /'
}

function location_environment_unassign {
  LOC=$1; shift
  # get the requested environment or abort
  generic_choose environment "$1" ENV && shift
  printf -- "Removing $ENV from location $LOC, deleting all configurations, files, resources, constants, et cetera...\n"
  get_yn RL "Are you sure (y/n)? "; test "$RL" != "y" && return
  # unassign the environment
  pushd $CONF >/dev/null 2>&1
  test -d ${LOC}/$ENV && git rm -rf ${LOC}/$ENV >/dev/null 2>&1
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
  cat ${CONF}/location |awk 'BEGIN{FS=","}{print $1}' |sort
}

function location_show {
  test $# -eq 1 || err "Provide the location name"
  grep -qE "^$1," ${CONF}/location || err "Unknown location" 
  IFS="," read -r CODE NAME DESC <<< "$( grep -E "^$1," ${CONF}/location )"
  printf -- "Code: $CODE\nName: $NAME\nDescription: $DESC"
}

function location_update {
  start_modify
  generic_choose location "$1" C && shift
  IFS="," read -r CODE NAME DESC <<< "$( grep -E "^$C," ${CONF}/location )"
  get_input CODE "Location Code (three characters)" --default "$CODE"
  test `printf -- "$CODE" |wc -c` -eq 3 || err "Error - the location code must be exactly three characters."
  get_input NAME "Name" --nc --default "$NAME"
  get_input DESC "Description" --nc --null --default "$DESC"
  sed -i 's/^'$C',.*/'${CODE}','"${NAME}"','"${DESC//,/ }"'/' ${CONF}/location
  # handle rename
  if [ "$CODE" != "$C" ]; then
    pushd $CONF >/dev/null 2>&1
    test -d $C && git mv $C $CODE >/dev/null 2>&1
    sed -i 's/^'$C',/'$CODE',/' network
    popd >/dev/null 2>&1
  fi
  commit_file location
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
  get_input NET "Network"
  get_input MASK "Subnet Mask"
  get_input BITS "Subnet Bits"
  get_input GW "Gateway Address" --null
  get_input VLAN "VLAN Tag/Number" --null
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
  grep -qE "^${C//-/,}," ${CONF}/network || err "Unknown network"
  get_yn RL "Are you sure (y/n)? "
  if [ "$RL" == "y" ]; then
    IFS="," read -r LOC ZONE ALIAS DISC <<< "$( grep -E "^${C//-/,}," ${CONF}/network )"
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
  test $NUM -eq 0 && return
  ( printf -- "Site Alias Network\n"; cat ${CONF}/network |awk 'BEGIN{FS=","}{print $1"-"$2,$3,$4"/"$6}' |sort ) |column -t |sed 's/^/   /'
}

function network_show {
  test $# -eq 1 || err "Provide the network name (loc-zone-alias)"
  test `printf -- "$1" |sed 's/[^-]*//g' |wc -c` -eq 2 || err "Invalid format. Please ensure you are entering 'location-zone-alias'."
  grep -qE "^${1//-/,}," ${CONF}/network || err "Unknown network"
  IFS="," read -r LOC ZONE ALIAS NET MASK BITS GW VLAN DESC <<< "$( grep -E "^${1//-/,}," ${CONF}/network )"
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
  grep -qE "^${C//-/,}," ${CONF}/network || err "Unknown network"
  printf -- "\n"
  IFS="," read -r L Z A NET MASK BITS GW VLAN DESC <<< "$( grep -E "^${C//-/,}," ${CONF}/network )"
  get_input LOC "Location Code" --default "$L" --options "$( location_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  get_input ZONE "Network Zone" --options core,edge --default "$Z"
  get_input ALIAS "Site Alias" --default "$A"
  # validate unique name if it is changing
  if [ "$LOC-$ZONE-$ALIAS" != "$C" ]; then
    grep -qE "^$LOC,$ZONE,$ALIAS," $CONF/network && err "Network already defined."
  fi
  get_input DESC "Description" --nc --null --default "$DESC"
  get_input NET "Network" --default "$NET"
  get_input MASK "Subnet Mask" --default "$MASK"
  get_input BITS "Subnet Bits" --default "$BITS"
  get_input GW "Gateway Address" --default "$GW" --null
  get_input VLAN "VLAN Tag/Number" --default "$VLAN" --null
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

function resource_byval {
  err "Not Implemented"
  # <value> [--assign-host|--unassign-host|--list]
}

# resource field format:
#   type,value,assignment_type(application,host),assigned_to,description
#
function resource_create {
  start_modify
  # get user input and validate
  get_input TYPE "Type" --options ip,cluster_ip,ha_ip
  get_input VAL "Value" --nc
  get_input DESC "Description" --nc --null
  # validate unique value
  grep -qE ",${VAL//,/}," $CONF/resource && err "Error - not a unique resource value."
  # add
  printf -- "${TYPE},${VAL//,/},,not assigned,${DESC//,/ }\n" >>$CONF/resource
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
  if ! [ -z "$1" ]; then
    grep -E "$1" ${CONF}/resource |awk 'BEGIN{FS=","}{print $1,$2}' |sort |column -t |sed 's/^/   /'
  else
    cat ${CONF}/resource |awk 'BEGIN{FS=","}{print $1,$2}' |sort |column -t |sed 's/^/   /'
  fi
}

function resource_show {
  test $# -eq 1 || err "Provide the resource value"
  grep -qE ",$1," ${CONF}/resource || err "Unknown resource" 
  IFS="," read -r TYPE VAL ASSIGN_TYPE ASSIGN_TO DESC <<< "$( grep -E ",$1," ${CONF}/resource )"
  printf -- "Type: $TYPE\nValue: $VAL\nDescription: $DESC\nAssigned to $ASSIGN_TYPE: $ASSIGN_TO"
}

function resource_update {
  start_modify
  generic_choose resource "$1" C && shift
  IFS="," read -r TYPE VAL ASSIGN_TYPE ASSIGN_TO DESC <<< "$( grep -E ",$C," ${CONF}/resource )"
  get_input TYPE "Type" --options ip,cluster_ip,ha_ip --default "$TYPE"
  get_input VAL "Value" --nc --default "$VAL"
  # validate unique value
  if [ "$VAL" != "$C" ]; then
    grep -qE ",${VAL//,/}," $CONF/resource && err "Error - not a unique resource value."
  fi
  get_input DESC "Description" --nc --null --default "$DESC"
  sed -i 's/.*,'$C',.*/'${TYPE}','${VAL//,/}','"$ASSIGN_TYPE"','"$ASSIGN_TO"','"${DESC//,/ }"'/' ${CONF}/resource
  commit_file resource
}

function system_create {
  start_modify
  # get user input and validate
  get_input NAME "Hostname"
  get_input BUILD "Build" --null --options "$( build_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  get_input IP "Primary IP"
  get_input LOC "Location" --options "$( location_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  # validate unique name
  grep -qE "^$NAME," $CONF/system && err "System already defined."
  # add
  printf -- "${NAME},${BUILD//,/ },${IP},${LOC}\n" >>$CONF/system
  commit_file system
}

function system_delete {
  generic_delete system $1
}

function system_list {
  NUM=$( wc -l ${CONF}/system |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined system${S}."
  test $NUM -eq 0 && return
  cat ${CONF}/system |awk 'BEGIN{FS=","}{print $1}' |sort |sed 's/^/   /'
}

function system_show {
  test $# -eq 1 || err "Provide the system name"
  grep -qE "^$1," ${CONF}/system || err "Unknown system"
  IFS="," read -r NAME BUILD IP LOC <<< "$( grep -E "^$1," ${CONF}/system )"
  printf -- "Name: $NAME\nBuild: $BUILD\nIP: $IP\nLocation: $LOC\n"
  # look up the applications configured for the build assigned to this system
  if ! [ -z "$BUILD" ]; then
    NUM=$( grep -E ",${BUILD}," ${CONF}/application |wc -l )
    if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
    echo -e "\nThere ${A} ${NUM} linked application${S}."
    if [ $NUM -gt 0 ]; then
      grep -E ",${BUILD}," ${CONF}/application |awk 'BEGIN{FS=","}{print $1}' |sed 's/^/   /'
      :>/tmp/app-config.$$
      for APP in $( grep -E ",${BUILD}," ${CONF}/application |awk 'BEGIN{FS=","}{print $1}' ); do
        grep -E ",${APP}\$" ${CONF}/file-map |awk 'BEGIN{FS=","}{print $1}' >>/tmp/app-config.$$
      done
      echo -e "\nConfiguration files:"
      for FILE in $( cat /tmp/app-config.$$ |sort |uniq ); do
        grep -E "^${FILE}," ${CONF}/file |awk 'BEGIN{FS=","}{print $2}' |sed 's/^/   /'
      done
    fi
  fi
}

function system_update {
  start_modify
  generic_choose system "$1" C && shift
  IFS="," read -r NAME BUILD IP LOC <<< "$( grep -E "^$C," ${CONF}/system )"
  get_input NAME "Hostname" --default "$NAME"
  get_input BUILD "Build" --default "$BUILD" --null --options "$( build_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  get_input IP "Primary IP" --default "$IP"
  get_input LOC "Location" --default "$LOC" --options "$( location_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )" 
  sed -i 's/^'$C',.*/'${NAME}','${BUILD}','${IP}','${LOC}'/' ${CONF}/system
  commit_file system
}

function usage {
  echo "Manage application/server configurations and base templates across all environments.

Usage $0 component (sub-component|verb) [--option1] [--option2] [...]
              $0 commit [-m 'commit message']
              $0 cancel
              $0 diff

Run commit when complete to finalize changes.

Component:
  application
    file [--add|--remove|--list]
  build
  constant
  environment
    application [--add|--remove|--list]
    application --name <name> [--define|--undefine|--list-constant]
    application --name <name> [--assign-resource|--unassign-resource|--list-resource]
    constant [--define|--undefine|--list]
  file
    edit [<name>] [--environment <name>]
  location
    [<name>] [--assign|--unassign|--list]
  network
  resource
    <value> [--assign-host|--unassign-host|--list]
  system
    <value> [--release]

Verbs - all top level components:
  create
  delete [<name>]
  list
  show [<name>]
  update [<name>]
" >&2
  exit 1
}

# variables
CONF=/usr/local/etc/lpad/app-config
TMP=/tmp/generate-patch.$$
USERNAME=""

# set local variables
APP=""
ENV=""
FILE=""

trap cleanup_and_exit EXIT INT

# initialize
test "`whoami`" == "root" || err "What madness is this? Ye art not auth'riz'd to doeth that."
which git >/dev/null 2>&1 || err "Please install git or correct your PATH"
if ! [ -d $CONF ]; then
  read -r -p "Configuration not found - this appears to be the first time running this script.  Do you want to initialize the configuration (y/n)? " P
  P=$( echo "$P" |tr 'A-Z' 'a-z' )
  test "$P" == "y" && initialize_configuration || exit 1
fi
test $# -ge 1 || usage

# get subject
SUBJ="$( echo "$1" |tr 'A-Z' 'a-z' )"; shift

# intercept non subject/verb commands
if [ "$SUBJ" == "commit" ]; then stop_modify $@; exit 0; fi
if [ "$SUBJ" == "cancel" ]; then cancel_modify; exit 0; fi
if [ "$SUBJ" == "diff" ]; then diff_master; exit 0; fi

# get verb
VERB="$( echo "$1" |tr 'A-Z' 'a-z' )"; shift

# if no verb is provided default to list, since it is available for all subjects
if [ -z "$VERB" ]; then VERB="list"; fi

# validate subject and verb
printf -- " application build constant environment file location network resource system " |grep -q " $SUBJ "
[[ $? -ne 0 || -z "$SUBJ" ]] && usage
if [[ "$SUBJ" != "resource" && "$SUBJ" != "location" ]]; then
  printf -- " create delete list show update edit file application constant environment " |grep -q " $VERB "
  [[ $? -ne 0 || -z "$VERB" ]] && usage
fi
[[ "$VERB" == "edit" && "$SUBJ" != "file" ]] && usage
[[ "$VERB" == "file" && "$SUBJ" != "application" ]] && usage
[[ "$VERB" == "application" && "$SUBJ" != "environment" ]] && usage
[[ "$VERB" == "constant" && "$SUBJ" != "environment" ]] && usage
[[ "$VERB" == "environment" && "$SUBJ" != "location" ]] && usage

# call function with remaining arguments
if [ "$SUBJ" == "resource" ]; then
  case "$VERB" in
    create|delete|list|show|update) eval ${SUBJ}_${VERB} $@;;
    *) resource_byval $@;;
  esac
elif [ "$SUBJ" == "location" ]; then
  case "$VERB" in
    create|delete|list|show|update) eval ${SUBJ}_${VERB} $@;;
    *) location_environment $@;;
  esac
else
  eval ${SUBJ}_${VERB} $@
fi
