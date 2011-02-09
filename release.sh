#! /bin/sh

set -e

version="$1" ; shift
sign="$1"

if [ -z "$version" ] || ! ( [ -z "$sign" ] || [ "$sign" = "-s" ] ) ; then
    cat <<EOF >&2
USAGE: $0 VERSION-NUMBER [SIGN]

This script frobs NEWS, makes a "release" commit, builds, runs tests
and creates an annotated tag for the release with VERSION-NUMBER.

If SIGN is -s, then use the gpg-sign mechanism of "git tag". You will
need to have your gpg secret key handy.

No changes will be pushed upstream. This script will tell you how to
do this when it finishes.
EOF
    exit 1
fi



set -x

sbcl_directory="$(cd "$(dirname $0)"; pwd)"

## Check for messy work dirs:

git fetch

branch_name="release-$(date '+%s')"
original_branch="$(git status -bs | head -1 | awk '{ print $2 }' )"
trap "cd \"$sbcl_directory\" ; git checkout $original_branch" EXIT
# XXX/asf: should branch off master, need this to branch off git-toolchain for now.
git checkout -b $branch_name git-toolchain  # origin/master   

if [ $(git status --porcelain | wc -l) = 0 ]
#    && "$(git log --oneline origin/master.. | wc -l)" = 0
then
    :
else
    echo "There are uncommitted / unpushed changes in this checkout!"
    exit 1
fi

## Perform the necessary changes to the NEWS file:

sed -i.orig "/^changes relative to sbcl-.*:/ s/changes/changes in sbcl-$version/ " NEWS
rm NEWS.orig

cd "$sbcl_directory"

git add NEWS
git commit -m "$version: will be tagged as \"sbcl.$version\""
git tag $sign -m "Released on $(date)" "sbcl.$version"
# For compatibility, tag like this also (feel free to drop that):
git tag $sign -m "Released on $(date)" "sbcl_$(echo $version | sed 's/\./_/g')"

tmpfile=$(mktemp -t sbcl-build-$(date +%Y%m%d)-XXXXXXXXX)

./make.sh >$tmpfile 2>&1

./src/runtime/sbcl --version | grep '^SBCL [1-9][0-9]*\.[0-9]\+\.[1-9][0-9]*$'

built_version=$(./src/runtime/sbcl --version | awk '{print $2}')
grep "^changes in sbcl-$version relative to" NEWS

cd tests
sh ./run-tests.sh >>$tmpfile 2>&1
cd ..

tmpdir="$(mktemp -d -t sbcl-build-tree-$(date +%Y%m%d)-XXXXXXXXX)"

cp ./src/runtime/sbcl "$tmpdir"/sbcl-$version-bin
cp ./output/sbcl.core "$tmpdir"/sbcl-$version.core

./make.sh ""$tmpdir"/sbcl-$version-bin --core "$tmpdir"/sbcl-$version.core --no-userinit --no-siteinit --disable-debugger" >>$tmpfile  2>&1
cd doc && sh ./make-doc.sh

cd ..

rm -f "$tmpdir"/sbcl-$version-bin "$tmpdir"/sbcl-$version.core

cp -a "$sbcl_directory" "$tmpdir"/sbcl-$version

ln -s "$tmpdir"/sbcl-$version "$tmpdir"/sbcl-$version-x86-linux
cd "$tmpdir"/
sh sbcl-$version/binary-distribution.sh sbcl-$version-x86-linux
sh sbcl-$version/html-distribution.sh sbcl-$version
cd sbcl-$version
sh ./distclean.sh
cd ..
sh sbcl-$version/source-distribution.sh sbcl-$version

awk "BEGIN { state = 0 }
 /^changes in sbcl-/ { state = 0 } 
 /^changes in sbcl-$version/ { state = 1 }
 { if(state == 1) print \$0 }" < sbcl-$version/NEWS > sbcl-$version-release-notes.txt

echo "The SHA256 checksums of the following distribution files are:" > sbcl-$version-crhodes
echo >> sbcl-$version-crhodes
sha256sum sbcl-$version*.tar >> sbcl-$version-crhodes
bzip2 "$tmpdir"/sbcl-$version*.tar

echo Bugs fixed by sbcl-$version release > sbcl-$version-bugmail.txt
for bugnum in $(egrep -o "#[1-9][0-9][0-9][0-9][0-9][0-9]+" sbcl-$version-release-notes.txt | sed s/#// | sort -n)
do 
  printf "\n bug %s\n status fixreleased" $bugnum >> sbcl-$version-bugmail.txt
done
echo >> sbcl-$version-bugmail.txt

set +x

echo SBCL distribution has been prepared in "$tmpdir"
echo TODO:
echo
echo "git merge $branch_name && git push && git push --tags"
echo "git branch -d $branch_name"
echo "cd \"$tmpdir\""
echo gpg -sta sbcl-$version-crhodes
echo sftp crhodes,sbcl@frs.sourceforge.net
echo \* cd /home/frs/project/s/sb/sbcl/sbcl
echo \* mkdir $version
echo \* chmod 775 $version
echo \* cd $version
echo \* put sbcl-$version-crhodes.asc
echo \* put sbcl-$version-x86-linux-binary.tar.bz2
echo \* put sbcl-$version-source.tar.bz2
echo \* put sbcl-$version-documentation-html.tar.bz2
echo \* put sbcl-$version-release-notes.txt
echo 
echo perform administrative tasks:
echo 
echo \* https://sourceforge.net/project/admin/?group_id=1373
echo \* In the File Manager interface, click on the release notes file
echo \ \ and tick the release notes box.
echo \* In the File Manager interface, click on the source tarball and
echo \ \ select as default download for all OSes.
echo \* mail sbcl-announce
echo \* check and send sbcl-$version-bugmail.txt to edit@bugs.launchpad.net
echo \ \ '(sign: C-c RET s p)'
echo \* update \#lisp IRC topic
echo \* update sbcl website
