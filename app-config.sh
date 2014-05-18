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
}

# error / exit function
#
function err {
  test ! -z "$1" && echo $1 >&2 || echo "An error occurred" >&2
  test x"${BASH_SOURCE[0]}" == x"$0" && exit 1 || return 1
}

# manage changes and locking with branches
#
function start_modify {
  # get the running user
  if ! [ -z "$SUDO_USER" ]; then U=${SUDO_USER}; else
    read -p "You have accessed root with a non-standard environment. What is your username? [root]? " U
    U=$( echo "$U" |tr 'A-Z' 'a-z' ); [ -z "$U" ] && U=root
  fi
  test -z "$U" && err "A user name is required to make modifications."
  # the current branch must either be master or the name of this user to continue
  cd $CONF || err
  git branch |grep -E '^\*' |grep -q master
  if [ $? -eq 0 ]; then
    git branch $U
  else
    git branch |grep -E '^\*' |grep -q $U || err "Another change is in progress, aborting."
  fi
  return 0
}

# merge changes back into master and remove the branch
#
function stop_modify {
  err
}

# input functions
#
# requires:
#  $1 variable name (no spaces)
#  $2 prompt
#  $3 force lowercase (0 eq no, 1 eq yes, default 1)
#
function get_input {
  test $# -lt 2 && return
  RL=""
  if [ "$2" == "0" ]; then LC=0; else LC=1; fi
  while [ -z "$RL" ]; do read -p "$2" RL; if [ $LC -eq 1 ]; then RL=$( printf -- "$RL" |tr 'A-Z' 'a-z' ); fi; done
  eval "$1='$RL'"
}
#
# requires:
#  $1 variable name (no spaces)
#  $2 prompt
#
function get_yn {
  test $# -lt 2 && return
  while [[ "$RL" != "y" && "$RL" != "n" ]]; do get_input RL "$2"; done
  eval "$1='$RL'"
}

function application_create {
  # get user input and validate
  get_input NAME "Name: "
  get_input ALIAS "Alias: "
  get_input BUILD "Build: "
  get_yn CLUSTER "LVS Support (y/n): "
  # validate unique name
  grep -qE '^'$NAME',' $CONF/application && err "Application already defined."
  grep -qE ','$ALIAS',' $CONF/application && err "Alias invalid or already defined."
  # confirm before adding
  printf -- "\nDefining a new application named '$NAME', alias '$ALIAS', installed on the '$BUILD' build"
  [ "$CLUSTER" == "y" ] && printf -- " with " || printf -- " without "
  printf -- "cluster support.\n"
  while [[ "$ACK" != "y" && "$ACK" != "n" ]]; do read -p "Is this correct (y/n): " ACK; ACK=$( printf "$ACK" |tr 'A-Z' 'a-z' ); done
  # add
  [ "$ACK" == "y" ] && printf -- "${NAME},${BUILD},${CLUSTER}\n" >>$CONF/application
  return
}

function application_delete {
  err
}

function application_list {
  NUM=$( wc -l $CONF/application |awk '{print $1}' )
  echo "There are $NUM defined applications."
  test $NUM -eq 0 && return
  cat $CONF/application |awk 'BEGIN{FS=","}{print $1}' |sort
}

function application_update {
  err
}

function constant_create {
  err
}

function constant_delete {
  err
}

function constant_list {
  err
}

function constant_update {
  err
}

function environment_create {
  err
}

function environment_delete {
  err
}

function environment_list {
  err
}

function environment_update {
  err
}

function file_create {
  err
}

function file_delete {
  err
}

function file_edit {
  err
}

function file_list {
  err
}

function file_update {
  err
}

function location_create {
  err
}

function location_delete {
  err
}

function location_list {
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
  err
}

function resource_update {
  err
}

function usage {
  echo "Usage $0 subject verb [--option1] [--option2] [...]

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
  update

Verbs - File:
  edit

" >&2
  exit 1
}


# variables
CONF=/usr/local/etc/lpad/app-config

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
test $# -ge 2 || usage

# get subject and verb
SUBJ="$1"; shift
VERB="$1"; shift

# validate subject and verb
printf -- " application constant environment file location network resource " |grep -q " $SUBJ "
[[ $? -ne 0 || -z "$SUBJ" ]] && usage
printf -- " create delete list update edit " |grep -q " $VERB "
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
