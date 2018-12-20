#!/usr/bin/env mksh
# -*- mode: sh -*-
#-
# Copyright © 2018
#	mirabilos <t.glaser@tarent.de>
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
# Create mvnrepository.com URLs for all dependencies, extensions and
# Maven plugins, sorted and categorised, for up-to-date checks.

LC_ALL=C; export LC_ALL
unset LANGUAGE

set -e
set -o pipefail
me=$(realpath "$0/..")
. "$me/assockit.ksh"
. "$me/progress-bar"

die() {
	print -ru2 -- "E: $*"
	exit 1
}

set -A grouping 'Parent' 'Project' 'Dependencies' 'Extensions' 'Plugins' 'Plugin Deps'

function xml2path {
	# thankfully only HT, CR, LF are, out of all C0 controls, valid in XML
	xmlstarlet tr "$me/mvnrepo.xsl" "$1" | { tr '\n' ''; print; } | \
	    sed -e 's!$!!' -e "s!'//!'//!g" -e "s!'\\\\''!'\\\\''!g" | \
	    tr '' '\n' | \
	    grep -E "^[^']*/(groupId|artifactId|version)='" >target/pom.xp
}

function extract {
	local line value base path p t x bron=$1 lines=$2

	# thankfully neither ' nor = are valid in XML names
	set +e
	while IFS= read -r line; do
		draw_progress_bar
		if [[ $line = *''* ]]; then
			print -ru2 -- "W: Embedded newline in ${line@Q}"
			continue
		fi
		value=${line#*=}
		eval "value=$value" # trust our XSLT escaping code
		(( $? )) && die "Error reading value from line ${line@Q}"
		line=${line%%=*}
		base=${line##*/}
		line=${line%/*}
		asso_sets "$value" "$bron" "$line" "$base"
	done <target/pom.xp
	asso_loadk "$bron"
	for path in "${asso_y[@]}"; do
		draw_progress_bar
		p=${path//'['+([0-9])']'}
		if [[ $p = //project/parent ]]; then
			t=0
		elif [[ $p = //project ]]; then
			t=1
		elif [[ $p = */extension ]]; then
			t=3
		elif [[ $p = */plugin/dependencies/dependency ]]; then
			t=5
		elif [[ $p = */plugin ]]; then
			t=4
		elif [[ $p = */dependencies/dependency ]]; then
			t=2
		elif [[ $p = */@(configuration|exclusions)/* ]]; then
			# skip well-known others silently
			continue
		else
			print -ru2 -- "W: Unknown XPath: $path"
			continue
		fi
		x=$(asso_getv "$bron" "$path" groupId)
		[[ -n $x ]] || case $t {
		(1)	x=$(asso_getv "$bron" //project/parent groupId)
			[[ -n $x ]] || die "No groupId for project or parent"
			;;
		(4)	x=org.apache.maven.plugins
			#print -ru2 -- "W: missing groupId for $path"
			;;
		(*)	die "missing groupId for $path"
			;;
		}
		[[ $x = */* ]] && die "wtf, groupId ${x@Q} for $path contains a slash"
		t+=/$x
		x=$(asso_getv "$bron" "$path" artifactId)
		if [[ -n $x ]]; then
			t+=/$x
			[[ $x = */* ]] && die "wtf, artifactId ${x@Q} for $path contains a slash"
			x=$(asso_getv "$bron" "$path" version)
			[[ $x = *'${'* || $x = *[\\/:\"\<\>\|?*]* ]] && x=
		fi
		[[ -n $x ]] && asso_sets "$x" versions "$t"
		asso_setnull $lines "$t"
	done
	set -e
}

function output {
	local lineno=-1 nlines line vsn lines=$1
	local last=-1 typ

	set +e
	asso_loadk $lines
	nlines=${#asso_y[*]}
	(( nlines )) || print -r -- "(none)"
	while (( ++lineno < nlines )); do
		draw_progress_bar
		line=${asso_y[lineno]}
		vsn=$(asso_getv versions "$line")
		[[ -n $vsn ]] && line+=/$vsn
		typ=${line::1}
		line=${line:2}
		if (( typ < 2 )); then
			print -nr -- "${grouping[typ]}: "
		elif (( typ != last )); then
			print
			print -r -- "${grouping[typ]}:"
		fi
		(( last = typ ))
		print -r -- "https://mvnrepository.com/artifact/$line"
	done
	set -e
}

function drop {
	local lineno=-1 nlines line vsn lines=$1 from=$2

	set +e
	asso_loadk $lines
	nlines=${#asso_y[*]}
	while (( ++lineno < nlines )); do
		draw_progress_bar
		asso_unset $from "${asso_y[lineno]}"
	done
	set -e
}

mkdir -p target
rm -f target/effective-pom.xml
mvn -B -N help:effective-pom -Doutput=target/effective-pom.xml >&2 &
xml2path pom.xml

Lxp=$(wc -l <target/pom.xp)
# first estimate
Lxe=$((Lxp * 3 / 2))
Lop=$((Lxp / 3))
Loe=300 # outrageous, I know, but it makes things smoother
set +e
init_progress_bar $((2*Lxp + 2 + 2*Lxe + 1 + Lop + 1 + Lop + Loe))
set -e

LN=$_cur_progress_bar
extract p plines
Lxpr=$((_cur_progress_bar - LN))

while [[ -n $(jobs) ]]; do wait; done
set +e
draw_progress_bar
set -e

xml2path target/effective-pom.xml

Lxe=$(wc -l <target/pom.xp)
# re-estimate
Loe=$(( (Lxe-Lxp) / 3 ))
set +e
asso_loadk plines
Lop=${#asso_y[*]}
_cnt_progress_bar=$((Lxpr + 2 + 2*Lxe + 1 + Lop + 1 + Lop + Loe))
draw_progress_bar
set -e

LN=$_cur_progress_bar
extract e elines
Lxer=$((_cur_progress_bar - LN))
rm -f target/effective-pom.xml target/pom.xp

# recalculate
set +e
asso_loadk elines
Loe=${#asso_y[*]}
_cnt_progress_bar=$((Lxpr + 2 + Lxer + 1 + Lop + 1 + Lop + Loe))
draw_progress_bar
set -e

drop plines elines

set +e
asso_loadk elines
Loe=${#asso_y[*]}
_cnt_progress_bar=$((Lxpr + 2 + Lxer + 1 + Lop + 1 + Lop + Loe))
draw_progress_bar
set -e

output plines
print
print Effective POM extras:
output elines
set +e
done_progress_bar
