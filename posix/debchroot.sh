#!/bin/sh
#-
# Copyright © 2020, 2021
#	mirabilos <m@mirbsd.org>
# Copyright © 2019, 2020
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

debchroot_start() (
	set +eu
	debchroot__init "$1" mpt
	rv=$?
	test x"$rv" = x"0" || exit "$rv"
	echo >&2 "I: preparing chroot directory $(debchroot__e "$mpt")..."
	debchroot__prep "$mpt"
	rv=$?
	if test x"$rv" = x"0"; then
		echo >&2 "I: done, enter with one of:"
		echo >&2 "N: debchroot_go $(debchroot__q "$mpt") [name]"
		echo >&2 "N: debchroot_run [-n name] $(debchroot__q "$mpt") command …"
		exit 0
	fi
	debchroot__undo "$mpt"
	exit "$rv"
)

debchroot_stop() (
	set +eu
	debchroot__init "$1" mpt
	rv=$?
	test x"$rv" = x"0" || exit "$rv"
	debchroot__undo "$mpt"
	rv=$?
	if test x"$rv" = x"0"; then
		echo >&2 "I: retracted chroot directory $(debchroot__e "$mpt")"
	fi
)

debchroot_go() {
	debchroot_run ${2:+-n "$2"} "$1" su -l -w \
	    debian_chroot,LANG,LC_CTYPE,LC_ALL,TERM,TERMCAP
}

