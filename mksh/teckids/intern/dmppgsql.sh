#!/bin/mksh
# $Id: dmppgsql.sh 4369 2015-05-06 14:51:42Z tglase $
#-
# Copyright © 2015
#	Thorsten Glaser <t.glaser@tarent.de>
#	Dominik George <dominik.george@teckids.org>
# Copyright © 2007
#	Benjamin Kix <b.kix@tarent.de>
#
# Provided that these terms and disclaimer and all copyright notices
# are retained or reproduced in an accompanying document, permission
# is granted to deal in this work without restriction, including un‐
# limited rights to use, publicly perform, distribute, sell, modify,
# merge, give away, or sublicence.
#
# This work is provided “AS IS” and WITHOUT WARRANTY of any kind, to
# the utmost extent permitted by applicable law, neither express nor
# implied; without malicious intent or gross negligence. In no event
# may a licensor, author or contributor be held liable for indirect,
# direct, other damage, loss, or other issues arising in any way out
# of dealing in the work, even if advised of the possibility of such
# damage or existence of a defect, except proven that it results out
# of said person’s immediate fault when using the work as intended.
#-
# Backup all databases in the main (default) PostgreSQL cluster from
# the local system; keep one old backup. If the backup process fails
# both older dumps will not be touched, and this script exits with a
# nōn-zero errorlevel.

export LC_ALL=C
unset LANGUAGE

die() {
	local rv=$1
	shift
	print -ru2 -- "$0: E: $*"
	exit "$rv"
}

[[ -o ?pipefail ]] || die 2 'mksh too old'
set -o pipefail

(( USER_ID )) && die 2 'need superuser privs'

#cd ~postgres || die 2 'HOME directory of management user postgres doesn’t exist'
#cd dumps || die 2 'dumps subdirectory doesn’t exist'
#dst=$(realpath .) || die 2 'huh?'
dst=/var/backups/local/postgres
cd /
umask 077

set -A databases
ndatabases=0
sudo -u postgres psql -At -P recordsep_zero \
    -c "SELECT datname FROM pg_database WHERE datistemplate='f';" |&
while IFS= read -r -d '' -p; do
	databases[ndatabases++]=$REPLY
done

(( ndatabases )) || die 1 'no databases found'

gzdatabases=" Syslog "

rv=0
for database in "${databases[@]}"; do
	print -nr -- "Processing $database... "
	rm -f "$dst/$database.sql*"
	usegz=
	[[ $gzdatabases = *" $database "* ]] && usegz=.gz
	if ! sudo -u postgres pg_dump -Fp "$database" | \
	    if [[ -n $usegz ]]; then
		gzip -n9
	    else
		cat
	    fi \
	    >"$dst/$database.sql$usegz"; then
		rv=1
		print -r -- FAILED
	else
		print -r -- ok
	fi
done
(( rv )) && exit $rv
print Successfully completed.
exit 0
