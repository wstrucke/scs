#!/bin/sh
#
# Manage application configuration files
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
#     <location>/<environment>/<application>               directory
#     <location>/<environment>/<application>/constant      file
#     
# Locks are taken by using git branches

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
  mkdir -p $CONF
  git init --quiet $CONF
  touch $CONF/{application,constant,environment,file,location,network,resource,template}
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
  return
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
  return
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
#
function get_input {
  test $# -lt 2 && return
  LC=1; RL=""; P="$2"; V="$1"; D=""; NUL=0; shift; shift
  while [ $# -gt 0 ]; do case $1 in
    --default) D="$2"; shift;;
    --nc) LC=0;;
    --null) NUL=1;;
    *) err;;
  esac; shift; done
  while [ -z "$RL" ]; do
    printf -- "$P"
    test ! -z "$D" && printf -- " [$D]: " || printf -- ": "
    read RL; if [ $LC -eq 1 ]; then RL=$( printf -- "$RL" |tr 'A-Z' 'a-z' ); fi
    [[ -z "$RL" && ! -z "$D" ]] && RL="$D"
    [[ -z "$RL" && $NUL -eq 1 ]] && break
  done
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

# refresh the directory structure to add/remove location/environment/application paths
#
function refresh_dirs {
  echo "Refresh not implemented" >&2
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
  refresh_dirs
  return
}

function application_delete {
  start_modify
  application_list
  printf -- "\n"
  get_input APP "Application to Delete"
  grep -qE '^'$APP',' $CONF/application || err "Invalid application"
  get_yn RL "Are you sure (y/n)? "
  if [ "$RL" == "y" ]; then sed -i '/^'$APP',/d' $CONF/application; fi
  refresh_dirs
}