debchroot_run() (
	set +eu
	debchroot__name=
	if test x"$1" = x"-n"; then
		debchroot__name=$2
		shift; shift
	fi
	debchroot__init "$1" debchroot__mpt || exit 255
	shift
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
	exec chroot "$debchroot__mpt" "$@"
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
	local mp rv=0 x

	if test -t 2; then
		echo '[0m
	fi

	if test x"$(id -u)" != x"0"; then
		echo >&2 "E: superuser privilegues required"
		return 1
	fi

	case $1 in
	(//*)
		echo >&2 "E: cannot have chroot on UNC path (network)"
		return 1 ;;
	(/*)
		mp=$1 ;;
	(.)
		if ! mp=$(pwd); then
			echo >&2 "E: cannot canonicalise cwd"
			return 2
		fi ;;
	(*)
		echo >&2 "E: mountpoint $(debchroot__e "$1") no absolute path"
		return 1 ;;
	esac

	if ! mp=$(readlink -f "$mp"); then
		echo >&2 "E: cannot canonicalise mountpoint $(debchroot__e "$1")"
		return 2
	fi

	for x in /bin /dev /etc /proc /sbin /sys /tmp /usr/sbin; do
		if ! test -d "$mp$x/."; then
			echo >&2 "E: mountpoint $(debchroot__e "$1") missing $x"
			rv=1
			continue
		fi
		case $(readlink -f "$mp$x") in
		("$mp"/*) ;;
		(*)
			echo >&2 "E: mountpoint $(debchroot__e "$mp") $x escaping"
			rv=1
			;;
		esac
	done
	eval "$2=\$mp"
	return $rv
}

debchroot__prep() {
	local x rv

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
	    if ! mount -t tmpfs swap "$1/tmp"; then
		echo >&2 "E: cannot mount $(debchroot__e "$1")/tmp"
		return 1
	fi
	# /dev/pts is a bit trickier
	if ! mountpoint -q "$1/dev/pts"; then
		test -h "$1/dev/pts" && if ! rm "$1/dev/pts"; then
			echo >&2 "E: target has /dev/pts as symlink"
			return 3
		fi
		test -d "$1/dev/pts" || if ! rm "$1/dev/pts"; then
			echo >&2 "E: target has /dev/pts as nōn-directory"
			return 3
		fi
		test -d "$1/dev/pts" || if ! mkdir "$1/dev/pts"; then
			echo >&2 "E: cannot mkdir $(debchroot__e "$1")/dev/pts"
			return 2
		fi
		if ! mount --bind /dev/pts "$1/dev/pts"; then
			echo >&2 "E: cannot mount $(debchroot__e "$1")/dev/pts"
			return 1
		fi
	fi
	# tricky but needed only sometimes
	test -d /run/udev && test -d "$1/run/udev" && \
	    if x"$(readlink -f "$1/run/udev" || echo ERR)" != x"$1/run/udev"; then
		echo >&2 "W: $(debchroot__e "$1")/run/udev weird, not mounted"
	elif ! mount --bind /run/udev "$1/run/udev"; then
		echo >&2 "E: cannot mount $(debchroot__e "$1")/run/udev"
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
		return 1
	fi
	cat >"$1/usr/sbin/policy-rc.d" <<-\EOF
		#!/bin/sh
		exit 101
	EOF
	chmod 0755 "$1/usr/sbin/policy-rc.d"
	test -x "$1/usr/sbin/policy-rc.d" || {
		echo >&2 "E: cannot install policy-rc.d deny script"
		return 1
	}

	x=$(mktemp "$1/tmp/tf.XXXXXXXXXX") || {
		echo >&2 "E: cannot create temporary file"
		return 1
	}

	e="$(debchroot__e "$1")" chroot "$1" /bin/sh 7>"$x" <<\EOCHR
		LC_ALL=C; export LC_ALL; LANGUAGE=C; unset LANGUAGE
		mountpoint -q /dev/shm || {
			test -d /dev/shm || rm -f /dev/shm
			test -d /dev/shm || mkdir -p /dev/shm
			mount -t tmpfs swap /dev/shm
		}
		mountpoint -q /dev/shm || {
			echo >&2 "E: cannot mount $e/dev/shm"
			exit 1
		}

		exists() {
			test -h "$1" || test -e "$1"
		}

		trydivert() {
			trydivert1 "$@" </dev/null && trydivert2 "$@"
		}
		trydivert1() {
			local T p=false

			if exists $1.REAL; then
				exists $1 && p=true
			elif exists $1; then
				mv $1 $1.REAL || exit 1
			fi
			T=$(mktemp "/tmp/tf.XXXXXXXXXX") || {
				echo >&2 "E: cannot create temporary file"
				exit 1
			}
			dpkg-divert --local --quiet --rename \
			    --divert $1.REAL --add $1 2>"$T"
			rv=$?
			grep -v \
			    -e 'Essential.*no-rename' \
			    -e 'no-rename.*Essential' \
			    <"$T" >&2
			rm -f "$T"
			test x"$rv" != x"0" && \
			    command -v dpkg-divert >/dev/null 2>&1 && exit $rv
			$p || if exists $1; then
				echo >&2 "E: cannot clear pre-existing $2"
				exit 1
			fi
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
	rv=$?
	rv=$rv,"$(cat "$x")"
	rm -f "$x"
	test x"$rv" = x"0,dobro" || return 1

	# everything should be set up now
	return 0
}

debchroot__rev_mounts_do() (
	eval '(set -o pipefail)' >/dev/null 2>&1 && set -o pipefail
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
	local rv

	e="$(debchroot__e "$1")" chroot "$1" /bin/sh <<\EOCHR
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
	rv=$?

	base="$1" debchroot__rev_mounts_do xargs -0r sh -c '
		for mpt in "$@"; do
			case $mpt in
			("$base"/*) umount "$mpt" ;;
			esac
		done
	'
	sleep 1

	base="$1" debchroot__rev_mounts_do xargs -0r sh -c '
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
			("$base"/*)
				rv=1
				echo >&2 "W: could not umount" \
				    "$(debchroot__e "$mpt")"
				# try lazy umount…
				umount -l "$mpt"
				;;
			esac
		done
	' || {
		echo >&2 'N: perhaps some process still has it open?'
		rv=1
	}

	return $rv
}

if test -n "${debchroot_embed:-}"; then
	unset debchroot_embed
	return 0
fi

case $2:$1 in
(start:/*|stop:/*|go:/*)
	p=$1 cmd=$2
	shift; shift
	set -- "$cmd" "$p" "$@"
	;;
(run:/*)
	p=$1 cmd=$2
	shift; shift
	if test x"$1" = x"-n"; then
		n=$2
		shift; shift
		set -- "$cmd" -n "$n" "$p" "$@"
	else
		set -- "$cmd" "$p" "$@"
	fi
	;;
esac

case $1 in
(start)
	shift
	debchroot_start "$@"
	;;
(stop)
	shift
	debchroot_stop "$@"
	;;
(go)
	shift
	debchroot_go "$@"
	;;
(run)
	shift
	debchroot_run "$@"
	;;
(*)
	cat >&2 <<\EOF
Usage: (you may also give the chroot directory before the command)
	# set up policy-rc.d and mounts
	sh debchroot.sh start /path/to/chroot	# or “.” for cwd
	# run a shell or things in a started chroot
	sh debchroot.sh go /path/to/chroot [chroot-name]
	sh debchroot.sh run [-n chroot-name] /path/to/chroot cmd args…
	# disband policy-rc.d and all sub-mounts
	sh debchroot.sh stop /path/to/chroot
	# make the debchroot_* functions available
	debchroot_embed=1 . ./debchroot.sh
EOF
	case $1 in
	(help|-h|-\?|--help) exit 0 ;;
	esac
	exit 1
	;;
esac