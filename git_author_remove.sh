#!/bin/sh

# A script for removing authors from git history and file contents

REPLACE_DOMAIN=${REPLACE_DOMAIN:-example.com}

restore_ref () {
    if [ -f orig-ref ] ; then
        orig=$(git rev-list --max-count=1 HEAD)
        echo $orig > rewrite-ref
        git reset --hard $(cat orig-ref) 
        rm orig-ref
    else
        echo No refs to restore >&2
    fi
}

rewrite_author () {
    git filter-branch -f --env-filter '

    OLD_EMAIL="'${1}'"
    CORRECT_NAME="'${2}'"
    CORRECT_EMAIL="'${2}'@'${REPLACE_DOMAIN}'"

    if [ "$GIT_COMMITTER_EMAIL" = "$OLD_EMAIL" ]
    then
        export GIT_COMMITTER_NAME="$CORRECT_NAME"
        export GIT_COMMITTER_EMAIL="$CORRECT_EMAIL"
    fi
    if [ "$GIT_AUTHOR_EMAIL" = "$OLD_EMAIL" ]
    then
        export GIT_AUTHOR_NAME="$CORRECT_NAME"
        export GIT_AUTHOR_EMAIL="$CORRECT_EMAIL"
    fi
    ' --tag-name-filter cat -- --branches --tags
}

get_authors () {
    i=0
    git log --format="format:%an:%ae" | sort -u | while read author; do
        printf "%s:%04d\n" "$author" $i
        i=$((i + 1))
    done 
}

sanitize_author_names () {
    author_map=$(readlink -f author-map)
    git filter-branch -f --tree-filter '
    while IFS=":" read old_name old_email new; do
        find . -not -path "./.git*" -type f | xargs sed -i -e "s/$old_name/$new/" -e "s/$old_email/$new/"
    done < '$author_map'
    '
}

rewrite () {
    orig=$(git rev-list --max-count=1 HEAD)
    echo $orig > orig-ref
    get_authors > author-map
    while IFS=':' read old_name old_email new; do
        echo "$old_email $new"
        rewrite_author $old_email $new
    done < author-map
    sanitize_author_names "$old_name" "$old_name" $new
    git diff $orig
}

while getopts 'fr' opt ; do
    case $opt in
        f)
            force=1
            ;;
        r)
            restore=1
            ;;
    esac
done

shift $((OPTIND-1))

if [ $restore ] ; then
    restore_ref
else
    if [ ! $force ] ; then
        if [ -f orig-ref ] ; then
            echo "An original ref already exists. Delete it to continue" >&2
            exit 2
        fi
    fi
    rewrite
fi