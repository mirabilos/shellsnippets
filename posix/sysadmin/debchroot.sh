#!/bin/sh
#-
# Copyright © 2020, 2021, 2023
#	mirabilos <m@mirbsd.org>
# Copyright © 2019, 2020, 2022
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
# Utilities for handling chroots the current system can run binaries
# for, Debian chroots specifically, which possibly run in qemu-user.
# debchroot_start sets up invoke-rc.d(8) etc. for chroots, as to not
# start/stop any dæmons, and mounts several filesystems (if not done
# yet); debchroot_stop disbands them and umounts all filesystems un‐
# der the chroot base directory, including manually mounted ones, if
# possible; it tries to lazily umount those in use and warns.

debchroot__debchroot_='debchroot_'
debchroot__quiet=

debchroot_start() (
	set +aeu
	debchroot__skip 0
	debchroot__P=
	OPTIND=1
	while getopts "P:s:" debchroot__ch; do
		case $debchroot__ch in
		(P) debchroot__P=$OPTARG ;;
		(s) debchroot__skip start "$OPTARG" || exit 1 ;;
		(*) echo >&2 "E: debchroot_start: bad options"; exit 1 ;;
		esac
	done
	set -e
	shift $(($OPTIND - 1))
	if test -z "$debchroot__P"; then
		debchroot__P=$1
		shift
	fi
	set +e
	debchroot__init "$debchroot__P"
	debchroot__rv=$?
	test x"$debchroot__rv" = x"0" || exit "$debchroot__rv"
	echo >&2 "I: preparing chroot directory $(debchroot__e "$debchroot__mpt")..."
	debchroot__prep "$debchroot__mpt"
	debchroot__rv=$?
	test -n "$debchroot__quiet" || if test x"$debchroot__rv" = x"0"; then
		sed -e 's/[^[:print:]]/[7m?[0m/g' >&2 <<-EOF
		I: done, enter with one of:
		N: ${debchroot__debchroot_}go $(debchroot__q "$debchroot__mpt") [name]
		N: ${debchroot__debchroot_}run [-n name] [-w cmd] $(debchroot__q "$debchroot__mpt") command ...
		I: finally, undo and umount everything under the directory with:
		N: ${debchroot__debchroot_}stop $(debchroot__q "$debchroot__mpt")
		EOF
	fi
	test x"$debchroot__rv" = x"0" || debchroot__undo "$debchroot__mpt"
	exit "$debchroot__rv"
)

debchroot_stop() (
	set +aeu
	debchroot__P=
	OPTIND=1
	while getopts "P:" debchroot__ch; do
		case $debchroot__ch in
		(P) debchroot__P=$OPTARG ;;
		(*) echo >&2 "E: debchroot_stop: bad options"; exit 1 ;;
		esac
	done
	set -e
	shift $(($OPTIND - 1))
	if test -z "$debchroot__P"; then
		debchroot__P=$1
		shift
	fi
	set +e
	debchroot__init "$debchroot__P"
	debchroot__rv=$?
	test x"$debchroot__rv" = x"0" || exit "$debchroot__rv"
	debchroot__undo "$debchroot__mpt"
	debchroot__rv=$?
	test -n "$debchroot__quiet" || if test x"$debchroot__rv" = x"0"; then
		echo >&2 "I: retracted chroot directory $(debchroot__e "$debchroot__mpt")"
		echo >&2 "N: everything mounted below was umounted as well!"
	fi
	exit "$debchroot__rv"
)

debchroot_go() {
	debchroot__name=
	debchroot__P=
	OPTIND=1
	while getopts "n:P:" debchroot__ch; do
		case $debchroot__ch in
		(n) debchroot__name=$OPTARG ;;
		(P) debchroot__P=$OPTARG ;;
		(*) echo >&2 "E: debchroot_go: bad options"; return 1 ;;
		esac
	done
	shift $(($OPTIND - 1))
	if test -z "$debchroot__P"; then
		debchroot__P=${1:-}
		if test -z "$debchroot__name"; then
			debchroot__name=${2:-}
		fi
	elif test -z "$debchroot__name"; then
		debchroot__name=${1:-}
	fi
	set -- -P "$debchroot__P" -n "$debchroot__name" \
	    -- su -l -w \
	    debian_chroot,LANG,LC_CTYPE,LC_ALL,TERM,TERMCAP
	unset debchroot__ch debchroot__P debchroot__name
	debchroot_run "$@"
}

