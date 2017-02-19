#!/bin/sh

# A script for removing authors from git history and file contents

REPLACE_DOMAIN=${REPLACE_DOMAIN:-example.com}
TEMPDIR=
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
    if [ $TEMPDIR ] ; then
        temppart="-d $TEMPDIR"
    fi
    export OLD_EMAIL="${1}"
    export OLD_NAME="${2}"
    export CORRECT_NAME="${3}"
    export CORRECT_EMAIL="${3}@${REPLACE_DOMAIN}"
    git filter-branch $temppart -f --env-filter '
    if [ "$GIT_COMMITTER_EMAIL" = "$OLD_EMAIL" -a "$GIT_COMMITTER_NAME" = "$OLD_NAME" ] ; then
        export GIT_COMMITTER_NAME="$CORRECT_NAME"
        export GIT_COMMITTER_EMAIL="$CORRECT_EMAIL"
    fi
    if [ "$GIT_AUTHOR_EMAIL" = "$OLD_EMAIL" -a "$GIT_AUTHOR_NAME" = "$OLD_NAME" ] ; then
        export GIT_AUTHOR_NAME="$CORRECT_NAME"
        export GIT_AUTHOR_EMAIL="$CORRECT_EMAIL"
    fi
    ' --tag-name-filter 'sed -r "s/^(export-)?/export-/"' -- --branches --tags
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
    if [ $TEMPDIR ] ; then
        temppart="-d $TEMPDIR"
    fi
    if [ $FILE_EXCLUDES ] ; then
        excludespart='-and -not -path "'$FILE_EXCLUDES'"'
    fi
    git filter-branch $temppart -f --tree-filter '
    while IFS=":" read old_name old_email new; do
        find . -not -path "./.git*" '"$excludespart"' -type f -print0 \
            | xargs --null sed -i -e "s/\b$old_name\b/$new/" -e "s/\b$old_email\b/$new/"
    done < '$author_map'
    '
}

ensure_author_map () {
    if [ -f author-map ] ; then
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
    #while IFS=':' read old_name old_email new; do
        #echo "$old_email $new"
        #rewrite_author $old_email "$old_name" $new
    #done < author-map
    sanitize_author_names "$old_name" "$old_name" $new
    git diff $orig
}

while getopts 'friga:x:d:' opt ; do
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
        d)
            TEMPDIR=$OPTARG
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
    ensure_author_map
    if [ $just_gen_map ] ; then
        exit 0
    fi
    if [ ! $force ] ; then
        if [ -f orig-ref ] ; then
            echo "An original ref already exists. Delete it to continue" >&2
            exit 2
        fi
    fi
    rewrite
fi
