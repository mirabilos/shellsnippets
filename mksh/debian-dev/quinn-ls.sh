#!/bin/mksh
rcsid='$MirOS: contrib/hosted/tg/deb/quinn-ls.sh,v 1.3 2011/05/25 17:40:51 tg Exp $'
#-
# Copyright © 2011
#	Thorsten Glaser <tg@debian.org>
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

gather=cwd
mydir=$(realpath "$(dirname "$0")")

while getopts "l" ch; do
	case $ch {
	(l)	gather=installed ;;
	(*)	exit 1 ;;
	}
done
shift $((OPTIND - 1))

# Debian Policy 3.9.2.0, §5.6.1
function isdebpkg {
	[[ $1 = [a-z0-9]+([a-z0-9+.-]) ]]
}

# Debian Policy 3.9.2.0, §5.6.12
function isdebver {
	local epochglob uvglob dvglob

	# strict (must start with a digit)
	#uvglob='[0-9]*'
	# loose (should, but it's ok if not)
	uvglob='+'

	uvglob=$uvglob'([A-Za-z0-9.+~'

	# colon is allowed if we have an epoch
	if [[ $1 = +([0-9])':'* ]]; then
		epochglob='+([0-9])'\'':'\'
		uvglob=$uvglob':'
	fi

	# hyphen is allowed if we have a debian revision
	if [[ $1 = *'-'+([A-Za-z0-9+.~]) ]]; then
		dvglob=\'-\''+([A-Za-z0-9+.~])'
		uvglob=$uvglob'-'
	fi

	uvglob=$uvglob'])'

	eval [[ \$1 = $epochglob$uvglob$dvglob ]]
}

set -A pkgs
set -A lver
set -A uver
i=0
function do_gather {
	if ! isdebpkg "$Source"; then
		print -ru2 "skipping invalid Source '$Source', file $name"
		return 2
	fi
	if ! isdebver "$Version"; then
		print -ru2 "skipping invalid Version '$Version', file $name"
		return 2
	fi
	j=-1
	while (( ++j < i )); do
		[[ ${pkgs[j]} = "$Source" ]] && break
	done
	if (( j == i )); then
		print -ru2 "local $Source $Version"
		pkgs[i]=$Source
		lver[i++]=$Version
		return 0
	fi
	for x in ${lver[j]}; do
		# skip dups (from .changes = .dsc probably) silently
		[[ $x = "$Version" ]] && return 1
	done
	# put the newest local version leftmost
	set -A xa -- ${lver[j]}
	if dpkg --compare-versions "$Version" gt "${xa[0]}"; then
		print -ru2 "newer $Source $Version"
		lver[j]="$Version ${lver[j]}"
	else
		print -ru2 "older $Source $Version"
		lver[j]="${lver[j]} $Version"
	fi
	return 0
}

if [[ $gather = cwd ]]; then
	find . -name \*.changes -o -name \*.dsc |&
	while IFS= read -pr name; do
		Source=
		Version=
		eval $(sed -n \
		    -e '/^\(Source\): \([^ ]*\)\( .*\)*$/s//\1='\''\2'\''/p' \
		    -e '/^\(Version\): \([^ ]*\)$/s//\1='\''\2'\''/p' \
		    "$name")
		do_gather
	done
elif [[ $gather = installed ]]; then
	dpkg-query -Wf '${Package} ${Version} ${Source} ${Package}\n' |&
	while read -p name Version Source x rest; do
		if [[ $Source = *'('*')' ]]; then
			# this is not customary…
			rest=${Source##*'('}
			rest=${rest%')'}
			isdebver "$rest" && Version=$rest
		elif [[ $x = '('*')' ]]; then
			# Source:Version ≠ Version
			x=${x#'('}
			x=${x%')'}
			isdebver "$x" && Version=$x
		fi
		do_gather
	done
else
	exit 1
fi

print -u2 '\nrunning rmadison…'
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
		print -ru2 "bogus $pkg $vsn ignored"
		continue
	fi
	x=${uver[j]}
	if [[ -z $x ]]; then
		print -ru2 "found $pkg $vsn"
		uver[j]=$vsn
	elif [[ $x = "$vsn" ]]; then
		print -ru2 "equal $pkg $vsn ignored"
	elif dpkg --compare-versions "$x" lt "$vsn"; then
		print -ru2 "newer $pkg $vsn (dropping $x)"
		uver[j]=$vsn
	else
		print -ru2 "older $pkg $vsn ignored"
	fi
done

print -u2 '\nreading override files [bad bld ign]…'
# bad: mark RIGHT versions lower or equal as "bad"
# bld: mark RIGHT version equal as "building"
# ign: mark LEFT version equal as "ignored" and ignore not-in-upstream
for type in bad bld ign; do
	[[ -s $mydir/quinn-ls.$type ]] || continue
	while read pkg vsn; do
		if ! isdebpkg "$pkg"; then
			print -ru2 "skipping invalid package '$pkg'," \
			    override $type
			continue
		fi
		if ! isdebver "$vsn"; then
			print -ru2 "skipping invalid version '$vsn'," \
			     override $type
			continue
		fi
		print -ru2 "o:$type $pkg $vsn"
		epkg=${pkg//'+'/_p}
		epkg=${epkg//'.'/_d}
		epkg=${epkg//'-'/_u}
		eval over_${type}_${epkg}=\$vsn
	done <$mydir/quinn-ls.$type
done

c0=$'\033[0m'
c1=$'\033[1;31m'
c2=$'\033[1;32m'
c3=$'\033[1;33m'
c4=$'\033[1;34m'
c5=$'\033[1;35m'
c6=$'\033[1;36m'
print -ru2 "$c0"
print -ru2

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

	epkg=${pkg//'+'/_p}
	epkg=${epkg//'.'/_d}
	epkg=${epkg//'-'/_u}
	for type in bad bld ign; do
		eval over_$type=\$over_${type}_${epkg}
	done
	if [[ -n $over_ign && $lv = "$over_ign" ]]; then
		lc=$c6
		[[ $uv = '0~RM' ]] && uc=$c6
	fi
	[[ -n $over_bad ]] && dpkg --compare-versions "$uv" le "$over_bad" && \
	    uc=$c5
	[[ -n $over_bld && $uv = "$over_bld" ]] && uc=$c6

	print -r -- "$c0$pkg $lc$lv$c0 $uc$uv$c0"
	[[ $lvs = $lv ]] && continue
	for lv in ${lvs#* }; do
		[[ $lv = "$uv"?('+b'+([0-9])) ]] && continue
		print -r -- "$c0$pkg $c4$lv$c0 -"
	done
done | sort | column -t