function application_list {
  NUM=$( wc -l $CONF/application |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined application${S}."
  test $NUM -eq 0 && return
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
  application_list
  printf -- "\n"
  get_input APP "Application to Modify"
  grep -qE '^'$APP',' $CONF/application || err "Invalid application"
  printf -- "\n"
  read APP ALIAS BUILD CLUSTER <<< $( grep -E '^'$APP',' ${CONF}/application |tr ',' ' ' )
  get_input NAME "Name" --default $APP
  get_input ALIAS "Alias" --default $ALIAS
  get_input BUILD "Build" --default $BUILD
  get_yn CLUSTER "LVS Support (y/n)"
  sed -i 's/^'$APP',.*/'${NAME}','${ALIAS}','${BUILD}','${CLUSTER}'/' ${CONF}/application
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
  return
}

function constant_delete {
  start_modify
  constant_list
  printf -- "\n"
  get_input C "Constant to Delete"
  C=$( printf -- "$C" |tr 'a-z' 'A-Z' )
  grep -qE '^'$C',' ${CONF}/constant || err "Unknown constant"
  get_yn RL "Are you sure (y/n)? "
  if [ "$RL" == "y" ]; then sed -i '/^'$C',/d' ${CONF}/constant; fi
}

function constant_list {
  NUM=$( wc -l ${CONF}/constant |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined constant${S}."
  test $NUM -eq 0 && return
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
  constant_list
  printf -- "\n"
  get_input C "Constant to Modify"
  C=$( printf -- "$C" |tr 'a-z' 'A-Z' )
  grep -qE '^'$C',' ${CONF}/constant || err "Unknown constant"
  printf -- "\n"
  read NAME DESC <<< $( grep -E '^'$C',' ${CONF}/constant |tr ',' ' ' )
  get_input NAME "Name" --default $NAME
  get_input DESC "Description" --default "$DESC"
  sed -i 's/^'$C',.*/'${NAME}','"${DESC//,/ }"'/' ${CONF}/constant
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
  refresh_dirs
  return
}

function environment_delete {
  start_modify
  environment_list
  printf -- "\n"
  get_input C "Environment to Delete"
  grep -qE '^'$C',' ${CONF}/environment || err "Unknown environment"
  get_yn RL "Are you sure (y/n)? "
  if [ "$RL" == "y" ]; then sed -i '/^'$C',/d' ${CONF}/environment; fi
  refresh_dirs
}

function environment_list {
  NUM=$( wc -l ${CONF}/environment |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined environment${S}."
  test $NUM -eq 0 && return
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
  environment_list
  printf -- "\n"
  get_input C "Environment to Modify"
  grep -qE '^'$C',' ${CONF}/environment || err "Unknown constant"
  printf -- "\n"
  read NAME ALIAS DESC <<< $( grep -E '^'$C',' ${CONF}/environment |tr ',' ' ' )
  get_input NAME "Name" --default $NAME
  get_input ALIAS "Alias (One Letter, Unique)" --default $ALIAS
  get_input DESC "Description" --default "$DESC" --null --nc
  # force uppercase for site alias
  ALIAS=$( printf -- "$ALIAS" | tr 'a-z' 'A-Z' )
  sed -i 's/^'$C',.*/'${NAME}','${ALIAS}','"${DESC//,/ }"'/' ${CONF}/constant
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
  return
}

function file_delete {
  start_modify
  file_list
  printf -- "\n"
  get_input C "File to Delete"
  grep -qE '^'$C',' ${CONF}/file || err "Unknown file"
  printf -- "WARNING: This will remove any templates and stored configurations in all environments for this file!\n"
  get_yn RL "Are you sure (y/n)? "
  if [ "$RL" == "y" ]; then sed -i '/^'$C',/d' ${CONF}/file; fi
  refresh_dirs
}

function file_edit {
  err
}

function file_list {
  NUM=$( wc -l ${CONF}/file |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined file${S}."
  test $NUM -eq 0 && return
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
  file_list
  printf -- "\n"
  get_input C "File to Modify"
  grep -qE '^'$C',' ${CONF}/file || err "Unknown file"
  printf -- "\n"
  read NAME PTH DESC <<< $( grep -E '^'$C',' ${CONF}/file |tr ',' ' ' )
  get_input NAME "Name (for reference)" --default $NAME
  get_input PTH "Full Path (for deployment)" --default "$PTH" --nc
  get_input DESC "Description" --default "$DESC" --null --nc
  if [ "$NAME" != "$C" ]; then
    # validate unique name
    grep -qE '^'$NAME',' ${CONF}/file && err "File already defined."
  fi
  sed -i 's%^'$C',.*%'${NAME}','${PTH//,/_}','"${DESC//,/ }"'%' ${CONF}/file
}

function location_create {
  err
  refresh_dirs
}

function location_delete {
  err
  refresh_dirs
}

function location_list {
  NUM=$( wc -l ${CONF}/location |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined location${S}."
  test $NUM -eq 0 && return
  cat ${CONF}/location |awk 'BEGIN{FS=","}{print $1}' |sort
}

function location_show {
  err
}

function location_update {
  err
}

function network_create {
  err
}

function network_delete {
  err
}

function network_list {
  NUM=$( wc -l ${CONF}/network |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined network${S}."
  test $NUM -eq 0 && return
  cat ${CONF}/network |awk 'BEGIN{FS=","}{print $1}' |sort
}

function network_show {
  err
}

function network_update {
  err
}

function resource_create {
  err
}

function resource_delete {
  err
}

function resource_list {
  NUM=$( wc -l ${CONF}/resource |awk '{print $1}' )
  if [ $NUM -eq 1 ]; then A="is"; S=""; else A="are"; S="s"; fi
  echo "There ${A} ${NUM} defined resource${S}."
  test $NUM -eq 0 && return
  cat ${CONF}/resource |awk 'BEGIN{FS=","}{print $1}' |sort
}

function resource_show {
  err
}

function resource_update {
  err
}

function usage {
  echo "Usage $0 subject verb [--option1] [--option2] [...]
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
test "`whoami`" == "root" || err "What madness is this? Ye art not auth\'riz\'d to doeth that."
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
