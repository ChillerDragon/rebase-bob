#!/bin/sh

SLEEP_MINUTES=15

log() {
	printf '[*][%s] %s\n' "$(date '+%F %H:%M')" "$1"
}

while ./rebase-bob.sh
do
	log "sleeping for $SLEEP_MINUTES minutes"
	sleep "$SLEEP_MINUTES"m
done

exit 1
