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
# Installs a Raspberry Pi 3B+ image from scratch (tested on a Debian
# bullseye/sid host system, others should work as well given suitab‐
# ly up-to-date tools), using qemu-user/binfmt_misc emulation to run
# the foreign architecture steps in a chroot.

# some shellcheck configuration:
# - not always true, and more compatible
# shellcheck disable=SC2004 shell=sh
# - yes, we use UCS/UTF-8 characters, how’s t̲h̲a̲t̲ even surprising?
# shellcheck disable=SC1111 disable=SC1112
# - enable some optional checks
# shellcheck enable=avoid-nullary-conditions enable=deprecate-which

#########
# SETUP #
#########

ht='	'
nl='
'
IFS=" $ht$nl"
POSIXLY_CORRECT=1
export POSIXLY_CORRECT
LANGUAGE=C
LC_ALL=C.UTF-8
export LC_ALL
unset LANGUAGE
safe_PATH=/bin:/sbin:/usr/bin:/usr/sbin
PATH=$PATH:$safe_PATH  # just to make sure
export safe_PATH PATH
d_arm64='64-bit ARMv8 (aarch64)'
d_armhf='32-bit ARMv7 with hardware Floating Point (fast)'
d_armel='32-bit ARMv5 with software FPU (slow), untested'

needprintf=
if test -n "$KSH_VERSION"; then
	p() {
		# ↓ runs on Korn Shell only
		# shellcheck disable=SC2039
		typeset i
		for i in "$@"; do
			print -ru2 -- "$i"
		done
	}
elif test x"$(printf '%s\n' 'a b' c 2>/dev/null)" = x"a b${nl}c"; then
	p() {
		printf '%s\n' "$@" >&2
	}
else
	needprintf=y
	p() {
		for p_arg in "$@"; do
			echo "$p_arg" >&2
		done
	}
fi

################################
# ERROR HANDLING AND UNWINDING #
################################

T=
loopdev=
kpx=
mpt=
dieteardown() {
	set -x
	if test -n "$mpt"; then
		umount "$mpt/tmp"
		umount "$mpt/proc"
		umount "$mpt/dev/shm"
		umount "$mpt/dev/pts"
		umount "$mpt/boot/firmware"
		umount "$mpt"
	fi
	mpt=
	if test -n "$kpx"; then
		kpartx -d -f -v -p p -t dos -s "$dvname"
	fi
	kpx=
	if test -n "$loopdev"; then
		losetup -d "$loopdev"
	fi
	loopdev=
}
diecleanup() {
	stty sane <&2 2>/dev/null
	tput cnorm 2>/dev/null
	tput sgr0 2>/dev/null
	dieteardown
	if test -n "$T"; then
		cd /
		rm -rf --one-file-system "$T"
	fi
	T=
}
die() {
	pfx='E: '
	for arg in "$@"; do
		p "$pfx$arg"
		pfx='N: '
	done
	diecleanup
	exit 1
}
trap 'p "I: exiting, cleaning up…"; diecleanup; exit 0' EXIT
trap 'p "E: caught SIGHUP, cleaning up…"; diecleanup; exit 129' HUP
trap 'p "E: caught SIGINT, cleaning up…"; diecleanup; exit 130' INT
trap 'p "E: caught SIGQUIT, cleaning up…"; diecleanup; exit 131' QUIT
trap 'p "E: caught SIGPIPE, cleaning up…"; diecleanup; exit 141' PIPE
trap 'p "E: caught SIGTERM, cleaning up…"; diecleanup; exit 143' TERM

#########################
# PREREQUISITE CHECKING #
#########################

# ensure $TERM is set to something the chroot can use
case $TERM in
(Eterm|Eterm-color|ansi|cons25|cons25-debian|cygwin|dumb|hurd|linux|mach|mach-bold|mach-color|mach-gnu|mach-gnu-color|pcansi|rxvt|rxvt-basic|rxvt-m|rxvt-unicode|rxvt-unicode-256color|screen|screen-256color|screen-256color-bce|screen-bce|screen-s|screen-w|screen.xterm-256color|sun|vt100|vt102|vt220|vt52|wsvt25|wsvt25m|xterm|xterm-256color|xterm-color|xterm-debian|xterm-mono|xterm-r5|xterm-r6|xterm-vt220|xterm-xfree86)
	# list from ncurses-base (6.1+20181013-2+deb10u1)
	;;
(screen.*|screen-*)
	# aliases possibly from ncurses-term
	TERM=screen ;;
(rxvt.*|rxvt-*)
	# let’s hope…
	TERM=rxvt ;;
(xterm.*|xterm-*)
	# …this works…
	TERM=xterm ;;
(linux.*)
	# …probably
	TERM=linux ;;
(*)
	die "Your terminal type '$TERM' is not supported by ncurses-base." \
	    'Maybe run this script in GNU screen?' ;;
esac

