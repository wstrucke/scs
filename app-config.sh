#!/bin/sh
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

function usage {
  echo "Usage $0 environment application template-file" >&2
  exit 1
}


# set local variables
APP=""
ENV=""
FILE=""
PATCHDIR=/usr/local/etc/lpad/app-patches
TEMPLATEDIR=/usr/local/etc/lpad/app-templates
TMP=/tmp/generate-patch.$$


trap cleanup_and_exit EXIT INT

# parse arguments
while [ $# -ge 1 ]; do case $( echo $1 |tr 'A-Z' 'a-z' ) in
  alpha|beta|dev|prod|sandbox|test) ENV=$( echo $1 |tr 'A-Z' 'a-z' );;
  affiliates|ctm|deskpro|e4x|ea|etl|expression-engine|finance|jasper|pentaho|prod-admin|purchase|purchase-api|rubix|v2|va) APP=$( echo $1 |tr 'A-Z' 'a-z' );;
  *) if [[ -z "$APP" || -z "$ENV" ]]; then usage; else FILE="$1"; fi;;
esac; shift; done

# input validation
if [[ -z "$APP" || -z "$ENV" || -z "$FILE" ]]; then usage; fi

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
