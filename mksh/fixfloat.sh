#!/bin/mksh
# -*- mode: sh -*-
#-
# Copyright © 2019
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
# Shows floating point numbers in “fixed” notation.

function f2f {
	local n=$1 p exp m
	if [[ $n = -* ]]; then
		m=-
		n=${n:1}
	fi

	if [[ $n = +([0-9])?(.*([0-9])) || \
	    $n = *([0-9]).+([0-9]) ]]; then
		print -r -- "out: $1"
		return
	elif [[ $n = .+([0-9])[Ee]?([+-])+([0-9]) ]]; then
		exp=${n##*[Ee]?(+)}
		n=0${n%%[Ee]*}
	elif [[ $n = +([0-9])?(.)[Ee]?([+-])+([0-9]) ]]; then
		exp=${n##*[Ee]?(+)}
		n=${n%%?(.)[Ee]*}.0
	elif [[ $n = +([0-9]).+([0-9])[Ee]?([+-])+([0-9]) ]]; then
		exp=${n##*[Ee]?(+)}
		n=${n%%[Ee]*}
	else
		print -r -- "err: does not pass regexp check"
		return
	fi
	p=${n##*.}
	n=${n%%.*}
	while (( exp > 0 )); do
		[[ -n $p ]] || p=0
		n=$n${p::1}
		p=${p:1}
		let --exp
	done
	while (( exp < 0 )); do
		[[ -n $n ]] || n=0
		p=${n: -1}$p
		n=${n%?}
		let ++exp
	done
	[[ -n $n ]] || n=0
	[[ -n $p ]] || p=0
	n=$n.$p
	n=${n##*(0)}
	[[ $n = .* ]] && n=0$n
	n=${n%%*(0)}
	n=${n%.}
	print -r -- "OUT: $m$n"
}

if (( $# )); then
	for x in "$@"; do
		print -r -- "IN : $x"
		f2f "$x"
	done
elif [[ -t 0 ]]; then
	while IFS= read -r x?'IN : '; do
		f2f "$x"
	done
else
	while IFS= read -r x; do
		print -r -- "IN : $x"
		f2f "$x"
	done
fi
