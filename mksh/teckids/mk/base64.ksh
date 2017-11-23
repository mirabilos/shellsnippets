# -*- mode: sh -*-

# From MirOS: src/bin/mksh/dot.mkshrc,v 1.68 2011/11/25 23:58:04 tg Exp $
#-
# Copyright (c) 2002, 2003, 2004, 2006, 2007, 2008, 2009, 2010,
#		2011, 2014
#	Thorsten Glaser <tg@mirbsd.org>
#
# Provided that these terms and disclaimer and all copyright notices
# are retained or reproduced in an accompanying document, permission
# is granted to deal in this work without restriction, including un-
# limited rights to use, publicly perform, distribute, sell, modify,
# merge, give away, or sublicence.
#
# This work is provided "AS IS" and WITHOUT WARRANTY of any kind, to
# the utmost extent permitted by applicable law, neither express nor
# implied; without malicious intent or gross negligence. In no event
# may a licensor, author or contributor be held liable for indirect,
# direct, other damage, loss, or other issues arising in any way out
# of dealing in the work, even if advised of the possibility of such
# damage or existence of a defect, except proven that it results out
# of said person's immediate fault when using the work as intended.
#-
# RFC compliant base64 encoder and decoder

if [[ -z $TOP ]]; then
	TOP=$(realpath .)
	while [[ ! -e $TOP/gnu.mk ]]; do
		TOP=$(realpath "$TOP"/..)
	done
	export TOP=$(realpath "$TOP"/www)
fi

if whence -p b64decode >/dev/null 2>&1; then
	function Lb64decode {
		local s="$*"
#		[[ -n $s ]] || { s=$(cat;print x); s=${s%x}; }

		print -nr -- "$s" | b64decode -r
	}
elif whence -p base64 >/dev/null 2>&1; then
	function Lb64decode {
		local s="$*"
		print -nr -- "$s" | base64 -d -i
	}
else
	# technically, we could use the pure-shell code,
	# but that would make some LDAP things very slow
	print -u2 'E: Need b64decode (MirBSD) or base64 (GNU coreutils)!'
	exit 1
fi

set -A Lb64encode_code -- A B C D E F G H I J K L M N O P Q R S T U V W X Y Z \
    a b c d e f g h i j k l m n o p q r s t u v w x y z 0 1 2 3 4 5 6 7 8 9 + /
# NUL safe base64 encoder, needs mksh R40
function Lb64encode {
	[[ -o utf8-mode ]]; local u=$?
	set +U
	local c s t
	if (( $# )); then
		read -raN-1 s <<<"$*"
		unset s[${#s[*]}-1]
	else
		read -raN-1 s
	fi
	local -i i=0 n=${#s[*]} j v

	while (( i < n )); do
		(( v = s[i++] << 16 ))
		(( j = i < n ? s[i++] : 0 ))
		(( v |= j << 8 ))
		(( j = i < n ? s[i++] : 0 ))
		(( v |= j ))
		t+=${Lb64encode_code[v >> 18]}${Lb64encode_code[v >> 12 & 63]}
		c=${Lb64encode_code[v >> 6 & 63]}
		if (( i <= n )); then
			t+=$c${Lb64encode_code[v & 63]}
		elif (( i == n + 1 )); then
			t+=$c=
		else
			t+===
		fi
		if (( ${#t} == 76 || i >= n )); then
			print $t
			t=
		fi
	done
	(( u )) || set -U
}
