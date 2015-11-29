# -*- mode: sh -*-
#-
# Copyright © 2013
#	mirabilos <t.glaser@tarent.de>
# Copyright © 2014, 2015
#	Dominik George <dominik.george@teckids.org>
# Copyright © 2014, 2015
#	mirabilos <thorsten.glaser@teckids.org>
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
# Generic LDAP (LDIF) parser into associative arrays.

# include assockit, unless already done
mydir=$(realpath "$(dirname "$0")")
[[ -n $ASSO_VAL ]] || PATH="$mydir:$mydir/..:$PATH" . assockit.ksh

# not NUL-safe
set -A Tb64decode_tbl -- \
    -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 \
    -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 \
    -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 62 -1 -1 -1 63 \
    52 53 54 55 56 57 58 59 60 61 -1 -1 -1 -1 -1 -1 \
    -1  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 \
    15 16 17 18 19 20 21 22 23 24 25 -1 -1 -1 -1 -1 \
    -1 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 \
    41 42 43 44 45 46 47 48 49 50 51 -1 -1 -1 -1 -1 \
    -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 \
    -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 \
    -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 \
    -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 \
    -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 \
    -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 \
    -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 \
    -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1 -1
function Tb64decode {
	[[ -o utf8-mode ]]; local u=$? s
	set +U
	read -raN-1 s <<<"$*"
	local -i i=0 n=${#s[*]} v x
	unset s[--n]
	local -i1 o

	while (( i < n )); do
		(( (x = Tb64decode_tbl[s[i++]]) == -1 )) && continue
		while (( (v = Tb64decode_tbl[s[i++]]) == -1 )); do
			if (( i > n )); then
				(( u )) || set -U
				return 0
			fi
		done
		(( o = ((x = (x << 6) | v) >> 4) & 255 ))
		REPLY+=${o#1#}
		while (( (v = Tb64decode_tbl[s[i++]]) == -1 )); do
			if (( i > n )); then
				(( u )) || set -U
				return 0
			fi
		done
		(( o = ((x = (x << 6) | v) >> 2) & 255 ))
		REPLY+=${o#1#}
		while (( (v = Tb64decode_tbl[s[i++]]) == -1 )); do
			if (( i > n )); then
				(( u )) || set -U
				return 0
			fi
		done
		(( o = ((x << 6) | v) & 255 ))
		REPLY+=${o#1#}
	done
	(( u )) || set -U
}

# Syntax: asso_setldap arrayname index ... -- ldapsearch-options
function asso_setldap_plain {
	local opts x n=0 found=0

	for x in "$@"; do
		opts[n++]=$x
		if [[ $x = -[-+] ]]; then
			opts[n++]=-x
			found=1
		fi
	done
	if (( !found )); then
		opts[n++]=--
		opts[n++]=-x
	fi
	asso_setldap_internal "${opts[@]}"
}
function asso_setldap_sasl {
	local opts x n=0 found=0

	for x in "$@"; do
		opts[n++]=$x
		if [[ $x = -[-+] ]]; then
			opts[n++]=-Q
			found=1
		fi
	done
	if (( !found )); then
		opts[n++]=--
		opts[n++]=-Q
	fi
	asso_setldap_internal "${opts[@]}"
}
function asso_setldap_internal {
	# parse options
	local arrpath ldapopts x i=0 T dn line value found=0
	set -A arrpath
	while (( $# )); do
		[[ $1 = -- || $1 = -+ ]] && break
		arrpath[i++]=$1
		shift
	done
	if [[ $1 != -- && $1 != -+ ]]; then
		print -u2 'assoldap.ksh: syntax: asso_setldap arraypath -- ldappath'
		return 255
	fi
	[[ $1 = -+ ]]; do_free=$?
	shift
	set -A ldapopts -- "$@"

	# Add default host URI if none is given
	for x in "${ldapopts[@]}"; do
		if [[ $x = -H ]]; then
			found=1
			break
		fi
	done
	if (( !found )); then
		set -A ldapopts+ -- -H ldapi://
	fi

	if (( do_free )); then
		# just in case, unset the target array and create it as associative
		asso__lookup 1 "${arrpath[@]}"
		asso__r_free
		asso__r_setf $ASSO_AASS
	fi

	# call ldapsearch with decent output format
	if ! T=$(mktemp /tmp/assoldap.XXXXXXXXXX); then
		print -u2 'assoldap.ksh: could not create temporary file'
		return 255
	fi
	if ! ldapsearch -LLL "${ldapopts[@]}" >"$T"; then
		print -ru2 "assoldap.ksh: error from: ldapsearch -LLL ${ldapopts[*]}"
		rm -f "$T"
		return $i
	fi
	if [[ ! -s $T ]]; then
		# empty output
		rm -f "$T"
		return 0
	fi

	# parse LDIF
	{ IFS= read -r line && while :; do
		if [[ -z $line ]]; then
			dn=
			IFS= read -r line || break
			continue
		fi
		if [[ $line = ' '* ]]; then
			value+=${line# }
		else
			x=${line%%: *}
			value=${line: ${#x}+2}
		fi
		IFS= read -r line || break
		[[ $line = ' '* ]] && continue
		if [[ $x = *: ]]; then
			x=${x%:}
			[[ $x = jpegPhoto ]] || value=${|Tb64decode "$value";}
		fi
		[[ $x = dn ]] && dn=$value

		c=$(asso_getv "${arrpath[@]}" "$dn" "$x" count)
		asso_sets "$value" "${arrpath[@]}" "$dn" "$x" $((c))
		asso_seti $((++c)) "${arrpath[@]}" "$dn" "$x" count
	done; } <"$T"
	rm -f "$T"
	return 0
}

:||\
{
	# for testing
	LDAPTLS_CACERT=/etc/ssl/certs/dc.lan.tarent.de.cer \
	    asso_setldap_plain users -- \
	    -H ldaps://dc.lan.tarent.de -b cn=users,dc=tarent,dc=de -s one \
	    isJabberAccount=1 cn uid
	if (( $? )); then
		print -u2 An error occurred: $?
		exit 1
	fi
	print "uid (dn) = cn"
	asso_loadk users
	for user_dn in "${asso_y[@]}"; do
		print -r -- "$(asso_getv users "$user_dn" uid)" \
		    "($user_dn) = $(asso_getv users "$user_dn" cn)"
	done | sort
}
