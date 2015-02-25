gitDir=../mainNVDACode

_cp() {
    if [ -e "$1" ]; then
        mkdir -p $(dirname "${gitDir}/${2}")
        cp "$1" "${gitDir}/${2}"
        git -C $gitDir add "$2"
    fi
}

checkT2t() {
    encoding=`file $1 | grep -vP ': +(ASCII text|UTF-8|empty)'`
    if [ "$encoding" != "" ]; then
        echo Encoding problem: $encoding
        return 1
    fi
    if ! output=$(txt2tags -q -o /dev/null $1 2>&1); then
        echo Error in $1:
        echo "$output"
        return 1
    fi
}

checkUserGuide() {
    checkT2t $1/userGuide.t2t || exit 1
    pushd $1 > /dev/null
    if ! output=$(python ../scripts/keyCommandsDoc.py 2>&1); then
        echo Key commands error in $1/userGuide.t2t: $output
        popd > /dev/null
        return 1
    fi
    popd > /dev/null
}

svn2nvda () {
    logMsg "Running svn2nvda"
    git -C "$gitDir" stash
    git -C "$gitDir" checkout master
    git -C "$gitDir" fetch origin
    brname=l10n
    git -C "$gitDir" branch -D "$brname" || true
    git -C "$gitDir" branch "$brname" origin/master
    git -C "$gitDir" checkout "$brname"
    svnRev=$(svn info | grep -i "Revision" | awk '{print $2}')

    ls -1 */settings | while read file; do
        lang=$(dirname $file)
        logMsg "Processing $lang" 
        lastSubmittedSvnRev=$(python scripts/db.py -f $file -g nvda.lastSubmittedSvnRev)
        if test "0" = "${lastSubmittedSvnRev}"; then
            lastSubmittedSvnRev=1
        fi
        needsCommitting=$(svn log -r${lastSubmittedSvnRev}:head ${lang}/nvda.po | grep -iP "r[0-9]+ \|" | grep -viP "commitbot" | wc -l)
        if test "$needsCommitting" != "0" && python -m poChecker $lang/nvda.po ; then
            _cp $lang/nvda.po source/locale/$lang/LC_MESSAGES/nvda.po
        fi
        _cp $lang/symbols.dic source/locale/$lang/symbols.dic
        _cp $lang/characterDescriptions.dic source/locale/$lang/characterDescriptions.dic
        _cp $lang/gestures.ini source/locale/$lang/gestures.ini

        checkT2t $lang/changes.t2t && _cp $lang/changes.t2t  user_docs/$lang/changes.t2t
        checkUserGuide $lang && _cp $lang/userGuide.t2t  user_docs/$lang/userGuide.t2t
        commit=$(git -C "$gitDir" diff --cached | wc -l)
        if [ "$commit" -gt "0" ]; then
            authors=$(python scripts/addresses.py $lang)
            stats=$(git -C "$gitDir" diff --cached --numstat --shortstat)
            echo "L10n updates for: $lang\nFrom translation svn revision: $svnRev\n\nAuthors:\n$authors\n\nStats:\n$stats" | 
            git -C "$gitDir" commit -F -
            python scripts/db.py -f $file -s nvda.lastSubmittedSvnRev "$svnRev"
        fi
    done
    git -C "$gitDir" checkout master
    git -C "$gitDir" stash pop || true
    echo "All languages processed, use stg to edit authors/provide additional information., also don't forget to push to try repo to make sure a snapshot can be built."
    echo "When all done don't forget to commit the updated metadata in srt/*/settings"
}
