#!/bin/bash
#
# LPAD Application Configuration
# Manage and deploy application configuration files
#
# William Strucke [wstrucke@gmail.com]
# Version 1.0.0, May 2014
#
# Configuration Storage:
#   /usr/local/etc/lpad/app-config/
#     application                                          file
#     binary                                               directory containing binary files
#     build                                                file
#     constant                                             constant index
#     environment                                          file
#     file                                                 file
#     file-map                                             application to file map
#     location                                             file
#     network                                              file
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
# Locks are taken by using git branches
#
# A constant is a variable with a static value globally, per environment, or per application in an environment. (Scope)
# A constant has a globally unique name with a fixed value in the scope it is defined in and is in only one scope (never duplicated).
#
# A resource is a pre-defined type with a globally unique value (e.g. an IP address).  That value can be assigned to either a host or an application in an environment.
#
# Use constants and resources in configuration files -- this is the whole point of lpac, mind you -- with this syntax:
#  {% resource.name %}
#  {% constant.name %}
#  {% system.name %}, {% system.ip %}, {% system.location %}, {% system.environment %}
#
# TO DO:
#   - system audit should check ownership and permissions on files
#

# first run function to init the configuration store
#
function initialize_configuration {
  test -d $CONF && exit 2
  mkdir -p $CONF/template/patch $CONF/{binary,value}
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
  test -f /tmp/app-config.$$ && rm -f /tmp/app-config.$$*
#  printf -- "\n"
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
    git branch -d $USERNAME >/dev/null 2>&1
  fi
  popd >/dev/null 2>&1
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
  LC=1; RL=""; P="$2"; V="$1"; D=""; NUL=0; OPT=""; RE=""; COMMA=0; shift 2
  while [ $# -gt 0 ]; do case $1 in
    --default) D="$2"; shift;;
    --nc) LC=0;;
    --null) NUL=1;;
    --options) OPT="$2"; shift;;
    --regex) RE="$2"; shift;;
    --comma) COMMA=1;;
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
    # special case to clear an existing value
    if [[ "$RL" == "null" || "$RL" == "NULL" ]]; then RL=""; fi
    # if no input was provied and null values are allowed, stop collecting input here
    [[ -z "$RL" && $NUL -eq 1 ]] && break
    # if there is a list of limited options clear the provided input unless it matches the list
    if ! [ -z "$OPT" ]; then printf -- ",$OPT," |grep -q ",$RL," || RL=""; fi
    # if a validation regex was provided, check the input against it
    if ! [ -z "$RE" ]; then printf -- "$RL" |grep -qE "$RE" || RL=""; fi
    # finally, enforce no comma rule
    if [ $COMMA -eq 0 ]; then printf -- "$RL" |grep -qE '[^,]*' && RL=""; fi
  done
  # set the provided variable value to the validated input
  eval "$V='$RL'"
}
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
  test ! -z "$2" && grep -qiE "$M$2," ${CONF}/$1
  if [ $? -ne 0 ]; then
    eval $1_list "$4"
    printf -- "\n"
    get_input I "Please specify $AN $1"
    test "$1" == "constant" && I=$( printf -- $I |tr 'a-z' 'A-Z' )
    grep -qE "$M$I," ${CONF}/$1 || err "Unknown $1" 
    printf -- "\n"
    eval $3="$I"
    return 1
  elif [ "$1" == "constant" ]; then
    eval $3=$( printf -- $2 |tr 'a-z' 'A-Z' )
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

function application_delete {
  generic_delete application $1 || return
  # delete from file-map as well
  sed -i "/^[^,]*,$APP\$/d" $CONF/file-map
  commit_file file-map
# should also unassign resources
# should also undefine constants
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
  awk 'BEGIN{FS=","}{print $1}' ${CONF}/build |sort
}

