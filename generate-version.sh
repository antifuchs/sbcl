#!/bin/false
# Not a shell script, but something intended to be sourced from shell scripts
git_available_p() {
    which git >/dev/null 2>/dev/null
}

generate_version() {
    if [ -f version.lisp-expr ] && ! git_available_p ; then
        # This is a release tarball. Leave version.lisp-expr alone.
        return
    else
        # Use non-annotated tags (a boinkor git specialty), and append
        # -dirty to a dirty tree.
        # For additional old-style version number compatibility,
        # translate the first - to a period.
        version="$(git describe --tags --abbrev=4 --match='sbcl.*' | \
                   sed -e 's/^sbcl\.//' -e 's/-/./')"
        if ! [ -z "NO_GIT_HASH_IN_VERSION" ] ; then
            version="$(echo "$version" | sed -e 's/-g[0-9a-f]*$//')"
        fi
        cat >version.lisp-expr <<EOF
;;; This is an auto-generated file, using git describe.
;;; Every time you re-run make.sh, this file will be overwritten.
"$version"
EOF
    fi
}