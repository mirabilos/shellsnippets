#!/bin/mksh
rcsid='$MirOS: contrib/hosted/tg/deb/quinn-ls.sh,v 1.1 2011/02/18 18:52:01 tg Exp $'
#-
# Copyright (c) 2011
#	Thorsten Glaser <tg@debian.org>
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

find . -name \*.changes -o -name \*.dsc |&
set -A pkgs
set -A lver
set -A uver
i=0
while IFS= read -pr name; do
	Source=
	Version=
	eval $(sed -n \
	    -e '/^\(Source\): \([^ ]*\)\( .*\)*$/s//\1='\''\2'\''/p' \
	    -e '/^\(Version\): \([^ ]*\)$/s//\1='\''\2'\''/p' \
	    "$name")
	if [[ -z $Source || -z $Version ]]; then
		print -ru2 "skipping invalid file $name"
		continue
	fi
	j=-1
	while (( ++j < i )); do
		[[ ${pkgs[j]} = "$Source" ]] && break
	done
	if (( j == i )); then
		print -u2 "local $Source $Version"
		pkgs[i]=$Source
		lver[i++]=$Version
		continue
	fi
	for x in ${lver[j]}; do
		# skip dups (from .changes = .dsc probably) silently
		[[ $x = "$Version" ]] && continue 2
	done
	# put the newest local version leftmost
	set -A xa -- ${lver[j]}
	if dpkg --compare-versions "$Version" gt "${xa[0]}"; then
		print -u2 "newer $Source $Version"
		lver[j]="$Version ${lver[j]}"
	else
		print -u2 "older $Source $Version"
		lver[j]="${lver[j]} $Version"
	fi
done

print -u2 '\nrunning rmadison...'
rmadison -s sid "${pkgs[@]}" |&
while read -pr pkg pipe vsn pipe sid pipe arches; do
	#print -u2 "D: pkg<$pkg> vsn<$vsn> sid<$sid> arches<$arches>"
	arches=${arches//,/ }
	[[ " $arches " = *' source '* ]] || continue
	j=-1
	while (( ++j < i )); do
		[[ ${pkgs[j]} = "$pkg" ]] && break
	done
	if (( j == i )); then
		print -u2 "bogus $pkg $vsn ignored"
		continue
	fi
	x=${uver[j]}
	if [[ -z $x ]]; then
		print -u2 "found $pkg $vsn"
		uver[j]=$vsn
	elif [[ $x = "$vsn" ]]; then
		print -u2 "equal $pkg $vsn ignored"
	elif dpkg --compare-versions "$x" lt "$vsn"; then
		print -u2 "newer $pkg $vsn (dropping $x)"
		uver[j]=$vsn
	else
		print -u2 "older $pkg $vsn ignored"
	fi
done

c0=$'\033[0m'
c1=$'\033[1;31m'
c2=$'\033[1;32m'
c3=$'\033[1;33m'
c4=$'\033[1;34m'
print -ru2 "$c0"
print -u2

j=-1
while (( ++j < i )); do
	pkg=${pkgs[j]}
	lvs=${lver[j]}
	lv=${lvs%% *}
	uv=${uver[j]}

	if [[ -z $uv ]]; then
		uv=0~RM
		lc=$c1
		uc=$c1
	elif [[ $lv = "$uv"?('+b'+([0-9])) ]]; then
		lc=$c2
		uc=$c2
	elif dpkg --compare-versions "$lv" lt "$uv"; then
		lc=$c1
		uc=$c3
	else
		lc=$c3
		uc=$c4
	fi
	print -r -- "$c0$pkg $lc$lv$c0 $uc$uv$c0"
	[[ $lvs = $lv ]] && continue
	for lv in ${lvs#* }; do
		[[ $lv = "$uv"?('+b'+([0-9])) ]] && continue
		print -r -- "$c0$pkg $c4$lv$c0 -"
	done
done | sort | column -t