function build_show {
  test $# -eq 1 || err "Provide the build name"
  grep -qE "^$1," ${CONF}/build || err "Unknown build"
  IFS="," read -r NAME ROLE DESC <<< "$( grep -E "^$1," ${CONF}/build )"
  printf -- "Build: $NAME\nRole: $ROLE\nDescription: $DESC\n"
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
  get_input DESC "Description" --nc --null
  # force uppercase for constants
  NAME=$( printf -- "$NAME" | tr 'a-z' 'A-Z' )
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

function constant_show {
  test $# -eq 1 || err "Provide the constant name"
  C="$( printf -- "$1" |tr 'a-z' 'A-Z' )"
  grep -qE "^$C," ${CONF}/constant || err "Unknown constant"
  IFS="," read -r NAME DESC <<< "$( grep -E "^$C," ${CONF}/constant )"
  printf -- "Name: $NAME\nDescription: $DESC\n"
}

function constant_update {
  start_modify
  generic_choose constant "$1" C && shift
  IFS="," read -r NAME DESC <<< "$( grep -E "^$C," ${CONF}/constant )"
  get_input NAME "Name" --default "$NAME"
  # force uppercase for constants
  NAME=$( printf -- "$NAME" | tr 'a-z' 'A-Z' )
  get_input DESC "Description" --default "$DESC" --null --nc
  sed -i 's/^'$C',.*/'${NAME}','"${DESC}"'/' ${CONF}/constant
  commit_file constant
}

# manipulate applications at a specific environment at a specific location
#
# application [<environment>] [--list] [<location>]
# application [<environment>] [--add|--remove|--assign-resource|--unassign-resource|--list-resource] [<application>] [<location>]
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
  generic_choose resource "$1" RES "^cluster_ip,.*,not assigned," && shift
  # verify the resource is available for this purpose
  grep -E ",${RES//,/}," $CONF/resource |grep -qE '^cluster_ip,.*,not assigned,' || err "Error - invalid or unavailable resource."
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
    sed -i 's/^'"$C"',.*/'"$C"','"$VAL"'/' ${CONF}/value/$ENV/constant
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
  mkdir -p $CONF/template/patch/${NAME} $CONF/value/${NAME} >/dev/null 2>&1
  printf -- "${NAME},${ALIAS},${DESC}\n" >>${CONF}/environment
  touch $CONF/value/${NAME}/constant
  commit_file environment
}

