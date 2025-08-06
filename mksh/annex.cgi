#!/bin/mksh
# -*- mode: sh -*-
#-
# Copyright © 2012
#	mirabilos <m$(date +%Y)@mirbsd.de>
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

export LC_ALL=C.UTF-8
unset LANGUAGE

[[ $1 = -s ]] || if [[ $REQUEST_METHOD = GET && $HTTPS = on && \
    -n $REMOTE_USER && $REMOTE_USER = "$AUTHENTICATE_UID" ]]; then
	[[ $PATH_INFO = /* ]] && \
	    exec sudo -u "$REMOTE_USER" "$(realpath "$0")" -s "$PATH_INFO" \
	    "$QUERY_STRING"
	print Status: 301 Redirect
	print Location: $SCRIPT_NAME/
	print
	print Please add the trailing slash after the .cgi
	exit 1
else
	print Content-type: text/plain\; charset=UTF-8
	print
	print Error in request arguments.
	exit 1
fi

me=$(realpath "$0")
cd $(dirname "$(dirname "$me")")
basedir=$(realpath .)
shift
pi=$1
QUERY_STRING=$2

function qsdecode {
	local _x=$1

	_x=${_x//\\/\\\\}
	print -- "${_x//[%]/\\x}"
}

function qsparse {
	local _saveIFS _q _s _k _v _a

	# no 'key=value' at all: make q be everything
	if [[ $QUERY_STRING != *=* ]]; then
		qs_q=$(qsdecode "$QUERY_STRING")
		qskeys=(q)
		return
	fi

	_saveIFS=$IFS
	IFS=';&'
	set -A _q -- $QUERY_STRING
	IFS=$_saveIFS

	set -A qskeys
	for _s in "${_q[@]}"; do
		# skip not 'key=value' parts
		[[ $_s = *=* ]] || continue

		_k=$(qsdecode "${_s%%=*}")
		_v=$(qsdecode "${_s#*=}")

		if [[ $_k = *'[]' ]]; then
			_a=1
			_k=${_k%??}
		else
			_a=0
		fi

		# limit keys to alphanumeric and underscore
		# as they must fit as part of an mksh variable
		[[ $_k = +([0-9A-Za-z_]) ]] || continue

		if (( _a )); then
			in_array qskeys $_k || eval set -A qs_$k
			nameref _A=qs_$_k
			_A+=("$_v")
		else
			# eval is evil, but… as long as we don’t have
			# associative arrays in mksh… this works
			eval qs_$_k=\$_v
		fi
		in_array qskeys $_k || qskeys+=("$_k")
	done
}

function in_array {
	nameref _arr=$1
	local _val=$2 _x

	for _x in "${_arr[@]}"; do
		[[ $_x = "$_val" ]] && return 0
	done
	return 1
}

qsparse

pi=${pi##*(/)}
pi=${pi%%*(/)}

function e403 {
	print Status: 403 Forbidden
	print Content-type: text/plain\; charset=UTF-8
	print
	print Du kumms hier nisch rein!
	exit 1
}

if [[ -n $pi ]]; then
	i=$(realpath "$pi")
	[[ -n $i && $i = "$basedir"/* ]] || e403
fi

[[ -e ${pi:-.} && -r ${pi:-.} ]] || e403

[[ -n $pi ]] && if [[ ! -d $pi ]]; then
	if in_array qskeys type; then
		ct=$qs_type
	else
		ct=$(file -biL "$pi")
	fi
	print -r Content-type: "$ct"
	print
	cat "$pi"
	exit 0
fi

[[ -n $pi ]] && cd "$pi"
set -A dirs
set -A files
for i in *; do
	[[ -e $i && -r $i ]] || continue
	if [[ -d $i ]]; then
		dirs+=("$i")
	else
		files+=("$i")
	fi
done

function h {
	typeset x="$*"

	x=${x//'&'/"&amp;"}
	x=${x//'<'/"&lt;"}
	x=${x//'>'/"&gt;"}

	print -r -- "$x"
}

cat <<EOF
Content-type: text/html; charset=UTF-8

<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
 "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en"><head>
 <meta http-equiv="content-type" content="text/html; charset=utf-8" />
 <meta name="tdm-reservation" content="1" />
 <title>$pi/ – Index for nik’s Annex</title>
</head><body>
<h1>Index of $pi/ in nik’s Annex</h1>
EOF

if (( !${#dirs[*]} && !${#files[*]} )); then
	print '<p>No content found.</p>'
else
	print '<table width="100%" border="0">'
	for i in "${dirs[@]}"; do
		print "<tr><td align=\"right\" style=\"width:20;\">[DIR]</td><td><a href=\"$(h "$i")/\">$(h "$i")/</a></td></tr>"
	done
	for i in "${files[@]}"; do
		sz=$(stat -Lc '%s' "$i")
		if (( ${#sz} < 10 )); then
			if (( sz >= 1048576 )); then
				if (( sz > 210000000 )); then
					sz=$(( (sz + 524288) / 1048576)) MiB
				else
					(( sz = (sz * 10 + 524288) / 1048576 ))
					x=${sz%?}
					sz=$x.${sz#$x} MiB
				fi
			elif (( sz >= 1024 )); then
				sz=$(( (sz * 100 + 512) / 1024))
				x=${sz%??}
				sz=$x.${sz#$x} KiB
			fi
		else
			sz=$(bc -q <<<$'scale=2\n'"$sz/1073741824") GiB
		fi
		print "<tr><td align=\"right\" style=\"width:20;\">$sz</td><td><a href=\"$(h "$i")\">$(h "$i")</a> (<a href=\"$(h "$i")?type=application/octet-stream\">download</a>)</td></tr>"
	done
	print '</table>'
fi

print '</body></html>'
exit 0
