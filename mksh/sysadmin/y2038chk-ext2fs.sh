#!/bin/mksh
# © mirabilos Ⓕ MirBSD or CC0

export LC_ALL=C
unset LANGUAGE
set +e -o pipefail -o noglob
nl='
'
saveIFS=$IFS

if (( USER_ID != 0 )); then
	print -ru2 -- 'E: need root'
	exit 255
fi

ec=1
n=0
p=0
i=$(
	IFS=' '
	seen=' '
	# not a useless use of cat: procfs behaves too weird for sh
	cat /proc/mounts | while read -r dv rest; do
		[[ $seen != *" $dv "* ]] || continue
		print -r -- "$dv $rest"
		seen+="$dv "
	done | sort -rk2
    ) || exit 255
IFS=$nl
read -rAN -1 lines <<<"$i" || exit 255
IFS=$saveIFS
i=${#lines[*]}
print -ru2 "I: scanning $i mounted filesystems for ext2/3/4 filesystems"
while (( i-- )); do
	IFS=' '
	# 1=what 2=where 3=type 4=params 5=dump 6=pass
	set -- ${lines[i]}
	IFS=$saveIFS
	[[ $3 = ext[234]*(fs|dev) ]] || continue
	vis="${1@Q} (${2@Q})"
	print -ru2
	if [[ $1 != /* ]]; then
		let ++p ec=2
		print -ru2 "E: not an absolute device path: $vis"
		continue
	fi
	let ++n
	dat=$nl$(tune2fs -l "$1") || {
		let ++p ec=2
		print -ru2 "E: tune2fs for $vis failed, cannot check"
		continue
	}
	if [[ $dat = *"$nl"'Filesystem features:'*'sparse_super2'* ]]; then
		print -ru2 "I: $vis cannot be online-resized by Linux"
	fi
	if [[ $dat = *"$nl"'Filesystem revision #:'*([	 ])0* ]]; then
		let ++p
		print -ru2 "W: $vis has Y2038 problem and is a revision 0 filesystem"
		print -ru2 'N: only revision 1 filesystem support 256-byte inodes; see:'
		print -ru2 'N: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1086603#66'
		continue
	fi
	if [[ $dat != *"$nl"'Filesystem revision #:'*([	 ])1' '* ]]; then
		let ++p ec=2
		print -ru2 "E: $vis has unknown filesystem revision, cannot check"
		continue
	fi
	isz=${dat##*"$nl"'Inode size:'*([	 ])}
	if [[ $isz = "$dat" ]]; then
		let ++p ec=2
		print -ru2 "E: could not find out inode size for $vis, cannot check"
		continue
	fi
	isz=${isz%%"$nl"*}
	if [[ $isz = 256 ]]; then
		print -ru2 "I: $vis is okay (new default inode size 256)"
		continue
	fi
	if [[ $isz != [1-9]*([0-9]) ]] || (( ${#isz} > 9 )); then
		let ++p ec=2
		print -ru2 "E: $vis has weird inode size ${isz@Q}, cannot check"
		continue
	fi
	if (( $isz < 256 )); then
		let ++p
		print -ru2 "W: $vis has Y2038 problem ($isz-byte inodes)"
		print -ru2 'N: raise the inode size to 256 bytes; for example with:'
		print -ru2 'N: https://feeding.cloud.geek.nz/posts/upgrading-ext4-filesystem-for-y2k38/#comment-bf205bf98828b7ad52460c15fe277d64'
	else
		print -ru2 "I: $vis is okay ($isz-byte inodes)"
	fi
done

print
print "I: checked $n ext2/3/4 filesystems, $p with problems"
exit $(( p ? ec : 0 ))