function environment_delete {
  generic_delete environment $1
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

# create a new file definition
#
# storage fields:
#   name	  a unique name to reference this entry; sometimes the actual file name but since
#                   there is only one namespace you may have to be creative.
#   path          the path on the system this file will be deployed to.
#   type          the type of entry, one of 'file', 'symlink', 'binary', 'copy', or 'download'.
#   owner         user name
#   group         group name
#   octal         octal representation of the file permissions
#   target        optional field; for type 'symlink', 'copy', or 'download' - what is the target
#   description   a description for this entry. this is not used anywhere except "$0 file show <entry>"
#
# file types:
#   file          a regular text file
#   symlink       a symbolic link
#   binary        a non-text file
#   copy          a regular file that is not stored here. it will be copied by this application from
#                   another location when it is deployed.  when auditing a remote system files of type
#                   'copy' will only be audited for permissions and existence.
#   download      a regular file that is not stored here. it will be retrieved by the remote system
#                   when it is deployed.  when auditing a remote system files of type 'download' will
#                   only be audited for permissions and existence.
#
function file_create {
  start_modify
  # initialize optional values
  TARGET=""
  # get user input and validate
  get_input NAME "Name (for reference)"
  get_input TYPE "Type" --options file,symlink,binary,copy,download --default file
  if [ "$TYPE" == "symlink" ]; then
    get_input TARGET "Link Target" --nc
  elif [ "$TYPE" == "copy" ]; then
    get_input TARGET "Local or Remote Path" --nc
  elif [ "$TYPE" == "download" ]; then
    get_input TARGET "Remote Path/URL" --nc
  fi
  get_input PTH "Full Path (for deployment)" --nc
  get_input DESC "Description" --nc --null
  get_input OWNER "Permissions - Owner" --default root
  get_input GROUP "Permissions - Group" --default root
  get_input OCTAL "Permissions - Octal (e.g. 0755)" --default 0644 --regex '^[0-7]{3,4}$'
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
    printf -- "\nPlease copy the binary file to: /$CONF/binary/$NAME"
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
    git rm template/${C} >/dev/null 2>&1
    git rm binary/${C} >/dev/null 2>&1
    git add file file-map >/dev/null 2>&1
    git commit -m"template removed by ${USERNAME}" >/dev/null 2>&1 || err "Error committing removal to repository"
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
  else
    printf -- "Name: $NAME\nType: $TYPE\nPath: $PTH\nPermissions: $( octal2text $OCTAL ) $OWNER $GROUP\nDescription: $DESC"
    [ "$TYPE" == "file" ] && printf -- "\nSize: `stat -c%s $CONF/template/$NAME` bytes"
    [ "$TYPE" == "binary" ] && printf -- "\nSize: `stat -c%s $CONF/binary/$NAME` bytes"
  fi
  printf -- '\n'
}

function file_update {
  start_modify
  generic_choose file "$1" C && shift
  IFS="," read -r NAME PTH T OWNER GROUP OCTAL TARGET DESC <<< "$( grep -E "^$C," ${CONF}/file )"
  get_input NAME "Name (for reference)" --default "$NAME"
  get_input TYPE "Type" --options file,symlink,binary,copy,download --default "$T"
  if [ "$TYPE" == "symlink" ]; then
    get_input TARGET "Link Target" --nc --default "$TARGET"
  elif [ "$TYPE" == "copy" ]; then
    get_input TARGET "Local or Remote Path" --nc --default "$TARGET"
  elif [ "$TYPE" == "download" ]; then
    get_input TARGET "Remote Path/URL" --nc --default "$TARGET"
  fi
  get_input PTH "Full Path (for deployment)" --default "$PTH" --nc
  get_input DESC "Description" --default "$DESC" --null --nc
  get_input OWNER "Permissions - Owner" --default "$OWNER"
  get_input GROUP "Permissions - Group" --default "$GROUP"
  get_input OCTAL "Permissions - Octal (e.g. 0755)" --default "$OCTAL" --regex '^[0-7]{3,4}$'
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
      git mv binary/$C binary/$NAME >/dev/null 2>&1
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
  # notify if the file still doesn't exist
  if ! [ -f $CONF/binary/$NAME ]; then
    printf -- "\nPlease copy the binary file to: /$CONF/binary/$NAME"
  fi
  commit_file file file-map
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
    sed -i 's/^'"$C"',.*/'"$C"','"$VAL"'/' $CONF/value/$LOC/$ENV
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
  printf -- "${LOC},${ZONE},${ALIAS},${NET},${MASK},${BITS},${GW},${VLAN},${DESC}\n" >>$CONF/network
  test ! -d ${CONF}/${LOC} && mkdir ${CONF}/${LOC}
  printf -- "${ZONE},${ALIAS},${NET}/${BITS}\n" >>${CONF}/${LOC}/network
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
  fi
  commit_file network ${CONF}/${LOC}/network
}

function network_list {
  NUM=$( wc -l ${CONF}/network |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined network${S}."
  test $NUM -eq 0 && return
  ( printf -- "Site Alias Network\n"; awk 'BEGIN{FS=","}{print $1"-"$2,$3,$4"/"$6}' ${CONF}/network |sort ) |column -t |sed 's/^/   /'
}

function network_show {
  test $# -eq 1 || err "Provide the network name (loc-zone-alias)"
  test `printf -- "$1" |sed 's/[^-]*//g' |wc -c` -eq 2 || err "Invalid format. Please ensure you are entering 'location-zone-alias'."
  grep -qE "^${1//-/,}," ${CONF}/network || err "Unknown network"
  IFS="," read -r LOC ZONE ALIAS NET MASK BITS GW VLAN DESC <<< "$( grep -E "^${1//-/,}," ${CONF}/network )"
  printf -- "Location Code: $LOC\nNetwork Zone: $ZONE\nSite Alias: $ALIAS\nDescription: $DESC\nNetwork: $NET\nSubnet Mask: $MASK\nSubnet Bits: $BITS\nGateway Address: $GW\nVLAN Tag/Number: $VLAN\n"
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
  sed -i 's/^'${C//-/,}',.*/'${LOC}','${ZONE}','${ALIAS}','${NET}','${MASK}','${BITS}','${GW}','${VLAN}','"${DESC}"'/' ${CONF}/network
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

# locate template variables and replace with actual data
#
# the template file WILL be modified!
#
# required:
#  $1 /path/to/template
#  $2 file with space seperated variables and values
#
# syntax:
#  {% resource.name %}
#  {% constant.name %}
#  {% system.name %}, {% system.ip %}, {% system.location %}, {% system.environment %}
#
function parse_template {
  [[ $# -ne 2 || ! -f $1 || ! -f $2 ]] && return
  while [ `grep -cE '{% (resource|constant|system)\.[^ ,]+ %}' $1` -gt 0 ]; do
    NAME=$( grep -Em 1 '{% (resource|constant|system)\.[^ ,]+ %}' $1 |sed -r 's/.*\{% (resource|constant|system)\.([^ ,]+) %\}.*/\1.\2/' )
    grep -qE "^$NAME " $2 || err "Error: Undefined variable $NAME"
    VAL=$( grep -E "^$NAME " $2 |sed "s/^$NAME //" )
    sed -i s$'\001'"{% $NAME %}"$'\001'"$VAL"$'\001' $1
  done
  return 0
}

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
#   be assigned to an application and environment
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
    grep -E "^$TYPE,$VAL," ${CONF}/resource |grep -qE ',(host|application),'
    test $? -eq 0 && printf -- "$NAME $TYPE $VAL\n" || printf -- "$NAME $TYPE $VAL unassigned\n"
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

# system functions
#
# <value> [--audit|--release|--vars]
function system_byname {
  # input validation
  test $# -gt 1 || err "Provide the system name"
  grep -qE "^$1," ${CONF}/system || err "Unknown system"
  # function
  case "$2" in
    --audit) system_audit $1;;
    --release) system_release $1;;
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
  # clean up temporary file
  rm -f $FILE
  pushd $TMP/REFERENCE >/dev/null 2>&1
  # pull down the files to audit
  echo "Retrieving current system configuration..."
  for F in $( find . -type f |sed 's%^\./%%' ); do
    mkdir -p $TMP/ACTUAL/`dirname $F`
    scp $1:/$F $TMP/ACTUAL/$F >/dev/null 2>&1
  done
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
  test $VALID -eq 0 && echo -e "\nSystem audit PASSED" || echo -e "\nSystem audit FAILED"
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

# combine two sets of variables and values, only including the first instance of duplicates
#
# example on including duplicates from first file only:
#   join -a1 -a2 -t',' <(sort -t',' -k1 1) <(sort -t',' -k1 2) |sed -r 's/^([^,]*,[^,]*),.*/\1/'
#
function constant_list_dedupe {
  if ! [ -f $1 ]; then cat $2; return; fi
  if ! [ -f $2 ]; then cat $1; return; fi
  join -a1 -a2 -t',' <(sort -t',' -k1 $1) <(sort -t',' -k1 $2) |sed -r 's/^([^,]*,[^,]*),.*/\1/'
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

function system_release {
  test $# -gt 0 || err
  # load the system
  IFS="," read -r NAME BUILD IP LOC EN <<< "$( grep -E "^$1," ${CONF}/system )"
  # create the temporary directory to store the release files
  mkdir -p $TMP $RELEASEDIR
  RELEASEFILE="$NAME-release-`date +'%Y%m%d-%H%M%S'`.tgz"
  RELEASESCRIPT="$TMP/lpac-install.sh"
  FILES=()
  # create the installation script
  printf -- "!/bin/bash\n# lpac installation script for $NAME, generated on `date`\n#\n\n" >$RELEASESCRIPT
  printf -- "# safety first\ntest \"\`hostname\`\" == \"$NAME\" || exit 2\n\n" >>$RELEASESCRIPT
  printf -- "logger -t lpac \"starting installation for $LOC $EN $NAME, generated on `date`\"\n\n" >>$RELEASESCRIPT
  # look up the applications configured for the build assigned to this system
  if ! [ -z "$BUILD" ]; then
    # retrieve application related data
    for APP in $( build_application_list "$BUILD" ); do
      # get the file list per application
      FILES=( ${FILES[@]} `grep -E ",${APP}\$" ${CONF}/file-map |awk 'BEGIN{FS=","}{print $1}'` )
    done
  fi
  # generate the system variables
  system_vars $NAME >/tmp/app-config.$$
  # generate the release configuration files
  if [ ${#FILES[*]} -gt 0 ]; then
    for ((i=0;i<${#FILES[*]};i++)); do
      # get the file path based on the unique name
      IFS="," read -r FNAME FPTH FTYPE FOWNER FGROUP FOCTAL FTARGET FDESC <<< "$( grep -E "^$${FILES[i]}," ${CONF}/file )"
      # remove leading '/' to make path relative
      FPTH=$( printf -- "$FPTH" |sed 's%^/%%' )
      # skip if path is null (implies an error occurred)
      test -z "$FPTH" && continue
      # ensure the relative path (directory) exists
      mkdir -p $TMP/`dirname $FPTH`
      # how the file is created differs by type
      if [ "$FTYPE" == "file" ]; then
        # copy the base template to the path
        cat $CONF/template/${FILES[i]} >$TMP/$FPTH
        # apply environment patch for this file if one exists
        if [ -f $CONF/template/$EN/${FILES[i]} ]; then
          patch -p0 $TMP/$FPTH <$CONF/template/$EN/${FILES[i]} >/dev/null 2>&1
          test $? -eq 0 || err "Error applying $EN patch to ${FILES[i]}."
        fi
        # process template variables
        parse_template $TMP/$FPTH /tmp/app-config.$$ || err "Error parsing template data"
      elif [ "$FTYPE" == "symlink" ]; then
        # tar will preserve the symlink so go ahead and create it
        ln -s $FTARGET $TMP/$FPTH
      elif [ "$FTYPE" == "binary" ]; then
        # simply copy the file, if it exists
        test -f $CONF/binary/$FNAME || err "Error - binary file '$FNAME' does not exist"
        cat $CONF/binary/$FNAME >$TMP/$FPTH
      elif [ "$FTYPE" == "copy" ]; then
        # copy the file using scp or fail
        scp $FTARGET $TMP/$FPTH >/dev/null 2>&1 || err "Error - an unknown error occurred copying source file '$FTARGET'."
      elif [ "$FTYPE" == "download" ]; then
        # add download to command script
        printf -- "# download '$FNAME'\ncurl -f -k -L --retry 1 --retry-delay 10 -s --url \"$FTARGET\" -o \"/$FPTH\" >/dev/null 2>&1 || logger -t lpac \"error downloading '$FNAME'\"\n" >>$RELEASESCRIPT
      fi
      # stage permissions for processing
      printf -- "# set permissions on '$FNAME'\nchown $FOWNER:$FGROUP /$FPTH\nchmod $FOCTAL /$FPTH\n" >>$RELEASESCRIPT
    done
    # finalize installation script
    printf -- "\nlogger -t lpac \"installation complete\"\n" >>$RELEASESCRIPT
    chmod +x $RELEASESCRIPT
    # generate the release
    pushd $TMP >/dev/null 2>&1
    tar czf $RELEASEDIR/$RELEASEFILE *
    popd >/dev/null 2>&1
    echo -e "Complete. Generated release:\n$RELEASEDIR/$RELEASEFILE"
  else
    err "No managed configuration files."
  fi
}

# generate all system variables and settings
#
function system_vars {
  test $# -eq 1 || err "System name required"
  # load the system
  IFS="," read -r NAME BUILD IP LOC EN <<< "$( grep -E "^$1," ${CONF}/system )"
  # output system data
  echo -e "system.name $NAME\nsystem.build $BUILD\nsystem.ip $IP\nsystem.location $LOC\nsystem.environment $EN"
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
  for C in $( system_constant_list $NAME ); do
    IFS="," read -r CN VAL <<< "$C"
    echo "constant.$( printf -- "$CN" |tr 'A-Z' 'a-z' ) $VAL"
  done
}

function system_create {
  start_modify
  # get user input and validate
  get_input NAME "Hostname"
  get_input BUILD "Build" --null --options "$( build_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  get_input IP "Primary IP"
  get_input LOC "Location" --options "$( location_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  get_input EN "Environment" --options "$( environment_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  # validate unique name
  grep -qE "^$NAME," $CONF/system && err "System already defined."
  # add
  printf -- "${NAME},${BUILD},${IP},${LOC},${EN}\n" >>$CONF/system
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
  awk 'BEGIN{FS=","}{print $1}' ${CONF}/system |sort |sed 's/^/   /'
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
    printf -- "\nManaged configuration files:"
    for ((i=0;i<${#FILES[*]};i++)); do
      grep -E "^${FILES[i]}," $CONF/file |awk 'BEGIN{FS=","}{print $2}' |sed 's/^/   /'
    done |sort |uniq
  else
    printf -- "\nNo managed configuration files."
  fi
  printf -- '\n'
}

function system_update {
  start_modify
  generic_choose system "$1" C && shift
  IFS="," read -r NAME BUILD IP LOC EN <<< "$( grep -E "^$C," ${CONF}/system )"
  get_input NAME "Hostname" --default "$NAME"
  get_input BUILD "Build" --default "$BUILD" --null --options "$( build_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  get_input IP "Primary IP" --default "$IP"
  get_input LOC "Location" --default "$LOC" --options "$( location_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )" 
  get_input EN "Environment" --default "$EN" --options "$( environment_list_unformatted |sed ':a;N;$!ba;s/\n/,/g' )"
  sed -i 's/^'$C',.*/'${NAME}','${BUILD}','${IP}','${LOC}','${EN}'/' ${CONF}/system
  commit_file system
}

function usage {
  echo "Manage application/server configurations and base templates across all environments.

Usage $0 component (sub-component|verb) [--option1] [--option2] [...]
              $0 commit [-m 'commit message']
              $0 cancel [--force]
              $0 diff

Run commit when complete to finalize changes.

Component:
  application
    file [--add|--remove|--list]
  build
  constant
  environment
    application [<environment>] [--list] [<location>]
    application [<environment>] [--add|--remove|--assign-resource|--unassign-resource|--list-resource] [<application>] [<location>]
    application [<environment>] [--name <name>] [--define|--undefine|--list-constant] [<application>]
    constant [--define|--undefine|--list] [<environment>] [<constant>]
  file
    edit [<name>] [--environment <name>]
  location
    [<name>] [--assign|--unassign|--list]
    [<name>] constant [--define|--undefine|--list] [<environment>] [<constant>]
  network
  resource
    <value> [--assign] [<system>]
    <value> [--unassign|--list]
  system
    <value> [--audit|--release|--vars]

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
RELEASEDIR=/bkup1/lpad-releases
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
if [ "$SUBJ" == "cancel" ]; then cancel_modify $@; exit 0; fi
if [ "$SUBJ" == "diff" ]; then diff_master; exit 0; fi

# get verb
VERB="$( echo "$1" |tr 'A-Z' 'a-z' )"; shift

# if no verb is provided default to list, since it is available for all subjects
if [ -z "$VERB" ]; then VERB="list"; fi

# validate subject and verb
printf -- " application build constant environment file location network resource system " |grep -q " $SUBJ "
[[ $? -ne 0 || -z "$SUBJ" ]] && usage
if [[ "$SUBJ" != "resource" && "$SUBJ" != "location" && "$SUBJ" != "system" ]]; then
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
else
  eval ${SUBJ}_${VERB} $@
fi
