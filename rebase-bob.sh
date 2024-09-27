#!/bin/sh

set -u

# hello I am bob the rebase bot!
# use me to let others rebase your pending github prs by commenting "rebase please"

# shellcheck disable=SC1091
[ -f .env ] && . ./.env

SCRIPT_ROOT="$PWD"

ARG_VERBOSE="${ARG_VERBOSE:-0}"
GH_BOT_USERNAME="${GH_BOT_USERNAME:-ChillerDragon}"
GIT_ROOT="${GIT_ROOT:-/tmp/bob}"

KNOWN_URLS_FILE="$SCRIPT_ROOT/urls.txt"
touch "$KNOWN_URLS_FILE"

# https://github.com/teeworlds-community/mirror-bot/issues/5
# https://github.com/cli/cli/blob/f4dff56057efabcfa38c25b3d5220065719d2b15/pkg/cmd/root/help_topic.go#L92-L96
# use local github cli config
# so this script never opens pullrequests under the wrong github user
# if the linux user wide configuration changes
export GH_CONFIG_DIR="$PWD/gh"

# log error
err() {
	printf '[-][%s] %s\n' "$(date '+%F %H:%M')" "$1" > /dev/stderr
}
# log warning
wrn() {
	printf '[!][%s] %s\n' "$(date '+%F %H:%M')" "$1" > /dev/stderr
}
# log info
log() {
	printf '[*][%s] %s\n' "$(date '+%F %H:%M')" "$1"
}
# log debug
dbg() {
	[ "$ARG_VERBOSE" = "0" ] && return

	printf '[DEBUG][%s] %s\n' "$(date '+%F %H:%M')" "$1"
}

# everything not in here should be passed to check_dep
# https://pubs.opengroup.org/onlinepubs/9699919799/utilities/contents.html
# https://pubs.opengroup.org/onlinepubs/009695399/idx/utilities.html
check_dep() {
	[ -x "$(command -v "$1")" ] && return
	err "Error: missing dependency $1"
	exit 1
}

check_dep gh
check_dep jq
check_dep git

if ! gh --version | grep -qF 'https://github.com/cli/cli/releases'
then
	err "Error: found gh in your PATH but it does not seem to be the github cli"
	exit 1
fi

if ! gh auth switch --user "$GH_BOT_USERNAME"
then
	err "Error: failed to switch to github account '$GH_BOT_USERNAME'"
	exit 1
fi

# https://stackoverflow.com/questions/38015239/url-encoding-a-string-in-shell-script-in-a-portable-way/38021063#38021063
urlencodepipe() {
    LANG=C;
    while IFS= read -r c;
    do
        case $c in [a-zA-Z0-9.~_-]) printf "%s" "$c"; continue ;; esac
        printf "%s" "$c" | od -An -tx1 | tr ' ' % | tr -d '\n'
    done <<EOF
$(fold -w1)
EOF
    echo
}
urlencode() {
	printf '%s\n' "$*" | urlencodepipe
}


is_dirty_git() {
    if [ "$(git status | tail -n1)" != "nothing to commit, working tree clean" ]
    then
        return 0
    fi
    return 1
}

