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

# include assockit and pure-mksh base64 decoder, unless already done
mydir=$(realpath "$(dirname "$0")")
[[ -n $ASSO_VAL ]] || PATH="$mydir:$mydir/..:$PATH" . assockit.ksh
typeset -f Lb64decode >/dev/null || PATH="$mydir:$mydir/..:$PATH" . base64

# Syntax: asso_setldap arrayname index ... -- ldapsearch-options
function asso_setldap {
	# parse options
	local arrpath ldapopts x i=0 T dn line value
	set -A arrpath
	while (( $# )); do
		[[ $1 = -- ]] && break
		arrpath[i++]=$1
		shift
	done
	if [[ $1 != -- ]]; then
		print -u2 'assoldap.ksh: syntax: asso_setldap arraypath -- ldappath'
		return 255
	fi
	shift
	set -A ldapopts -- "$@"

	# just in case, unset the target array and create it as associative
	asso__lookup 1 "${arrpath[@]}"
	asso__r_free
	asso__r_setf $ASSO_AASS

	# call ldapsearch with decent output format
	if ! T=$(mktemp -d /tmp/assoldap.XXXXXXXXXX); then
		print -u2 'assoldap.ksh: could not create temporary directory'
		return 255
	fi
	(ldapsearch -xLLL "${ldapopts[@]}"; echo $? >"$T/err") | \
	    tr '\n' $'\a' | sed -e $'s/\a //g' >"$T/out"
	i=$(<"$T/err")
	if (( i )); then
		print -u2 'assoldap.ksh: ldapsearch returned error'
		rm -rf "$T"
		return $i
	fi
	if [[ ! -s $T/out ]]; then
		# empty output
		rm -rf "$T"
		return 0
	fi

	# parse LDIF (without linewraps)
	while IFS= read -d $'\a' -r line; do
		if [[ -z $line ]]; then
			dn=
			continue
		fi
		value=${line##+([!:]):?(:)*( )}
		if [[ $value = "$line" ]]; then
			print -ru2 "assoldap.ksh: malformed line: $line"
			rm -rf "$T"
			return 255
		fi
		x=${line%%*( )"$value"}
		if [[ $x = "$line" ]]; then
			print -ru2 "assoldap.ksh: malformed line: $line"
			rm -rf "$T"
			return 255
		fi
		[[ $x = *:: ]] && value=$(Lb64decode "$value")
		x=${x%%+(:)}
		if [[ -z $dn ]]; then
			if [[ $x = dn ]]; then
				dn=$value
			else
				print -ru2 "assoldap.ksh: not dn: $line"
				rm -rf "$T"
				return 255
			fi
		elif [[ $x = dn ]]; then
			print -ru2 "assoldap.ksh: unexpected dn ($dn): $line"
			rm -rf "$T"
			return 255
		fi
		asso_sets "$value" "${arrpath[@]}" "$dn" "$x"
	done <"$T/out"
	rm -rf "$T"
	if [[ -n $dn ]]; then
		print -u2 'assoldap.ksh: missing empty line at EOT'
		return 255
	fi
	return 0
}

:||\
{
	# for testing
	LDAPTLS_CACERT=/etc/ssl/certs/dc.lan.tarent.de.cer \
	    asso_setldap users -- \
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
