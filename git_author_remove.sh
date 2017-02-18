#!/bin/sh

# A script for removing authors from git history and file contents

REPLACE_DOMAIN=${REPLACE_DOMAIN:-example.com}
interactive=

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
        find . -print0 -not -path "./.git*" -type f | egrep --null -v -e "'$FILE_EXCLUDES'" \
            | xargs --null sed -i -e "s/$old_name/$new/" -e "s/$old_email/$new/"
    done < '$author_map'
    '
}

ensure_author_map () {
    if [ author-map ] ; then
        echo 'There is already an author=>id map in author-map.'
        if [ $interactive ] ; then
            echo -n 'Use(0), replace(1), or exit(2)? '
            read AUTHOR_MAP_HANDLING
        fi
        case $AUTHOR_MAP_HANDLING in
            1|replace)
                echo 'Replacing author-map'
                get_authors > author-map
                ;;
            2|exit)
                exit 3
                ;;
            *)
                echo 'Using existing author-map'
                ;;
        esac
    else
        get_authors > author-map
    fi
}

rewrite () {
    orig=$(git rev-list --max-count=1 HEAD)
    echo $orig > orig-ref
    while IFS=':' read old_name old_email new; do
        echo "$old_email $new"
        rewrite_author $old_email $new
    done < author-map
    sanitize_author_names "$old_name" "$old_name" $new
    git diff $orig
}

while getopts 'friga:x:' opt ; do
    case $opt in
        f)
            force=1
            ;;
        r)
            restore=1
            ;;
        i)
            interactive=1
            ;;
        g)
            just_gen_map=1
            ;;
        a)
            AUTHOR_MAP_HANDLING=$OPTARG
            ;;
        x)
            FILE_EXCLUDES=$OPTARG
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
    ensure_author_map
    if [ $just_gen_map ] ; then
        exit 0
    fi
    rewrite
fi