# check that all utilities we use exist; give Debian paths for missing ones
rv=0
chkhosttool() {
	chkhosttool_prog=$1; shift
	chkhosttool_missing=0
	for chkhosttool_fullpath in "$@"; do
		chkhosttool_basename=${chkhosttool_fullpath##*/}
		# POSIX way to check for utility (builtin or $PATH)
		if command -v "$chkhosttool_basename" >/dev/null 2>&1; then
			: # let’s hope it’s compatible with Debian’s
		else
			test $chkhosttool_missing = 1 || \
			    p "E: please install $chkhosttool_prog to continue!"
			chkhosttool_missing=1
			p "N: missing: $chkhosttool_fullpath"
		fi
	done
	test $chkhosttool_missing = 0 || rv=1
}
chkhosttool bc /usr/bin/bc
chkhosttool binfmt-support /usr/sbin/update-binfmts
chkhosttool coreutils /bin/cat /bin/chmod /bin/chown /bin/cp /bin/dd \
    /bin/ln /bin/mkdir /bin/mktemp /bin/rm /bin/stty /usr/bin/env \
    /usr/bin/id /usr/bin/printf /usr/bin/truncate /usr/sbin/chroot
chkhosttool debootstrap /usr/sbin/debootstrap
chkhosttool dosfstools /sbin/mkfs.msdos
chkhosttool dpkg /usr/bin/dpkg-deb
chkhosttool e2fsprogs /sbin/mkfs.ext4
chkhosttool eatmydata /usr/bin/eatmydata
chkhosttool fdisk /sbin/fdisk
chkhosttool kpartx /sbin/kpartx
chkhosttool mount /bin/mount /bin/umount /sbin/losetup
chkhosttool ncurses-bin /usr/bin/tput
chkhosttool qemu-user-static /usr/bin/qemu-aarch64-static \
    /usr/bin/qemu-arm-static
chkhosttool util-linux /bin/lsblk /sbin/fstrim /usr/bin/unshare
chkhosttool whiptail /usr/bin/whiptail
unset chkhosttool_prog
unset chkhosttool_missing
unset chkhosttool_fullpath
unset chkhosttool_basename
test x"$rv" = x"0" || exit "$rv"
if test -n "$needprintf"; then
	p() {
		printf '%s\n' "$@" >&2
	}
	unset p_arg
fi
unset needprintf

# needs direct device I/O and chroot
case $(id -u) in
(0) ;;
(*) die 'Please run this as root.' ;;
esac

# create temporary directory as base of operations
T=$(mktemp -d /tmp/mkrpi3b+img.XXXXXXXXXX) || \
    die 'cannot create temporary directory'
case $T in
(/*) ;;
(*) die "non-absolute temporary directory: $T" ;;
esac
chmod 700 "$T" || die 'chmod failed'
cd "$T" || die 'cannot cd into temporary directory'

#########################
# DIALOGUE PREPARATIONS #
#########################

# syntax: assign tgtvar fallback glob
assign() {
	assign_tgt=$1; shift
	# ↓ false positive (eval)
	# shellcheck disable=SC2034
	assign_nil=$1; shift
	eval "$assign_tgt=\$assign_nil"
	test -n "$1" && test -e "$1" || return 0
	eval "$assign_tgt=\$*"
}

# state machine wrappers
Srun() {
	s=0
	while test x"$s" != x"999"; do
		sthis=$s
		s=$(($s+1))
		"$@"
	done
}
Sdone() {
	s=999
}
Snext() {
	s=$(($sthis+${1:-1}))
}
Sredo() {
	s=$sthis
}
Sprev() {
	s=$(($sthis-${1:-1}))
}
alias sdone='Sdone; return'
alias sskip='Snext 2; return'
alias snext='Snext; return'
alias sprev='Sprev; return'
alias sredo='Sredo; return'

# wrap around whiptail
w() {
	whiptail --backtitle 'mkrpi3b+img.sh' --output-fd 4 4>res "$@"
	rv=$?
	res=$(cat res) || die cannot read whiptail result file
	return $rv
}
# w plus advance the state machine
dw() {
	w "$@" && snext $rv
	if test x"$s" = x"0"; then
		p '' 'I: aborted by user'
		diecleanup
		exit $rv
	fi
	sprev $rv
}
# wrapper for w --yesno plus handle the state machine
ynw() {
	ynwv=$1; shift
	eval "ynwc=\$$ynwv"
	# ↓ false positive (eval)
	# shellcheck disable=SC2154
	# ↓ IFS splitting actually required
	# shellcheck disable=SC2086
	if w $ynwc "$@"; then
		eval "$ynwv="
		snext
	elif test x"$rv" = x"1"; then
		eval "$ynwv=--defaultno"
		snext
	else
		sprev
	fi
}
ynwtrue() {
	eval "test -z \"\$$1\""
}
ynwfalse() {
	eval "test -n \"\$$1\""
}

################################
# ENSURE MINIMUM TERMINAL SIZE #
################################

states_termsize() {
	# ↓ IFS splitting actually required
	# shellcheck disable=SC2046
	set -- $(stty size) || die 'stty failed'
	test $# -eq 2 || die 'stty weird output' "$@"
	case "$*" in
	(*[!\ 0-9]*) die 'stty invalid output' "$@" ;;
	esac
	case $sthis in
	(0)
		#### INITIAL TERMINAL SIZE CHECK
		if test "$1" -ge 24 && test "$2" -ge 80; then
			sskip
		fi ;;
	(1)
		#### TTY TOO SMALL REQUEST CHANGE
		p 'E: tty size too small' \
		  "N: ${2}x$1 actual" "N: 80x24 minimum"
		sleep 5
		;;
	(2)
		#### SEE WHETHER THAT HELPED
		if test "$1" -ge 24 && test "$2" -ge 80; then
			sskip
		fi ;;
	(3)
		#### STILL REQUEST CHANGE
		w --title 'Terminal size' --msgbox \
		    "Your terminal is too small (only ${2}x$1 glyphs).

Please resize your terminal to at least 80x24 now, then press Enter to continue. Afterwards, DO *NOT* change the terminal size again! APT and debconf really do not like that, and your display will be garbled if you do…

Change size now, press Enter only afterwards to continue." 14 61
		sskip ;;
	(4)
		#### INITIAL TTY SIZE OK
		w --title 'Terminal size' --msgbox \
		    "Your terminal size is okay: ${2}x$1 glyphs, minimum 80x24 required.

Please DO *NOT* change the terminal size for the entire runtime of this script, starting now! APT and debconf really do not like that, and your display will be garbled if you do…

Press Enter to continue." 14 72
		;;
	(5)
		#### SEE THAT WE END UP AT CORRECT SIZE
		if test "$1" -ge 24 && test "$2" -ge 80; then
			sdone
		fi ;;
	(6)
		#### NOT GOOD ENOUGH
		if w --title 'Terminal size' --yes-button OK --no-button Exit \
		    --yesno "Your terminal still is too small (${2}x$1).

We requested you to change it to at least 80x24 (and keep the size constant afterwards). Please do so now, or press Escape or use the Exit button if you really can’t.

Remember to *NOT* change the size afterwards, since APT and debconf cache it and do not like sudden changes below them; if you do, your display will be garbled…

Change size now, press Enter only afterwards to continue." 17 61; then
			sprev
		fi
		p '' 'I: aborted by user'
		exit 0 ;;
	esac
}
Srun states_termsize

#################
# DIALOGUE LOOP #
#################

# default values
assign devices '' /dev/sd[a-z]
tgtdev=MANUAL
tgtimg=/dev/sdX
swsize=0
# ↓ false positive (eval)
# shellcheck disable=SC2034
swmode=			# nonempty=after (else (true) before the root partition)
myfqdn=rpi3bplus.lan.tarent.invalid
userid=pi
# ↓ false positive (eval)
# shellcheck disable=SC2034
setcma=			# empty means yes (set CMA to higher value by default)
# ↓ false positive (eval)
# shellcheck disable=SC2034
dropsd=--defaultno	# nonempty means no (do not drop systemd by default)
pkgadd=-		# - means out default values
tgarch=arm64
# state machine (menu question number)
states_menu() {
	case $sthis in
	(0)
		sgoback_devchoice=$sthis
		#### WHICH TARGET DEVICE? (CHOICE)
		set --
		# ↓ false positive (eval in assign)
		# shellcheck disable=SC2154
		for x in $devices; do
			set -- "$@" "$x" "$x"
		done
		if dw --title 'Select target device' \
		    --notags --default-item "$tgtdev" \
		    --menu 'Select which device to write to. IT WILL BE OVERWRITTEN!' \
		    20 72 10 MANUAL 'Enter path manually (/dev/XXX or image file)' "$@"; then
			tgtdev=$res
			if test x"$tgtdev" = x"MANUAL"; then
				tgtimg=/dev/sdX
			else
				tgtimg=$tgtdev
				sskip
			fi
		fi
		;;
	(1)
		sgoback_devname=$sthis
		#### WHICH TARGET DEVICE OR IMAGE? (FREETEXT)
		if dw --title 'Choose target device' \
		    --inputbox 'Enter path to target raw device (e.g. /dev/sdX) or to pre-existing, already correctly-sized, image file to use:' \
		    20 72 "$tgtimg"; then
			tgtimg=$res
		fi
		;;
	(2)
		# minimum disc size (MBR, firmware, root, possibly swap)
		minsz=1792
		#### WHETHER TO CREATE A SWAP PARTITION
		if dw --title 'Create a swap partition?' \
		    --inputbox 'Enter size of desired swap space; leave empty or set to 0 to not create a swap partition.

Swap space is used to page out data from system memory (RAM) to allow programs to use more (faux) memory than physically present; especially in RPi devices with only 1 GiB RAM or less, this may be highly preferrable. Using it will, however, wear out your µSD card much faster; therefore, it is disabled by default.

Typical sizes are: 256, 512, 1024 (= 1 GiB), 1536, 2048 (= 2 GiB)
Use no more than twice the amount of RAM installed.

Size in MiB:' \
		    20 72 "$swsize"; then
			x=0
			while test $x = 0; do
				case $swsize in
				(0*) swsize=${swsize#0} ;;
				(*) x=1 ;;
				esac
			done
			swsize=${swsize:-0}
			case $swsize in
			(*[!0-9]*)
				w --msgbox "The given swap partition size '$swsize' was not numeric!" 8 72
				sredo ;;
			esac
			if test ${#swsize} -gt 5; then
				w --msgbox "The given swap partition size '$swsize' was improbably large!" 8 72
				sredo
			fi
			if test "$swsize" -gt 0; then
				minsz=$(($minsz+$swsize))
			else
				sskip
			fi
		fi
		;;
	(3)
		#### WHERE TO PUT THE SWAP PARTITION
		ynw swmode --title 'Swap partition location' \
		    --yes-button Before --no-button After \
		    --yesno 'Do you want to have the swap partition situated before or after the root partition? (The firmware partition is always placed first.)

Putting it before makes enlarging the root partition (such as when moving to a larger µSD card, expanding) slightly easier.

Putting it after makes it possible to add the space to the root partition later, disabling swap, when free space has become tight.' \
		    14 72
		;;
	(4)
		#### VALIDATE IMAGE/DEVICE PATH/SIZE/ETC. / CREATE SPARSE FILE
		# step to go back to if things fail
		if test x"$tgtdev" = x"MANUAL"; then
			s=$sgoback_devname
		else
			s=$sgoback_devchoice
		fi
		# check image/device: path, existence, not a symlink (for stability)
		case $tgtimg in
		(/[!/]*) ;;
		(*)
			w --msgbox 'The chosen device/image path is not an absolute pathname!' 8 72
			# sgoback_* above
			return ;;
		esac
		test -e "$tgtimg" || if w --title 'Nonexistent path chosen' \
		    --ok-button 'Create' --cancel-button 'Go back' \
		    --inputbox 'The chosen device/image path does not exist!

If you wish to create it, enter a size in the format accepted by GNU coreutils’ truncate(1) utility (that is, a number followed by M for MiB or G for GiB, in its most basic form) and select the “Create” button (or just press Enter). This will create a sparse image file (which will only take up the space actually used by data). We have pre-filled the input field with the minimum allowed image size.

The image will be created *immediately* and never deleted!

If you do not with to create it, press Escape to go back instead.' \
		    20 72 ${minsz}M; then
			truncate -s "$res" "$tgtimg" || \
			    die 'failed to create sparse file'
			test -e "$tgtimg" || die 'sparse file not created'
		else
			# sgoback_* above
			return
		fi
		if test -h "$tgtimg"; then
			tgtimg=$(readlink -f "$tgtimg") || die 'error in readlink -f'
			sredo
		fi
		# whether block device, regular file or grounds for refusal
		if test -b "$tgtimg"; then
			dvname=$tgtimg
		elif test -f "$tgtimg"; then
			# losetup -f does not echo chosen devicem which we need
			dvname=$(losetup -f) || die 'losetup failed in get'
			case $dvname in
			(/dev/loop*) ;;
			(*) die 'losetup shows weird result' "$dvname" ;;
			esac
			loopdev=$dvname
			losetup "$loopdev" "$tgtimg" || die 'losetup failed in set'
		else
			w --msgbox 'The chosen device/image path is neither a block special device nor a regular file!' 8 72
			# sgoback_* above
			return
		fi
		# we now have a block (or loopback device) we can check
		test -b "$dvname" || die 'block device missing'
		sz=$(lsblk --nodeps --noheadings --output SIZE --bytes \
		    --raw "$dvname") || die 'lsblk failed'
		case $sz in
		(*[!0-9]*) die 'lsblk shows weird result' "$sz" ;;
		([0-9]*) ;;
		(*) die 'lsblk returned empty result' ;;
		esac
		# use bc for arithmetic: numbers too large for shell
		case $(echo "a=0; if($sz<(${minsz}*1048576)) a=1; a" | bc) in
		(0) ;;
		(1)
			w --msgbox "The chosen device/image path is smaller than $minsz MiB!" 8 72
			dieteardown
			# sgoback_* above
			return ;;
		(*) die 'bc returned weird result' ;;
		esac
		# and it’s big enough for the Debian installation; accept
		sz=$(echo "scale=2; $sz/1048576" | bc) || die 'bc cannot divide'
		dw --title 'Accept target device' --defaultno \
		    --yesno "Your chosen target device: $tgtimg

Block device $dvname of size $sz MiB

Do you REALLY want to use this as target device
and OVERWRITE ALL DATA with no chance of recovery?" 14 72
		sz=${sz%.*}
		;;
	(5)
		#### HOSTNAME FOR THE SYSTEM
		if dw --title 'Enter target hostname' \
		    --inputbox 'Enter fully-qualified hostname the target device should have:' \
		    20 72 "$myfqdn"; then
			# one trailing full stop is allowed (like DNS)
			myfqdn=${res%.}
			# check length [1; 255]
			if test "${#myfqdn}" -lt 1; then
				w --msgbox 'The given hostname is empty!' 8 72
				sredo
			fi
			if test "${#myfqdn}" -gt 255; then
				w --msgbox 'The given hostname is too long!' 8 72
				sredo
			fi
			# check characters used
			case $myfqdn in
			(.*|*.)
				w --msgbox 'The given hostname begins or ends with a full stop!' 8 72
				sredo ;;
			(*[!.0-9A-Za-z-]*)
				w --msgbox 'The given hostname contains invalid characters!' 8 72
				sredo ;;
			esac
			# similar for the component labels
			IFS=.; set -o noglob
			# ↓ IFS splitting actually required
			# shellcheck disable=SC2086
			set -- $myfqdn
			IFS=" $ht$nl"; set +o noglob
			for x in "$@"; do
				if test "${#x}" -lt 1 || test "${#x}" -gt 63; then
					w --msgbox 'The given hostname contains parts that are empty or too long!' 8 72
					sredo
				fi
				# invalid label composition
				case $x in
				(-*)
					w --msgbox 'The given hostname contains parts that begin with a hyphen-minus!' 8 72
					sredo ;;
				(*-)
					w --msgbox 'The given hostname contains parts that end with a hyphen-minus!' 8 72
					sredo ;;
				(*[!0-9A-Za-z-]*)
					w --msgbox 'The given hostname contains invalid characters!' 8 72
					sredo ;;
				esac
			done
			case $myfqdn in
			(*.local)
				w --msgbox 'The given hostname uses the TLD reserved for mDNS!' 8 72
				sredo ;;
			esac
		fi
		;;
	(6)
		#### USERNAME TO CREATE FOR INITIAL SSH AND SUDO
		if dw --title 'Enter initial username' \
		    --inputbox 'Enter UNIX username of the initially created user (which has full sudo access):' \
		    20 72 "$userid"; then
			userid=$res
			# Unix limitations
			if test -z "$userid"; then
				w --msgbox 'The given username is empty!' 8 72
				sredo
			fi
			if test "${#userid}" -gt 32; then
				w --msgbox 'The given username is too long! (32 bytes max.)' 8 72
				sredo
			fi
			# default /etc/adduser.conf NAME_REGEX
			case $userid in
			(*[!a-z0-9_-]*)
				w --msgbox 'The given username contains invalid characters!' 8 72
				sredo ;;
			([!a-z]*)
				w --msgbox 'The given username does not start with a letter!' 8 72
				sredo ;;
			esac
		fi
		;;
	(7)
		#### ADJUST DEFAULT CMA SIZE?
		ynw setcma --title 'Default CMA size' \
		    --yesno "Raise default CMA from 64 to 128 MiB?

This is especially useful when you’ll be using graphics." \
		    10 72
		;;
	(8)
		#### SELECT INIT SYSTEM
		ynw dropsd --title 'Choose the init system' \
		    --yesno "Change init system from systemd to sysvinit?

The default init system in Debian 10 “buster” is systemd with usrmerge.
This option allows you to change to traditional SysV init with classic
filesystem layout.

Most users will say “No” here." \
		    10 72
		;;
	(9)
		#### ARCHITECTURE
		case $tgarch in
		(arm64) set -- on off off ;;
		(armhf) set -- off on off ;;
		(armel) set -- off off on ;;
		(*) die "huh? tgarch<$tgarch>" ;;
		esac
		if dw --title 'Choose target architecture' \
		    --radiolist 'Please select which Debian architecture to install on the target. The default is usually fine, as you can run 32-bit binaries (both armel and armhf) under a 64-bit kernel normally, with Multi-Arch.

Use the cursor keys ↑ and ↓ followed by Space to select an item; press Enter to accept and continue, or Esc to go back.' \
		   15 72 3 \
		   arm64 "$d_arm64 " "$1" \
		   armhf "$d_armhf " "$2" \
		   armel "$d_armel " "$3"; then
			tgarch=$res
		fi
		;;
	(10)
		#### EXTRA PACKAGES TO INSTALL
		if test x"$pkgadd" = x"-"; then
			# openssh-server will generate the server keys using
			# random bytes from the host, in the chroot (good!)
			pkgadd='anacron bind9-host bridge-utils postfix bsd-mailx curl etckeeper ethtool ntp openssh-server patch pv rdate reportbug unscd wget _WLAN_'
			blurb=' We have provided you with a selection of default useful system utilities and services, which you can change if you wish, of course.'
		else
			blurb=
		fi
		if dw --title 'Extra packages to install' \
		    --inputbox "Enter extra packages to install, separated by space.$blurb Some other extra packages, like less and sudo, are always installed.

You can use the macro _WLAN_ to select packages needed to support WiFi. To install packages from Backports, append “/buster-backports” to the package name, e.g. “musescore3/buster-backports”. Removing packages by appending “-” to their name is also possible, as this list is passed as-is to apt-get install.

Press ^U (Ctrl-U) to delete the entire line.
Enter just - to restore the default and start editing anew." \
		    20 72 "$pkgadd"; then
			pkgadd=$res
			test x"$pkgadd" = x"-" && sredo
		fi
		;;
	(11)
		#### SUMMARY BEFORE DOING ANYTHING (except sparse file creation)
		if test "$swsize" -gt 0; then
			if ynwfalse swmode; then
				paging=after
			else
				paging=before
			fi
			paging="$swsize MiB, $paging the root partition"
		else
			paging='no'
		fi
		if ynwtrue setcma; then
			cma=128
		else
			cma=64
		fi
		if ynwfalse dropsd; then
			init='systemd with usrmerge'
		else
			init='sysvinit with standard filesystem'
		fi
		case $tgarch in
		(arm64|armhf|armel) eval "arch=\"\$tgarch: \$d_$tgarch\"" ;;
		(*) die "huh? tgarch<$tgarch>" ;;
		esac
		# ↓ false positive (eval) on $arch
		# shellcheck disable=SC2154
		dw --title 'Proceed with installation?' --defaultno \
		    --yesno "Do you wish to proceed and DELETE ALL DATA from the target device? (Choosing “No” or pressing Escape allows you to go back to each individual step for changing the information.) Summary of settings:

Target  : $tgtimg (≥ $sz MiB)
Pagefile: $paging
Hostname: $myfqdn
Username: $userid
CMA size: $cma MiB                  Machine: $arch
init/FHS: $init

Packages: $pkgadd" 20 72
		;;
	(12)
		sdone
		;;
	esac
}
Srun states_menu

##########################
# PREPARE DISC STRUCTURE #
##########################

p 'I: ok, proceeding; this may take some time…' \
  'N: be prepared to interactively answer more questions though'
sleep 3
# store some random seed for later, 1ˢᵗ half (taken from host CSPRNG)
dd if=/dev/urandom bs=256 count=1 of=rnd 2>/dev/null || die 'dd rnd1 failed'
# create MBR with empty BIOS partition table
s='This SD card boots on a Raspberry Pi 3B+ only!'
# x86 machine code outputting message then stopping
# ↓ dynamically composed format string
# shellcheck disable=SC2059
printf '\xE8\x'"$(echo "obase=16; ${#s}+5" | bc)"'\0\r\n' >data
printf '%s' "$s" | tee txt >>data
printf '\r\n\0\x5E\16\x1F\xAC\10\xC0\x74\xFE\xB4\16\xBB\7\0\xCD\20\xEB\xF2' \
    >>data
dd if=/dev/zero bs=16 count=4 of=pt 2>/dev/null || die 'dd mbr1 failed'
printf '\x55\xAA' >>pt
# cobble together wiping partition first MiB “en passant”
dd if=/dev/urandom bs=256 count=4096 of=mbr 2>/dev/null || die 'dd mbr2 failed'
dd if=mbr bs=1048576 of="$dvname" seek=1 2>/dev/null || die 'dd clr1 failed'
dd if=mbr bs=1048576 of="$dvname" seek=256 2>/dev/null || die 'dd clr2 failed'
dd if=data of=mbr conv=notrunc 2>/dev/null || die 'dd mbr3 failed'
dd if=pt of=mbr bs=1 seek=446 conv=notrunc 2>/dev/null || die 'dd mbr4 failed'
# write to disc, wiping pre-partition space as well
dd if=mbr bs=1048576 of="$dvname" 2>/dev/null || die 'dd mbr5 failed'
rm data mbr
# layout partition table (per board-specific requirements)
if test x"$paging" = x"no"; then cat <<-EOF
	n
	p
	1
	2048
	524287
	n
	p
	2
	524288

	t
	1
	c
	a
	1
	w
	EOF
elif ynwfalse swmode; then cat <<-EOF
	n
	p
	1
	2048
	524287
	n
	p
	2
	524288
	$(echo "($sz-$swsize)*2048-1" | bc)
	n
	p
	3
	$(echo "($sz-$swsize)*2048" | bc)

	t
	1
	c
	t
	3
	82
	a
	1
	w
	EOF
else cat <<-EOF
	n
	p
	1
	2048
	524287
	n
	p
	3
	524288
	$((524288+($swsize*2048)-1))
	n
	p
	2
	$((524288+($swsize*2048)))

	t
	1
	c
	t
	3
	82
	a
	1
	w
	EOF
fi >fdsk
fdisk -c=nondos -t MBR -w always -W always "$tgtimg" <fdsk || \
    die 'fdisk failed'
# map partitions so we can access them under a fixed name
kpx=/dev/mapper/${dvname##*/}
kpartx -a -f -v -p p -t dos -s "$dvname" || die 'kpartx failed'
# create filesystems
test -b "${kpx}p1" || die 'cannot kpartx firmware partition'
eatmydata mkfs.msdos -f 1 -F 32 -m txt -n RASPI_FIRMW -v "${kpx}p1" || \
    die 'mkfs.msdos failed'
test -b "${kpx}p2" || die 'cannot kpartx root partition'
eatmydata mkfs.ext4 -e remount-ro -E discard -L RASPI_root \
    -U random "${kpx}p2" || die 'mkfs.ext4 failed'
if test "$swsize" -gt 0; then
	test -b "${kpx}p3" || die 'cannot kpartx swap partition'
	eatmydata dd if=/dev/zero bs=1048576 count=1 of="${kpx}p3" 2>/dev/null
	eatmydata mkswap -L RASPI_swap "${kpx}p3" || die 'mkswap failed'
fi

# mount filesystems
mpt=$T/mnt
mkdir "$mpt" || die 'mkdir mpt failed'
mount -t ext4 -o noatime,discard "${kpx}p2" "$mpt" || die 'mount (ext4) failed'
mkdir "$mpt/boot" || die 'mkdir mpt/boot failed'
mkdir "$mpt/boot/firmware" || die 'mkdir mpt/boot/firmware failed'
mount -t vfat -o noatime,discard "${kpx}p1" "$mpt/boot/firmware" || \
    die 'mount (vfat) failed'

#################################################
# INSTALL DEBIAN, FIRST STAGE (CROSS-BOOTSTRAP) #
#################################################

p 'I: created filesystems, now debootstrapping…'
if ynwfalse dropsd; then
	init=
else
	init=--no-merged-usr
fi
case $tgarch in
(arm64) kernel=linux-image-arm64 qemu=qemu-aarch64-static ;;
(armhf) kernel=linux-image-armmp qemu=qemu-arm-static ;;
(armel) kernel=linux-image-rpi qemu=qemu-arm-static ;;
(*) die "huh? tgarch<$tgarch>" ;;
esac
# retrieve path to the command (its existence was tested earlier)
qemu_user_static=$(command -v $qemu) || die 'huh?'
case $qemu_user_static in
(/*) ;;
(*) die "$qemu cannot be found" ;;
esac
test -x "$qemu_user_static" || \
    die "$qemu $qemu_user_static is not executable"

# added programs: eatmydata to speed up APT/dpkg; makedev needs to be
# run very early as we can’t use udev or the host’s /dev filesystem,
# mksh because the post-install script is written in it for simplicity
# ↓ IFS splitting actually required
# shellcheck disable=SC2086
eatmydata debootstrap --arch="$tgarch" --include=eatmydata,makedev,mksh \
    --force-check-gpg $init --verbose --foreign buster "$mpt" \
    http://deb.debian.org/debian sid || die 'debootstrap (first stage) failed'
    # script specified here as it’s normally what buster symlinks to,
    # to achieve compatibility with more host distros
# we need this early; Debian #700633
(
	set -e
	cd "$mpt"
	for archive in var/cache/apt/archives/*eatmydata*.deb; do
		dpkg-deb --fsys-tarfile "$archive" >a
		tar -xkf a
	done
	rm -f a
) || die 'failure extracting eatmydata early'
# the user can delete this later, from the booted system
cp "$qemu_user_static" "$mpt/usr/bin/$qemu" || die 'cp failed'

##################################################
# INSTALL DEBIAN, SECOND STAGE (UNDER EMULATION) #
##################################################

p 'I: second stage bootstrap (under emulation), slooow…'
mount -t tmpfs swap "$mpt/dev/shm" || die 'mount /dev/shm failed'
mount -t proc  proc "$mpt/proc" || die 'mount /proc failed'
mount -t tmpfs swap "$mpt/tmp" || die 'mount /tmp failed'
chroot "$mpt" /usr/bin/env -i LC_ALL=C.UTF-8 HOME=/root PATH="$safe_PATH" \
    TERM="$TERM" /usr/bin/eatmydata /debootstrap/debootstrap --second-stage || \
    die 'debootstrap (second stage) failed'
# debootstrap umounts some; just umount then remount everything
umount "$mpt/tmp" 2>/dev/null
umount "$mpt/proc" 2>/dev/null
umount "$mpt/dev/shm" 2>/dev/null

####################################################################
# CREATE POST-BOOTSTRAP ENVIRONMENT AND ADJUST CONFIGURATION FILES #
####################################################################

p 'I: pre-configuring…'
mount -t tmpfs swap "$mpt/dev/shm" || die 'remount /dev/shm failed'
mount -t proc  proc "$mpt/proc" || die 'remount /proc failed'
mount -t tmpfs swap "$mpt/tmp" || die 'remount /tmp failed'
# extra as needed below
mount --bind /dev/pts "$mpt/dev/pts" || die 'bind-mount /dev/pts failed'

# standard configuration files (generic)
if ynwfalse dropsd; then
	# path apparently varies with init system
	rnd=/var/lib/systemd/random-seed
else
	# traditional path (content is identical though)
	rnd=/var/lib/urandom/random-seed
fi
(
	set -ex
	# as set by d-i
	printf '%s\n' '0.0 0 0.0' 0 UTC >"$mpt/etc/adjtime"
	cat >"$mpt/etc/apt/sources.list" <<-'EOF'
deb http://deb.debian.org/debian buster main non-free contrib
deb http://deb.debian.org/debian-security buster/updates main non-free contrib
deb http://deb.debian.org/debian buster-updates main non-free contrib
deb http://deb.debian.org/debian buster-backports main non-free contrib
	EOF
	# from console-setup (1.193) config/keyboard (d-i)
	cat >"$mpt/etc/default/keyboard" <<-'EOF'
		# KEYBOARD CONFIGURATION FILE

		# Consult the keyboard(5) manual page.

		XKBMODEL=pc105
		XKBLAYOUT=us
		XKBVARIANT=
		XKBOPTIONS=

		BACKSPACE=guess
	EOF
	# avoids early errors, configured properly later
	: >"$mpt/etc/default/locale"
	# target-appropriate
	cat >"$mpt/etc/fstab" <<-'EOF'
LABEL=RASPI_root   /               ext4   defaults,relatime,discard       0  2
LABEL=RASPI_FIRMW  /boot/firmware  vfat   defaults,noatime,discard        0  1
swap               /tmp            tmpfs  defaults,relatime,nosuid,nodev  0  0
	EOF
	if test "$swsize" -gt 0; then cat >>"$mpt/etc/fstab" <<-'EOF'
LABEL=RASPI_swap   swap            swap   sw,discard=once                 0  0
	EOF
	fi
	# hostname and hosts (generic)
	case $myfqdn in
	(*.*)	myhost="$myfqdn ${myfqdn%%.*}" ;;
	(*)	myhost=$myfqdn ;;
	esac
	printf '%s\n' "$myfqdn" >"$mpt/etc/hostname"
	cat >"$mpt/etc/hosts" <<-EOF
		127.0.0.1	$myhost localhost localhost.localdomain

		::1     ip6-localhost ip6-loopback localhost6 localhost6.localdomain6
		fe00::0 ip6-localnet
		ff00::0 ip6-mcastprefix
		ff02::1 ip6-allnodes
		ff02::2 ip6-allrouters
		ff02::3 ip6-allhosts
	EOF
	# like d-i
	rm -f "$mpt/etc/mtab"
	ln -sfT /proc/self/mounts "$mpt/etc/mtab"
	# so the user can ssh in straight after booting
	cat >>"$mpt/etc/network/interfaces" <<-'EOF'

		# The loopback network interface
		auto lo
		iface lo inet loopback

		# First Ethernet interface
		auto eth0
		iface eth0 inet dhcp
	EOF
	# for bootstrapping in chroot
	cat /etc/resolv.conf >"$mpt/etc/resolv.conf"
	# base directory, init system-dependent but identical
	mkdir -p "$mpt${rnd%/*}"
	test -d "$mpt${rnd%/*}"/.
	chown 0:0 "$mpt${rnd%/*}"
	chmod 755 "$mpt${rnd%/*}"
) || die 'pre-configuring failed'

###################################
# CREATE POST-INSTALLATION SCRIPT #
###################################

(
	set -e
	# beginning
	cat <<-'EOF'
		#!/bin/mksh
		set -e
		set -o pipefail
		# reset environment so we can work
		unset LANGUAGE
		export DEBIAN_FRONTEND=teletype HOME=/root LC_ALL=C.UTF-8 \
		    PATH=/usr/sbin:/usr/bin:/sbin:/bin POSIXLY_CORRECT=1
		export SUDO_USER=root USER=root # for etckeeper
		# necessary to avoid leaking the host’s /dev
		print -ru2 -- 'I: the MAKEDEV step is extremely slow…'
		set -x
		(cd /dev && exec MAKEDEV std sd console ttyS0)
		# because this is picked up by packages, e.g. postfix
		hostname "$(</etc/hostname)"
		# sanitise APT state
		apt-get clean
		apt-get update
		# for debconf (required)
		apt-get --purge -y install --no-install-recommends \
		    libterm-readline-gnu-perl
		export DEBIAN_FRONTEND=readline
		# just in case there were security uploads
		apt-get --purge -y dist-upgrade
	EOF
	# switch to sysvinit?
	ynwfalse dropsd || cat <<-'EOF'
		apt-get --purge -y install --no-install-recommends \
		    sysvinit-core systemd-
		printf '%s\n' \
		    'Package: systemd' 'Pin: version *' 'Pin-Priority: -1' '' \
		    >/etc/apt/preferences.d/systemd
		# make it suck slightly less, mostly already in sid
		(: >/etc/init.d/.legacy-bootordering)
		grep FANCYTTY /etc/lsb-base-logging.sh >/dev/null 2>&1 || \
		    echo FANCYTTY=0 >>/etc/lsb-base-logging.sh
	EOF
	# install base packages
	echo "kernel=$kernel qemu=$qemu"
	cat <<-'EOF'
		rm -f /var/cache/apt/archives/*.deb  # save temp space
		# kernel, initrd and base firmware
		apt-get --purge -y install --no-install-recommends \
		    busybox firmware-linux-free \
		    $kernel
		rm -f /var/cache/apt/archives/*.deb  # save temp space
		# some tools and bootloader firmware
		apt-get --purge -y install --no-install-recommends \
		    adduser ed linuxlogo raspi-firmware/buster-backports \
		    sudo whiptail
		rm -f /var/cache/apt/archives/*.deb  # save temp space
		export DEBIAN_FRONTEND=dialog
		# basic configuration
		print -r -- '(. /etc/os-release 2>/dev/null; linux_logo' \
		    '-uy ${PRETTY_NAME+-t "OS version: $PRETTY_NAME"} || :)' \
		    >/etc/profile.d/linux_logo.sh
		# user configuration
		(whiptail --backtitle 'mkrpi3b+img.sh' --msgbox \
		    'We will now reconfigure some packages, so you can set up some basic things about your system: timezone (default UTC), keyboard layout, console font, and the system locale (and possibly whether additional locales are to be installed).

Press Enter to continue.' 12 72 || :)
		dpkg-reconfigure -plow tzdata
		rm -f /etc/default/locale  # force generation
		DEBIAN_PRIORITY=low \
		    apt-get --purge -y install --no-install-recommends \
		    console-{common,data,setup} locales
		# whether the user just hit Enter
		case $(</etc/default/locale) in
		(''|'#  File generated by update-locale')
			# empty, add sensible default (same as update-locale)
			print -r -- 'LANG=C.UTF-8' >>/etc/default/locale
			;;
		esac
	EOF
	# adjust CMA size?
	ynwfalse setcma || cat <<-'EOF'
		ed -s /etc/default/raspi-firmware <<-'EODB'
			,g/^#CMA=64M/s//CMA=128M/
			w
			q
		EODB
	EOF
	# remaining packages and configuration
	cat <<-'EOF'
		ed -s /etc/default/raspi-firmware <<-'EODB'
			,g!^#ROOTPART=/dev/mmcblk0p2!s!!ROOTPART=LABEL=RASPI_root!
			w
			q
		EODB
		/etc/initramfs/post-update.d/z50-raspi-firmware
		: remaining user configuration may error out intermittently
		set +e
		# make man-db faster at cost of no apropos(1) lookup database
		debconf-set-selections <<-'EODB'
			man-db man-db/build-database boolean false
			man-db man-db/auto-update boolean false
		EODB
		: install basic packages  # change at your own risk but ok
		# bullseye/sid += bsdextrautils
		apt-get --purge -y install --no-install-recommends \
		    bc ca-certificates ifupdown iproute2 jupp joe-jupp less \
		    lsb-release lynx man-db mc mlocate molly-guard net-tools \
		    netcat-openbsd openssh-client popularity-contest procps \
		    rsync screen sharutils
		rm -f /var/cache/apt/archives/*.deb  # save temp space
	EOF
	set -o noglob
	# ↓ IFS splitting actually required
	# shellcheck disable=SC2086
	set -- $pkgadd
	set +o noglob
	pkgs=''
	s=''
	for pkg in "$@"; do
		# macro substitution of tools often found together
		case $pkg in
		(_WLAN_) pkg='crda firmware-brcm80211 wireless-tools wpasupplicant' ;;
		esac
		# collect list of packages to install
		pkgs="$pkgs$s$pkg" s=' '
	done
	# list of groups from user-setup (1.81), i.e. d-i,
	# debian/user-setup.templates: passwd/user-default-groups
	set -- audio bluetooth cdrom debian-tor dip floppy lpadmin \
	    netdev plugdev scanner video
	# we add adm and sudo (at least sudo done by d-i as well)
	groups="$* adm sudo"
	cat <<-EOF
		: install extra packages
		apt-get --purge install --no-install-recommends $pkgs
		rm -f /var/cache/apt/archives/*.deb  # save temp space
		: create initial user account, asking for password
		adduser '$userid'
		: ignore errors for nonexisting groups, please
		for group in $groups; do
			adduser '$userid' \$group
		done
		: end of pre-scripted post-bootstrap steps
		set +x
		# prepare for manual steps as desired
		userid='$userid'
	EOF

	##############################################################
	# PERMIT MANUAL STEPS BY SWITCHING (UNDER EMULATION) TO USER #
	##############################################################

	cat <<-'EOF'
		# instruct the user what they can do now
		whiptail --backtitle 'mkrpi3b+img.sh' \
		    --msgbox "We will now (chrooted into the target system, under emulation, so it will be really slooooow…) run a login shell as the user account we just created ($userid), so you can do any manual post-installation steps desired.

Please use “sudo -S command” to run things as root, if necessary.

Press Enter to continue; exit the emulation with the “exit” command." 14 72
		# clean environment for interactive use
		unset DEBIAN_FRONTEND POSIXLY_CORRECT
		export HOME=/  # later overridden by su
		# create an initial entry in syslog
		>>/var/log/syslog print -r -- "$(date +"%b %d %T")" \
		    "${HOSTNAME%%.*} mkrpi3b+img.sh[$$]:" \
		    soliciting manual post-installation steps
		chown 0:adm /var/log/syslog
		chmod 640 /var/log/syslog
		# avoids warnings with sudo, cf. Debian #922349
		find /usr/lib -name libeatmydata.so\* -a -type f -print0 | \
		    xargs -0r chmod u+s --
		(unset SUDO_USER USER; exec su - "$userid")
		# revert the above change again
		find /usr/lib -name libeatmydata.so\* -a -type f -print0 | \
		    xargs -0r chmod u-s --
		# might not do anything, but allow the user refusal
		print -ru2 -- 'I: running apt-get autoremove,' \
		    'acknowledge as desired'
		apt-get --purge autoremove
		# remove installation debris
		print -ru2 -- 'I: finally, cleaning up'
		apt-get clean
		pwck -s
		grpck -s
		rm -f /etc/{passwd,group,{,g}shadow,sub{u,g}id}-
		# record initial /etc state
		if whence -p etckeeper >/dev/null; then
			etckeeper commit 'Finish installation'
			etckeeper vcs gc
		fi
		rm -f /var/log/bootstrap.log
		# from /lib/init/bootclean.sh
		cd /run
		find . ! -xtype d ! -name utmp ! -name innd.pid -delete
		# fine𝄐
		>>/var/log/syslog print -r -- "$(date +"%b %d %T")" \
		    "${HOSTNAME%%.*} mkrpi3b+img.sh[$$]:" \
		    finishing up installation\; once booted natively on the \
		    device, you can nuke /usr/bin/$qemu manually later
	EOF
) >"$mpt/root/munge-it.sh" || die 'post-installation script creation failure'

# now place initial random seed in the target location
mv rnd "$mpt$rnd" || die 'mv rnd failed'
chown 0:0 "$mpt$rnd" || die 'chown rnd failed'
chmod 600 "$mpt$rnd" || die 'chmod rnd failed'
# second half (collected from host’s CSPRNG now)
dd if=/dev/urandom bs=256 count=1 >>"$mpt$rnd" || die 'dd rnd2 failed'

########################################################
# POST-BOOTSTRAP SCRIPT RUN IN CHROOT, UNDER EMULATION #
########################################################

# run the script concatenated together above in the chroot
unshare --uts chroot "$mpt" /usr/bin/env -i TERM="$TERM" /usr/bin/eatmydata \
    /bin/mksh /root/munge-it.sh || die 'post-bootstrap failed'
# remove the oneshot script
rm -f "$mpt/root/munge-it.sh"

#######################
# FINISH AND CLEAN UP #
#######################

w --infobox 'OK. We will now clean up the target system.' 7 72

# to minimise size of backing sparse image file (also good for SSD)
fstrim -v "$mpt/boot/firmware"
fstrim -v "$mpt"
# add another couple of random bytes, so the first boot isn’t without
dd if=/dev/urandom bs=64 count=1 conv=notrunc of="$mpt$rnd" || \
    p 'W: dd rnd3 failed'
# that’s it
p "I: done installing on $dvname ($tgtimg), cleaning up…"
diecleanup
set +x
trap - EXIT
# Debian #801614
p 'W: when installing X11, you’ll need these extra steps:' \
    'N: 1. install the package xserver-xorg-legacy' \
    'N: 2. add to /etc/X11/Xwrapper.config the line:' \
    'N:     needs_root_rights=yes'
p 'I: installation finished successfully'
exit 0