rebase_error_msg() {
	cat <<-'EOF'
	Hello I am [bob](https://github.com/ChillerDragon/rebase-bob). And there was an error rebasing sorry UwU.
	
	If there is a bug with the bot you can comment ``!shutdown bob`` and it will stop running.
	EOF
}

# rebase_pull_url [repo_pull_url]
# example:
#   rebase_pull_url https://api.github.com/repos/ChillerDragon/github-meta/pulls/7
rebase_pull_url() {
	pull_url="$1"
	details=''
	if ! details="$(gh api "$pull_url" | jq -r '"\(.base.repo.full_name) \(.head.ref)"')"
	then
		wrn "Warning: failed to get $pull_url"
		return
	fi

	# TODO: check if this is a whitelisted repo
	repo="$(printf '%s' "$details" | cut -d' ' -f1)"

	# TODO: check if the git remote -v matches the repo

	if ! cd "$GIT_ROOT"
	then
		err "Error: failed to go to GIT_ROOT $GIT_ROOT"
		exit 1
	fi

	if ! cd "$GIT_ROOT/$repo"
	then
		err "Error: failed to go to repo $GIT_ROOT/$repo"
		exit 1
	fi

	if is_dirty_git
	then
		wrn "Warning: git repo dirty can not rebase"
		wrn ""
		wrn "  cd $PWD && git status"
		wrn ""
		return
	fi

	branch="$(printf '%s' "$details" | cut -d' ' -f2)"
	if ! git fetch upstream
	then
		wrn "Warning: failed to fetch upstream in $PWD"
		return
	fi

	if ! git fetch origin
	then
		wrn "Warning: failed to fetch origin in $PWD"
		return
	fi

	if [ "$branch" = "" ]
	then
		wrn "Warning: branch empty"
		return
	fi

	if ! git checkout "$branch"
	then
		wrn "Warning: failed to checkout branch $branch"
		return
	fi

	if ! git pull
	then
		wrn "Warning: failed to pull"
		return
	fi

	if ! git rebase upstream/master
	then
		wrn "Warning: failed to rebase master branch"

		# TODO: check if there is a "main" instead of "master" branch

		if ! pull_id="$(printf '%s' "$pull_url" | grep -Eo '/[0-9]+$' | cut -d'/' -f2)"
		then
			wrn "Warning: failed to get pull id"
			return
		fi

		if ! git rebase --abort
		then
			err "Error: failed to abort failed rebase"
			return
		fi

		if ! gh issue comment "$pull_id" --body "$(rebase_error_msg)"
		then
			err "Error: failed to comment"
			exit 1
		fi

		return
	fi

	log "pushing rebased branch $branch in repo $repo ..."

	if ! git push -f
	then
		wrn "Warning: failed to push"
	fi
}

# handle_notification [repo_url] [comment_url]
# example:
#   handle_notification author https://api.github.com/repos/ChillerDragon/github-meta/pulls/7 https://api.github.com/repos/ChillerDragon/github-meta/issues/comments/2379033937
handle_notification() {
	repo_url="$1"
	comment_url="$2"

	if [ "$comment_url" = null ]
	then
		# this can happend when we get a notification for something other than a comment
		# such as the pr being closed/merged or reviewed
		return
	fi

	if [ "$comment_url" = "" ]
	then
		wrn "Warning: comment url empty"
		return
	fi

	if grep -q "$comment_url" "$KNOWN_URLS_FILE"
	then
		dbg "skipping known comment $comment_url"
		return
	fi
	printf '%s\n' "$comment_url" >> "$KNOWN_URLS_FILE"


	if ! comment_json="$(gh api "$comment_url")"
	then
		wrn "Warning: failed to fetch comment json"
		return
	fi

	if ! comment="$(printf '%s' "$comment_json" | jq -r .body)"
	then
		wrn "Warning: failed to fetch comment content"
		return
	fi
	if [ "$comment" = "" ]
	then
		wrn "Warning: empty comment"
		return
	fi


	if ! author="$(printf '%s' "$comment_json" | jq -r '.user.login')"
	then
		wrn "Warning: failed to fetch comment author"
		return
	fi
	if [ "$author" = "$GH_BOT_USERNAME" ]
	then
		dbg "ignoring own comment: $comment"
		return
	fi

	if printf '%s' "$comment" | grep -qiE '(rebase|rebabe|rebob)'
	then
		log "got comment requesting rebase. comment: $comment"
		rebase_pull_url "$repo_url"
	elif [ "$comment" = '!shutdown bob' ]
	then
		log "got shutdown request from $author. comment: $comment"
		exit 0
	else
		log "got comment requesting no rebase. comment: $comment"
	fi
}

fetch_repo() {
	repo="$1"
	gh api "repos/$repo/notifications" \
		| jq -r '.[] | "\(.reason) \(.subject.url) \(.subject.latest_comment_url)"' \
		| grep '^author' | cut -d' ' -f2- | while IFS= read -r notification
		do
			log "not $notification"

			# explode args
			# shellcheck disable=SC2086
			handle_notification $notification
		done
}

fetch_repos() {
	printf '%s\n' "$ALLOWED_REMOTES" | tr ' ' '\n' | while IFS= read -r remote
	do
		log "fetching repo $remote ..."
		fetch_repo "$remote"
	done
}

fetch_repos