debchroot_run() (
	set +aeu
	debchroot__name=
	debchroot__P=
	debchroot__ccmd='exec chroot'
	OPTIND=1
	while getopts "n:P:w:" debchroot__ch; do
		case $debchroot__ch in
		(n) debchroot__name=$OPTARG ;;
		(P) debchroot__P=$OPTARG ;;
		(w) debchroot__ccmd=$OPTARG ;;
		(*) echo >&2 "E: debchroot_run: bad options"; exit 1 ;;
		esac
	done
	set -e
	shift $(($OPTIND - 1))
	if test -z "$debchroot__P"; then
		debchroot__P=$1
		shift
	fi
	set +e
	debchroot__init "$debchroot__P" || exit 255
	test -n "$debchroot__name" || \
	    test -h "$debchroot__mpt/etc/debian_chroot" || \
	    if test -s "$debchroot__mpt/etc/debian_chroot"; then
		debchroot__name=$(cat "$debchroot__mpt/etc/debian_chroot")
	fi
	test -n "$debchroot__name" || \
	    test -h "$debchroot__mpt/etc/hostname" || \
	    if test -s "$debchroot__mpt/etc/hostname"; then
		debchroot__name=$(cat "$debchroot__mpt/etc/hostname")
		# short hostname of chroot
		debchroot__name=${debchroot__name%%.*}
		# only if it differs from current hostname and not chained
		test -n "$debian_chroot" || case "$(hostname)" in
		("$debchroot__name"|"$debchroot__name".*) debchroot__name= ;;
		esac
	fi
	test -n "$debchroot__name" || debchroot__name=$debchroot__mpt
	debian_chroot=${debian_chroot:+"$debian_chroot|"}$debchroot__name
	export debian_chroot
	if test -t 2; then
		echo >&2 "I: entering chroot $(debchroot__e "$debchroot__mpt")" \
		    "as $(debchroot__e "$debchroot__name")"
	fi
	eval "$debchroot__ccmd"' "$debchroot__mpt" "$@"'
)

debchroot_rpi() (
	set +aeu
	debchroot__skip 0
	debchroot__P=
	debchroot_rpiname=
	OPTIND=1
	while getopts "n:P:s:" debchroot__ch; do
		case $debchroot__ch in
		(n) debchroot_rpiname=$OPTARG ;;
		(P) debchroot__P=$OPTARG ;;
		(s) debchroot__skip rpi "$OPTARG" || exit 1 ;;
		(*) echo >&2 "E: debchroot_rpi: bad options"; exit 1 ;;
		esac
	done
	set -e
	shift $(($OPTIND - 1))
	if test -z "$debchroot__P"; then
		debchroot__P=$1
		shift
	fi
	set +e
	test -n "$debchroot_rpiname" || debchroot_rpiname=$1
	debchroot__quiet=1
	case $debchroot__P in
	(/*) ;;
	(*)
		echo >&2 "E: device/image $(debchroot__e "$debchroot__P") not absolute"
		exit 1 ;;
	esac
	if test -b "$debchroot__P"; then
		debchroot__rpidv=$debchroot__P
		echo >&2 "I: preparing image device $(debchroot__e "$debchroot__rpidv")"
		debchroot__rpilo=
	elif test -f "$debchroot__P"; then
		debchroot__rpidv=$(losetup -f) || debchroot__rpidv="<ERROR:$?>$debchroot__rpidv"
		case $debchroot__rpidv in
		(/dev/loop*[!0-9]*)
			echo >&2 "E: losetup -f failed: $(debchroot__e "$debchroot__rpidv")"
			exit 1 ;;
		(/dev/loop*) ;;
		(*)
			echo >&2 "E: losetup -f failed: $(debchroot__e "$debchroot__rpidv")"
			exit 1 ;;
		esac
		echo >&2 "I: preparing image device $(debchroot__e "$debchroot__rpidv")" \
		    "for image file $(debchroot__e "$debchroot__P")"
		debchroot__rpilo=$debchroot__rpidv
		if ! losetup "$debchroot__rpilo" "$debchroot__P"; then
			echo >&2 "E: losetup failed"
			exit 1
		fi
	else
		echo >&2 "E: not a block device or image file: $(debchroot__e "$debchroot__P")"
		exit 1
	fi
	debchroot__rpixd=/dev/mapper/${debchroot__rpidv##*/}
	if ! kpartx -a -f -v -p p -t dos -s "$debchroot__rpidv"; then
		echo >&2 "E: kpartx failed"
		debchroot__lounsetup
		exit 1
	fi
	if ! test -b "${debchroot__rpixd}p2"; then
		echo >&2 "E: kpartx did not map expected partition"
		ls -l "${debchroot__rpixd}"* | sed \
		    -e 's/[^[:print:]]/[7m?[0m/g' -e 's/^/N: /' >&2
		kpartx -d -f -v -p p -t dos -s "$debchroot__rpidv"
		debchroot__lounsetup
		exit 1
	fi
	if ! e2fsck -p "${debchroot__rpixd}p2"; then
		echo >&2 "W: root filesystem check failed"
	fi
	if ! fsck.fat -p "${debchroot__rpixd}p1"; then
		echo >&2 "W: firmware/boot filesystem check failed"
	fi
	if ! debchroot__rpiT=$(mktemp -d /tmp/debchroot.XXXXXXXXXX) || \
	   test -z "$debchroot__rpiT" || \
	   ! chown 0:0 "$debchroot__rpiT" || \
	   ! chmod 0700 "$debchroot__rpiT" || \
	   ! mkdir "$debchroot__rpiT/mpt"; then
		echo >&2 "E: could not create mountpoint"
		test -z "$debchroot__rpiT" || rm -rf "$debchroot__rpiT"
		kpartx -d -f -v -p p -t dos -s "$debchroot__rpidv"
		debchroot__lounsetup
		exit 1
	fi
	debchroot__rpimpt=$debchroot__rpiT/mpt
	if ! mount -t ext4 -o noatime,discard "${debchroot__rpixd}p2" "$debchroot__rpimpt"; then
		echo >&2 "E: could not mount image root filesystem"
		rm -rf "$debchroot__rpiT"
		kpartx -d -f -v -p p -t dos -s "$debchroot__rpidv"
		debchroot__lounsetup
		exit 1
	fi
	if test -h "$debchroot__rpimpt/boot"; then
		echo >&2 "W: not mounting firmware/boot: /boot is a symlink"
		debchroot__rpibmp=
	elif test -d "$debchroot__rpimpt/boot"; then
		if test -h "$debchroot__rpimpt/boot/firmware"; then
			echo >&2 "W: not mounting firmware/boot:" \
			    "/boot/firmware exists but is a symlink"
			debchroot__rpibmp=
		elif test -d "$debchroot__rpimpt/boot/firmware"; then
			debchroot__rpibmp=/boot/firmware
		elif test -e "$debchroot__rpimpt/boot/firmware"; then
			echo >&2 "W: not mounting firmware/boot:" \
			    "/boot/firmware exists but is no directory"
			debchroot__rpibmp=
		else
			debchroot__rpibmp=/boot
		fi
	else
		echo >&2 "W: not mounting firmware/boot: /boot is missing"
		debchroot__rpibmp=
	fi
	test -z "$debchroot__rpibmp" || \
	    if ! mount -t vfat -o noatime,discard "${debchroot__rpixd}p1" "$debchroot__rpimpt$debchroot__rpibmp"; then
		echo >&2 "W: not mounting firmware/boot: attempt failed"
	fi
	(
		debchroot__skipinit=2
		debchroot_start "$debchroot__rpimpt" || exit 1
		debchroot_go "$debchroot__rpimpt" "$debchroot_rpiname"
	)
	debchroot__rv=$?
	echo >&2 "I: umounting and ejecting"
	debchroot__rpiE=
	debchroot_stop "$debchroot__rpimpt" || debchroot__rpiE=1
	umount "$debchroot__rpimpt" || debchroot__rpiE=1
	if mountpoint -q "$debchroot__rpimpt"; then
		echo >&2 "E: not removing mountpoint" \
		    "$(debchroot__e "$debchroot__rpimpt") because it is still in use"
		debchroot__rpiE=1
		# try lazy umount…
		umount -l "$debchroot__rpimpt"
	else
		rm -rf "$debchroot__rpiT"
	fi
	kpartx -d -f -v -p p -t dos -s "$debchroot__rpidv" || debchroot__rpiE=1
	debchroot__lounsetup || debchroot__rpiE=1
	case $debchroot__rv,$debchroot__rpiE in
	(0,1) debchroot__rv=1 ;;
	esac
	test -n "$debchroot__rpiE" || echo >&2 "I: retracted image $(debchroot__e "$debchroot__P")"
	exit $debchroot__rv
)

