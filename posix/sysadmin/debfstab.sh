#!/bin/sh
#-
# Copyright © 2020, 2021
#	mirabilos <m@mirbsd.org>
# Copyright © 2022
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
# Routines to pre-fill a GNU/Linux fstab(5) from a running system or
# a chroot/subset thereof. Note that whole-device bind mounts cannot
# be distinguished from nōn-bind mounts of the underlying device, in
# Linux.

debfstab_die() {
	echo >&2 "E: debfstab.sh: $*"
	exit 1
}

debfstab() (
	set +aeu
	eval '(set -o pipefail)' >/dev/null 2>&1 && set -o pipefail || :
	LC_ALL=C
	export LC_ALL
	unset LANGUAGE

	command -v perl >/dev/null 2>&1 || debfstab_die perl not found

	if test -n "$KSH_VERSION"; then
		writeln() { print -r -- "$1"; }
	else
		writeln() { printf '%s\n' "$1"; }
	fi

	case $1 in
	(///*) ;;
	(//*) debfstab_die 'cannot have basedir on UNC path' ;;
	esac
	basedir=$(readlink -f "${1:-/}") || debfstab_die cannot canonicalise basedir
	case $basedir in
	(//*) debfstab_die 'cannot have basedir on UNC path' ;;
	(/*) ;;
	(*) debfstab_die could not canonicalise basedir to absolute path ;;
	esac

	if command -v dmsetup >/dev/null 2>&1; then
		islv() {
			dmi=$(dmsetup --noheadings --nameprefixes splitname -- "$1")
			case $dmi in
			("DM_VG_NAME='/dev/mapper/"[a-zA-Z0-9+_.]*) ;;
			(*) return 1 ;;
			esac
			dmi=${dmi#"DM_VG_NAME='/dev/mapper/"}
			case $dmi in
			(*"'"[:\ ]"DM_LV_NAME='"[a-zA-Z0-9+_.]*"'"[:\ ]"DM_LV_LAYER=''") ;;
			(*) return 1 ;;
			esac
			dmi=${dmi%"'"[: ]"DM_LV_LAYER=''"}
			vg=${dmi%"'"[: ]"DM_LV_NAME='"*}
			lv=${dmi#*"'"[: ]"DM_LV_NAME='"}
			case x$vg in
			(x) return 1 ;;
			(*[!a-zA-Z0-9+_.-]*) return 1 ;;
			esac
			case x$lv in
			(x) return 1 ;;
			(*[!a-zA-Z0-9+_.-]*) return 1 ;;
			esac
			lvdev=/dev/$vg/$lv
			test "$lvdev" -ef "$1" || {
				#return 1
				echo >&2 "W: $lvdev from $1 does not match"
				lvdev='#!#'$lvdev
			}
			return 0
		}
	else
		islv() {
			return 1
		}
	fi

	command -v column >/dev/null 2>&1 || column() { cat; }
	# literal linefeed
	nl='
'
	{
		writeln '#/dev/... swap swap sw,discard=once 0 0configureyourswapdevice(s)here'
		writeln 'swap /tmp tmpfs defaults,noatime,nosuid,nodev 0 0configuretotaste'
		findmnt --real -abnrUuvo FSTYPE,TARGET,SOURCE,FSROOT,OPTIONS,LABEL,UUID,PARTLABEL,PARTUUID,FSTYPE | \
		    debfstab_unfuck_findmnt | {
		    hasroot=0
		    while IFS= read -r fst tgt src fsr opt ql qu qpl qpu sentinel; do
			if test -z "$tgt"; then
				echo >&2 "W: empty target in findmnt output"
				continue
			fi
			if test -z "$fst" || test -z "$src"; then
				writeln "#invalid-type-or-source ^$tgt"
				continue
			fi
			case $fsr in
			(/*) ;;
			(*)
				writeln "#invalid-fsroot ^$tgt"
				continue ;;
			esac
			test x"$fst" = x"$sentinel" || {
				echo >&2 "E: bogus findmnt output"
				writeln "#bogus-table ^$tgt"
				continue
			}
			case $tgt in
			($basedir)
				hasroot=1
				tgt=/ ;;
			(${basedir%/}/*)
				tgt=${tgt#${basedir%/}} ;;
			(*)
				continue ;;
			esac
			case $tgt in
			(/) pass=2 ;;
			(/boot*) pass=1 ;;
			(*) pass=3 ;;
			esac
			# copy a few whitelisted mount options
			opt=,$opt,
			opts=
			for x in rw ro discard nosuid nodev noexec \
			    noatime relatime; do
				case $opt in
				(*,$x,*) opts=$opts,$x ;;
				esac
			done
			# check for bind mount or LVM/UUID/LABEL
			odev=
			if test x"$fsr" != x"/"; then
				src=$(findmnt -abcefnrUuvo TARGET -- "$src" | \
				    debfstab_unfuck_findmnt) || src=
				case $src in
				(/*) ;;
				(*)
					writeln "#bind-no-src $tgt"
					continue ;;
				esac
				src=${src%/}$fsr
				case $src in
				($basedir)
					src=/ ;;
				(${basedir%/}/*)
					src=${src#${basedir%/}} ;;
				(*)
					writeln "#outside-bind $tgt"
					continue ;;
				esac
				opts=$opts,bind
				fst=none
				pass=0
			elif islv "$src"; then
				src=$lvdev
			elif test -n "$ql"; then
				odev=$src
				src=LABEL=$ql
			elif test -n "$qu"; then
				odev=$src
				src=UUID=$qu
			elif test -n "$qpl"; then
				odev=$src
				src=PARTLABEL=$qpl
			elif test -n "$qpu"; then
				odev=$src
				src=PARTUUID=$qpu
			fi
			# figure out more options
			case $fst in
			(ext4)
				opts=,auto_da_alloc$opts ;;
			esac
			opts=defaults$opts
			writeln "$src $tgt $fst $opts 0 $pass${odev:+$odev}"
		  done
		  test x"$hasroot" = x"1" || \
		    writeln '/dev/... / ... defaults 0 1makesuretoconfigure'
		}
	} | sort -k2,2 -k1 | {
		writeln '#spec file vfstype mntopts freq passno'
		cat
	} | column -t | sed \
	    -e "1s/\$/\\${nl}/" \
	    -e "s/^\\(.*\\)\\(.*\\)\$/# \\2\\${nl}\\1/" \
	    -e "s// /g" \
	    -e 's/  *$//'
)

debfstab_unfuck_findmnt() {
	# findmnt output escaping does not match fstab-expected one
	# and is additionally hard to parse in shell
	perl -ne '
		s/\ca/\\001/g;
		s/\\/\\134/g;
		s/\\134x([0-9a-fA-F][0-9a-fA-F])/sprintf "\\%03o", hex($1)/eg;
		y/ /\ca/;
		print $_;
	'
}

debfstab_unmangle() {
	perl -ne '
		s/\\([0-7][0-7][0-7])/chr(oct($1))/eg;
		print $_;
	'
}

if test -n "${debfstab_embed:-}"; then
	unset debfstab_embed
	return 0
fi

debfstab "$@"