debchroot__e() {
	debchroot__esc <<EOF
${1}X
EOF
}
debchroot__esc() {
	tr '\n' '' | { cat; echo; } | sed \
	    -e 's/X$//' \
	    -e "s/'/'\\\\''/g" \
	    -e "s/^/'/" \
	    -e "s/\$/'/" \
	    -e 's/[^[:print:]]/[7m?[0m/g'
}
debchroot__q() {
	sed \
	    -e "s/'/'\\\\''/g" \
	    -e "1s/^/'/" \
	    -e "\$s/X\$/'/" \
	    <<EOF
${1}X
EOF
}

debchroot__init() {
	if test -t 2; then
		echo '[0m' | tr -d '\n' >&2
	fi

	if test x"$(id -u)" != x"0"; then
		echo >&2 "E: superuser privilegues required"
		return 1
	fi

	case $1 in
	(///*)
		;;
	(//*)
		echo >&2 "E: cannot have chroot on UNC path (network) $(debchroot__e "$1")"
		unset debchroot__initd
		return 1 ;;
	(/*)
		;;
	(.)
		debchroot__initd=$(pwd) || debchroot__initd="<ERROR:$?>$debchroot__initd"
		case $debchroot__initd in
		(/*)
			debchroot__init "$debchroot__initd"
			return $?
			;;
		(*)
			echo >&2 "E: cannot canonicalise cwd $(debchroot__e "$debchroot__initd")"
			unset debchroot__initd
			return 2
			;;
		esac ;;
	(*)
		echo >&2 "E: mountpoint $(debchroot__e "$1") no absolute path"
		return 1 ;;
	esac

	debchroot__mpt=$(readlink -f "$1") || debchroot__mpt="<ERROR:$?>$debchroot__mpt"
	case $debchroot__mpt in
	(//*)
		echo >&2 "E: canonical mountpoint $(debchroot__e "$1") is UNC path $(debchroot__e "$debchroot__mpt")"
		unset debchroot__initd debchroot__mpt
		return 1 ;;
	(/*)
		# ///* also ends up here or canonicalisation failed
		;;
	(*)
		echo >&2 "E: canonical mountpoint $(debchroot__e "$1") bad $(debchroot__e "$debchroot__mpt")"
		unset debchroot__initd debchroot__mpt
		return 2 ;;
	esac

	debchroot__initrv=0
	for debchroot__initd in /bin /dev /etc /proc /sbin /sys /tmp /usr /usr/sbin; do
		case $debchroot__initrv:$debchroot__initd in
		(1:/*/*) continue ;;
		esac
		case $(readlink -f "$debchroot__mpt$debchroot__initd") in
		("$debchroot__mpt"/*) ;;
		(*)
			if test -h "$debchroot__mpt$debchroot__initd"; then
				echo >&2 "E: mountpoint $(debchroot__e "$debchroot__mpt") escaping $debchroot__initd"
			elif test -e "$debchroot__mpt$debchroot__initd"; then
				echo >&2 "E: mountpoint $(debchroot__e "$debchroot__mpt") unreal $debchroot__initd"
			else
				echo >&2 "E: mountpoint $(debchroot__e "$1") missing $debchroot__initd"
			fi
			debchroot__initrv=1
			;;
		esac
	done
	unset debchroot__initd
	eval "unset debchroot__initrv; return $debchroot__initrv"
}

debchroot__skipinit=0
debchroot__skip() {
	if test x"$1" = x"q"; then
		echo "tmp|dev|devpts|devshm|run|runudev"
		return 0
	fi
	if test x"$1" = x"0"; then
		test x"$debchroot__skipinit" = x"2" || {
			debchroot__skip_tmp=0
			debchroot__skip_dev=0
			debchroot__skip_devpts=0
			debchroot__skip_devshm=0
			debchroot__skip_run=0
			debchroot__skip_runudev=0
		}
		debchroot__skipinit=1
		return 0
	fi
	case $2 in
	(tmp)
		debchroot__skip_tmp=1 ;;
	(dev)
		debchroot__skip_dev=1
		debchroot__skip_devpts=1
		debchroot__skip_devshm=1
		;;
	(devpts)
		debchroot__skip_devpts=1 ;;
	(devshm)
		debchroot__skip_devshm=1 ;;
	(run)
		debchroot__skip_run=1 ;;
	(runudev)
		debchroot__skip_runudev=1 ;;
	(*)
		echo >&2 "E: debchroot_$1: bad -s option argument"
		return 1 ;;
	esac
	return 0
}

debchroot__prep() {
	# unless mounted, mount basic filesystems first; assume workable /dev though
	test -f "$1/proc/cmdline" || \
	    if ! mount -t proc proc "$1/proc"; then
		echo >&2 "E: cannot mount $(debchroot__e "$1")/proc"
		return 1
	fi
	test -d "$1/sys/devices" || \
	    if ! mount -t sysfs sysfs "$1/sys"; then
		echo >&2 "E: cannot mount $(debchroot__e "$1")/sys"
		return 1
	fi
	test -s "$1/sys/firmware/efi/efivars" && \
	    if ! mount -t efivarfs efivars "$1/sys/firmware/efi/efivars"; then
		echo >&2 "E: cannot mount $(debchroot__e "$1")/sys/firmware/efi/efivars"
		return 1
	fi
	# only if not symlinked, e.g. to var/tmp
	test -h "$1/tmp" || mountpoint -q "$1/tmp" || \
	    if test x"$debchroot__skip_tmp" = x"1"; then
		test -n "$debchroot__quiet" || \
		    echo >&2 "W: skipping /tmp mount as requested"
	elif ! mount -t tmpfs swap "$1/tmp"; then
		echo >&2 "E: cannot mount $(debchroot__e "$1")/tmp"
		return 1
	fi

	# chroot job response file
	debchroot__prepj=$(mktemp "$1/tmp/tf.XXXXXXXXXX") || debchroot__prepj="<ERROR:$?>$debchroot__prepj"
	case $debchroot__prepj in
	("$1/tmp/"*) ;;
	(*)
		echo >&2 "E: cannot create temporary file $(debchroot__e "$debchroot__prepj")"
		test -z "$debchroot__prepj" || rm -f "$debchroot__prepj"
		unset debchroot__prepj
		return 1 ;;
	esac

	# do /run which may (unusually) be a symlink
	chroot "$1" /usr/bin/env mountpoint -q /run || \
	    if test x"$debchroot__skip_run" = x"1"; then
		test -n "$debchroot__quiet" || \
		    echo >&2 "W: skipping /run mount as requested"
	elif ! chroot "$1" /bin/sh 7>"$debchroot__prepj" -ec '
		test -d /run || mkdir /run
		cd /run
		tar -cf - -b 1 --one-file-system --warning=no-file-ignored . >&7
	    '; then
		echo >&2 "E: cannot pack up old $(debchroot__e "$1")/run"
		rm "$debchroot__prepj"
		unset debchroot__prepj
		return 1
	elif ! mount -t tmpfs swap "$1/run"; then
		echo >&2 "E: cannot mount $(debchroot__e "$1")/run"
		rm "$debchroot__prepj"
		unset debchroot__prepj
		return 1
	elif ! chroot "$1" /bin/sh 7<"$debchroot__prepj" -ec '
		cd /run
		tar -xf - --same-permissions --same-owner <&7
		if test -h /etc/resolv.conf; then
			test -e resolvconf || mkdir resolvconf
		fi
		test -e udev || mkdir udev
	    '; then
		echo >&2 "E: cannot restore old $(debchroot__e "$1")/run"
		umount "$1/run"
		rm "$debchroot__prepj"
		unset debchroot__prepj
		return 1
	fi

	# /dev is tricky, consider uid/gid mismatch between host and chroot
	mountpoint -q "$1/dev" || \
	    if test x"$debchroot__skip_dev" = x"1"; then
		test -n "$debchroot__quiet" || \
		    echo >&2 "W: skipping /dev{,/pts,/shm} mounts as requested"
	else
		debchroot__prept=$(mktemp -d "$1/tmp/mnt.XXXXXXXXXX") || debchroot__prept="<ERROR:$?>$debchroot__prept"
		case $debchroot__prept in
		("$1/tmp/"*) ;;
		(*)
			echo >&2 "E: cannot create temporary mountpoint $(debchroot__e "$debchroot__prept")"
			test -z "$debchroot__prept" || rmdir "$debchroot__prept"
			rm "$debchroot__prepj"
			unset debchroot__prepj debchroot__prept
			return 1 ;;
		esac
		if ! mount -t tmpfs -o mode=0755,uid=0,gid=0 sdev "$debchroot__prept"; then
			echo >&2 "E: cannot mount temporary tmpfs on $(debchroot__e "$debchroot__prept")"
			rm -r "$debchroot__prept" "$debchroot__prepj"
			unset debchroot__prepj debchroot__prept
			return 1
		fi
		mkdir "$debchroot__prept/dev"
		if ! mount -t tmpfs -o mode=0755,uid=0,gid=0 sdev "$debchroot__prept/dev"; then
			echo >&2 "E: cannot mount target /dev tmpfs"
			umount "$debchroot__prept"
			rm -r "$debchroot__prept" "$debchroot__prepj"
			unset debchroot__prepj debchroot__prept
			return 1
		fi
		(
			set -e
			cd /dev
			tar -cf - -b 1 --one-file-system --warning=no-file-ignored .
		) >"$debchroot__prept/dev/.archive" || {
			echo >&2 "E: cannot pack up /dev"
			umount "$debchroot__prept/dev"
			umount "$debchroot__prept"
			rm -r "$debchroot__prept" "$debchroot__prepj"
			unset debchroot__prepj debchroot__prept
			return 1
		}
		debchroot__prepd=${debchroot__prept#"$1"}/dev
		export debchroot__prepd
		chroot "$1" /bin/sh 7>"$debchroot__prepj" <<\EOCHR
			LC_ALL=C; export LC_ALL; LANGUAGE=C; unset LANGUAGE
			set -e
			cd "$debchroot__prepd"
			exec 6<.archive
			rm .archive
			tar -xf - --same-permissions --same-owner <&6
			rm -f log
			rm -rf pts shm
			mkdir pts
			if test -h /dev/shm; then
				cp -a /dev/shm .
			else
				mkdir shm
			fi
			echo klaar >&7
EOCHR
		debchroot__preprv=$?
		unset debchroot__prepd
		debchroot__preprv=$debchroot__preprv,"$(cat "$debchroot__prepj")"
		test x"$debchroot__preprv" = x"0,klaar" || {
			echo >&2 "E: cannot set up target /dev"
			umount "$debchroot__prept/dev"
			umount "$debchroot__prept"
			rm -r "$debchroot__prept" "$debchroot__prepj"
			unset debchroot__prepj debchroot__prept debchroot__preprv
			return 1
		}
		unset debchroot__preprv
		(
			set -e
			cd /dev
			find . \( -type s -o -path ./log \) -print0
		) >"$debchroot__prepj" || {
			echo >&2 "E: cannot discover /dev sockets"
			umount "$debchroot__prept/dev"
			umount "$debchroot__prept"
			rm -r "$debchroot__prept" "$debchroot__prepj"
			unset debchroot__prepj debchroot__prept
			return 1
		}
		(
			set -e
			cd "$debchroot__prept/dev"
			<"$debchroot__prepj" xargs -0rI @@ touch @@
			<"$debchroot__prepj" xargs -0rI @@ mount --bind /dev/@@ @@
		) || {
			echo >&2 "E: cannot set up /dev sockets"
			umount "$debchroot__prept/dev"
			umount "$debchroot__prept"
			rm -r "$debchroot__prept" "$debchroot__prepj"
			unset debchroot__prepj debchroot__prept
			return 1
		}
		mount --make-private "$debchroot__prept"
		if ! mount --move "$debchroot__prept/dev" "$1/dev"; then
			echo >&2 "E: cannot finalise target /dev"
			umount "$debchroot__prept/dev"
			umount "$debchroot__prept"
			rm -r "$debchroot__prept" "$debchroot__prepj"
			unset debchroot__prepj debchroot__prept
			return 1
		fi
		umount "$debchroot__prept" && rmdir "$debchroot__prept" || :
		unset debchroot__prept
	fi
	# /dev/pts is a bit tricky… consider /dev might not be from us
	if test ! -h "$1/dev/pts" && mountpoint -q "$1/dev/pts"; then
		test -n "$debchroot__quiet" || \
		    echo >&2 "I: /dev/pts already mounted"
	elif test x"$debchroot__skip_devpts" = x"1"; then
		test -n "$debchroot__quiet" || \
		    echo >&2 "W: skipping /dev/pts mount as requested"
	else
		test ! -h "$1/dev/pts" || if ! rm "$1/dev/pts"; then
			echo >&2 "E: target has /dev/pts as symlink"
			rm "$debchroot__prepj"
			unset debchroot__prepj
			return 3
		fi
		test -d "$1/dev/pts" || if ! rm "$1/dev/pts"; then
			echo >&2 "E: target has /dev/pts as non-directory"
			rm "$debchroot__prepj"
			unset debchroot__prepj
			return 3
		fi
		test -d "$1/dev/pts" || if ! mkdir "$1/dev/pts"; then
			echo >&2 "E: cannot mkdir $(debchroot__e "$1")/dev/pts"
			rm "$debchroot__prepj"
			unset debchroot__prepj
			return 2
		fi
		if ! mount --bind /dev/pts "$1/dev/pts"; then
			echo >&2 "E: cannot mount $(debchroot__e "$1")/dev/pts"
			rm "$debchroot__prepj"
			unset debchroot__prepj
			return 1
		fi
	fi
	# tricky but needed only sometimes
	test -d /run/udev && test -d "$1/run/udev" && \
	    if test x"$debchroot__skip_runudev" = x"1"; then
		test -n "$debchroot__quiet" || \
		    echo >&2 "W: skipping /run/udev mount as requested"
	elif test x"$(readlink -f "$1/run/udev" || echo ERR)" != x"$1/run/udev"; then
		echo >&2 "W: $(debchroot__e "$1")/run/udev weird, not mounted"
	elif mountpoint -q "$1/run/udev"; then
		: nothing
	elif ! mount --bind /run/udev "$1/run/udev"; then
		echo >&2 "E: cannot mount $(debchroot__e "$1")/run/udev"
		rm "$debchroot__prepj"
		unset debchroot__prepj
		return 1
	fi
	# /dev/shm is hardest, can be /run/shm with symlinks in either direction
	# so do that in the chroot, same as policy-rc.d setup

	if test -h "$1/usr/sbin/policy-rc.d" || \
	   test -e "$1/usr/sbin/policy-rc.d"; then
		rm -f "$1/usr/sbin/policy-rc.d"
		test -d "$1/usr/sbin/policy-rc.d" && rmdir "$1/usr/sbin/policy-rc.d"
	fi
	if test -h "$1/usr/sbin/policy-rc.d" || \
	   test -e "$1/usr/sbin/policy-rc.d"; then
		echo >&2 "E: cannot clear pre-existing policy-rc.d script"
		rm "$debchroot__prepj"
		unset debchroot__prepj
		return 1
	fi
	cat >"$1/usr/sbin/policy-rc.d" <<-\EOF
		#!/bin/sh
		exit 101
	EOF
	chmod 0755 "$1/usr/sbin/policy-rc.d"
	test -x "$1/usr/sbin/policy-rc.d" || {
		echo >&2 "E: cannot install policy-rc.d deny script"
		rm "$debchroot__prepj"
		unset debchroot__prepj
		return 1
	}

	debchroot__prepd="$(debchroot__e "$1")"
	export debchroot__prepd
	case $debchroot__skip_devshm$debchroot__quiet in
	(0) debchroot__prepnoshm=0 ;;
	(1) debchroot__prepnoshm=1 ;;
	(1*) debchroot__prepnoshm=2 ;;
	(*) debchroot__prepnoshm=0 ;;
	esac
	export debchroot__prepnoshm
	chroot "$1" /bin/sh 7>"$debchroot__prepj" <<\EOCHR
		LC_ALL=C; export LC_ALL; LANGUAGE=C; unset LANGUAGE
		# ensure /dev/null exists
		test -e /dev/null || {
			if test -h /dev/null; then
				odevnull=$(readlink /dev/null) || odevnull=
				rm -f /dev/null
			else
				odevnull=
			fi
			rdevnull() {
				rm -f /dev/null
				test -z "$odevnull" || \
				    ln -s -- "$odevnull" /dev/null
			}
			trap rdevnull EXIT
			mknod -m0666 /dev/null c 1 3
		}
		# note mountpoint, test -d follow; rm+mkdir is ephemeral
		if test x"$debchroot__prepnoshm" = x"1"; then
			mountpoint -q /dev/shm || \
			    echo >&2 "W: skipping /dev/shm mount as requested"
		elif test x"$debchroot__prepnoshm" = x"0"; then
			mountpoint -q /dev/shm || {
				test -d /dev/shm || rm -f /dev/shm
				test -d /dev/shm || mkdir -p /dev/shm
				mount -t tmpfs swap /dev/shm
			}
			mountpoint -q /dev/shm || {
				echo >&2 "E: cannot mount $debchroot__prepd/dev/shm"
				exit 1
			}
		fi

		exists() {
			test -h "$1" || test -e "$1"
		}

		trydivert() {
			trydivert1 "$@" </dev/null && trydivert2 "$@"
		}
		trydivert1() {
			debchroot__tdp=false

			if exists $1.REAL; then
				exists $1 && debchroot__tdp=true
			elif exists $1; then
				mv $1 $1.REAL || exit 1
			fi
			debchroot__tdT=$(mktemp "/tmp/tf.XXXXXXXXXX") || {
				echo >&2 "E: cannot create temporary file"
				exit 1
			}
			dpkg-divert --local --quiet --rename \
			    --divert $1.REAL --add $1 2>"$debchroot__tdT"
			debchroot__tdE=$?
			grep -v \
			    -e 'Essential.*no-rename' \
			    -e 'no-rename.*Essential' \
			    <"$debchroot__tdT" | sed \
			    -e 's/[^[:print:]]/[7m?[0m/g' >&2
			rm -f "$debchroot__tdT"
			unset debchroot__tdT
			test x"$debchroot__tdE" != x"0" && \
			    command -v dpkg-divert >/dev/null 2>&1 && exit $debchroot__tdE
			unset debchroot__tdE
			$debchroot__tdp || if exists $1; then
				echo >&2 "E: cannot clear pre-existing $2"
				exit 1
			fi
			unset debchroot__tdp
		}
		trydivert2() {
			cat >$1
			chmod 0755 $1
			test -x $1 || {
				echo >&2 "E: cannot install fake $2"
				exit 1
			}
		}

		trydivert /sbin/start-stop-daemon start-stop-daemon <<-\EOF
			#!/bin/sh
			echo 1>&2
			echo 'Warning: Fake start-stop-daemon called, doing nothing.' 1>&2
			exit 0
		EOF
		exists /sbin/initctl && trydivert /sbin/initctl Upstart <<-\EOF
			#!/bin/sh
			if [ "$1" = version ]; then exec /sbin/initctl.REAL "$@"; fi
			echo 1>&2
			echo 'Warning: Fake initctl called, doing nothing.' 1>&2
			exit 0
		EOF

		echo dobro >&7
EOCHR
	debchroot__preprv=$?
	unset debchroot__prepd
	debchroot__preprv=$debchroot__preprv,"$(cat "$debchroot__prepj")"
	rm -f "$debchroot__prepj"
	unset debchroot__prepj
	test x"$debchroot__preprv" = x"0,dobro" || {
		unset debchroot__preprv
		return 1
	}
	unset debchroot__preprv

	# everything should be set up now
	return 0
}

debchroot__rev_mounts_do() (
	eval '(set -o pipefail)' >/dev/null 2>&1 && set -o pipefail || :
	LC_ALL=C; export LC_ALL; LANGUAGE=C; unset LANGUAGE
	# make this literal newline and tab!
	nl='
'
	tab='	'
	# this relies on linux/fs/proc_namespace.c doing:
	# err = seq_path_root(m, &mnt_path, &p->root, " \t\n\\");
	</proc/mounts cut -f2 -d' ' | tr '\n' '\0' | sed -z \
	    -e "s!\\\\011!$tab!g" -e 's!\\040! !g' \
	    -e "s!\\\\012!\\$nl!g" -e 's!\\134!\\!g' | \
	    sort -zr | "$@"
)

debchroot__undo() {
	chroot "$1" /bin/sh <<\EOCHR
		LC_ALL=C; export LC_ALL; LANGUAGE=C; unset LANGUAGE
		rv=0

		exists() {
			test -h "$1" || test -e "$1"
		}

		if command -v dpkg-divert >/dev/null 2>&1; then
			undiverti() {
				dpkg-divert --local --quiet --rename \
				    --remove "$1" || rv=1
			}
			undivertn() { undiverti "$@"; }
		else
			undiverti() {
				mv "$1.REAL" "$1" || rv=1
			}
			undivertn() { :; }
		fi
		undivert() {
			exists "$1.REAL" || {
				undivertn "$1"
				return 0
			}
			rm -f "$1"
			if exists "$1"; then
				echo >&2 "E: cannot rm $1 before undivert"
				rv=1
			fi
			undiverti "$1"
			if exists "$1.REAL"; then
				echo >&2 "E: undivert $1 failed to rm REAL"
				rv=1
			fi
			exists "$1" || {
				echo >&2 "E: undivert $1 failed to rename"
				rv=1
			}
		}

		undivert /sbin/initctl
		undivert /sbin/start-stop-daemon

		rm -f /usr/sbin/policy-rc.d
		if exists /usr/sbin/policy-rc.d; then
			echo >&2 "E: failed to remove policy-rc.d script"
			rv=1
		fi

		exit $rv
EOCHR
	debchroot__undoE=$?

	debchroot_umtree "$1" || {
		echo >&2 'N: perhaps some process still has it open?'
		debchroot__undoE=1
	}

	eval "unset debchroot__undoE; return $debchroot__undoE"
}

debchroot_umtree() {
	debchroot__umbase=$1
	export debchroot__umbase

	debchroot__rev_mounts_do xargs -0r sh -c '
		for mpt in "$@"; do
			case $mpt in
			("$debchroot__umbase"/*) umount "$mpt" ;;
			esac
		done
	' sh || :

	sleep 1

	debchroot__umres=0
	debchroot__rev_mounts_do xargs -0r sh -c '
		debchroot__e() {
			debchroot__esc <<EOF
${1}X
EOF
		}
		debchroot__esc() {
			tr '\''\n'\'' '\'''\'' | { cat; echo; } | sed \
			    -e '\''s/X$//'\'' \
			    -e "s/'\''/'\''\\\\'\'''\''/g" \
			    -e "s/^/'\''/" \
			    -e "s/\$/'\''/" \
			    -e '\''s/[^[:print:]]/[7m?[0m/g'\''
		}

		rv=0
		for mpt in "$@"; do
			case $mpt in
			("$debchroot__umbase"/*)
				rv=1
				echo >&2 "W: could not umount" \
				    "$(debchroot__e "$mpt")"
				# try lazy umount…
				umount -l "$mpt"
				;;
			esac
		done
		exit $rv
	' sh || debchroot__umres=1

	unset debchroot__umbase
	eval "unset debchroot__umres; return $debchroot__umres"
}

debchroot__lounsetup() {
	test -n "$debchroot__rpilo" || return 0
	losetup -d "$debchroot__rpilo"
	if losetup "$debchroot__rpilo" >/dev/null 2>&1; then
		echo >&2 "W: $debchroot__rpilo still in use"
		return 1
	fi
	return 0
}

if test -n "${debchroot_embed:-}"; then
	unset debchroot_embed
	return 0
fi

debchroot__debchroot_="$0 "
command -v "$0" >/dev/null 2>&1 || \
    debchroot__debchroot_="sh $debchroot__debchroot_"
test -s "$0" || debchroot__debchroot_='sh debchroot.sh '
test -z "$SUDO_UID" || debchroot__debchroot_="sudo $debchroot__debchroot_"

case $2:$1 in
(start:/*|stop:/*|go:/*|run:/*|rpi:/*|start:.|stop:.|go:.|run:.)
	p=$1 cmd=$2
	shift; shift
	set -- "$cmd" -P "$p" "$@"
	;;
(help:*|-h:*|-\?:*|--help:*)
	set -- help
	;;
esac

rv=255
case $1 in
(start)
	shift
	debchroot_start "$@"
	rv=$?
	;;
(stop)
	shift
	debchroot_stop "$@"
	rv=$?
	;;
(go)
	shift
	debchroot_go "$@"
	rv=$?
	;;
(run)
	shift
	debchroot_run "$@"
	rv=$?
	;;
(rpi)
	shift
	debchroot_rpi "$@"
	rv=$?
	;;
(*)
	case $0 in
	(*/*) selfpath=$(debchroot__q "$0") || selfpath= ;;
	(*) selfpath=$(debchroot__q "./$0") || selfpath= ;;
	esac
	test -s "$0" || selfpath=
	if test -t 2; then
		echo '[0m' | tr -d '\n' >&2
	fi
	sed -e 's/[^	[:print:]]/[7m?[0m/g' >&2 <<EOF
Usage: (you may also give the chroot directory before the command)
	# set up policy-rc.d and mounts
	${debchroot__debchroot_}start [opts] /path/to/chroot	# or "." for cwd
	# opts can be: -s dir to skip [$(debchroot__skip q)]
	# run a shell or things in a started chroot
	${debchroot__debchroot_}go /path/to/chroot [chroot-name]
	${debchroot__debchroot_}run [-n chroot-name] [-w cmd] /p/t/chroot cmd args...
	# cmd is the chroot wrapper, "exec chroot" by default
	# disband policy-rc.d and all sub-mounts
	${debchroot__debchroot_}stop /path/to/chroot
	# mount RPi SD and enter it (p1 assumed firmware/boot, p2 root)
	${debchroot__debchroot_}rpi [opts] /dev/mmcblk0|/path/to/image [chroot-name]
	# make the debchroot_* functions available
	debchroot_embed=1; . ${selfpath:-./debchroot.sh}
EOF
	case $1 in
	(help|-h|-\?|--help) exit 0 ;;
	esac
	exit 1
	;;
esac
stty sane <&2 2>/dev/null
tput cnorm 2>/dev/null
tput sgr0 2>/dev/null
exit $rv
