#!/bin/sh
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
# Installs a Raspberry Pi 3B+ image from scratch (tested on a Debian
# bullseye/sid host system, others should work as well given suitab‐
# ly up-to-date tools), using qemu-user/binfmt_misc emulation to run
# the foreign architecture steps in a chroot.

#########
# SETUP #
#########

LANGUAGE=C
LC_ALL=C.UTF-8
export LC_ALL
unset LANGUAGE
ht='	'
nl='
'
IFS=" $ht$nl"
POSIXLY_CORRECT=1
export POSIXLY_CORRECT
safe_PATH=/bin:/sbin:/usr/bin:/usr/sbin
PATH=$PATH:$safe_PATH  # just to make sure
export safe_PATH PATH

needprintf=
if test -n "$KSH_VERSION"; then
	p() {
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
dieif() {
	dieif_reason=$1; shift
	"$@" || die "$dieif_reason"
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

rv=0
chkhosttool() {
	chkhosttool_prog=$1; shift
	chkhosttool_missing=0
	while test $# -gt 0; do
		test -x "$1" || {
			test $chkhosttool_missing = 1 || \
			    p "E: please install $chkhosttool_prog to continue!"
			chkhosttool_missing=1
			p "N: missing: $1"
		}
		shift
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
chkhosttool qemu-user-static /usr/bin/qemu-aarch64-static
chkhosttool util-linux /bin/lsblk /sbin/fstrim /usr/bin/unshare
chkhosttool whiptail /usr/bin/whiptail
unset chkhosttool_prog
unset chkhosttool_missing
test x"$rv" = x"0" || exit "$rv"
if test -n "$needprintf"; then
	p() {
		printf '%s\n' "$@" >&2
	}
	unset p_arg
fi
unset needprintf

case $(id -u) in
(0) ;;
(*) die 'Please run this as root.' ;;
esac

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

# assign tgtvar fallback glob
assign() {
	assign_tgt=$1; shift
	assign_nil=$1; shift
	eval "$assign_tgt=\$assign_nil"
	test -n "$1" && test -e "$1" || return 0
	eval "$assign_tgt=\$*"
}

w() {
	whiptail --backtitle 'mkrpi3b+img.sh' --output-fd 4 4>res "$@"
	rv=$?
	res=$(cat res) || die cannot read whiptail result file
	return $rv
}
dw() {
	if w "$@"; then
		s=$(($s+1))
	elif test x"$s" = x"0"; then
		p '' 'I: aborted by user'
		diecleanup
		exit $rv
	else
		s=$(($s-1))
	fi
	return $rv
}

################################
# ENSURE MINIMUM TERMINAL SIZE #
################################

s=0
while test x"$s" != x"9"; do
	set -- $(stty size) || die 'stty failed'
	test $# -eq 2 || die 'stty weird output' "$@"
	case "$*" in
	(*[!\ 0-9]*) die 'stty invalid output' "$@" ;;
	esac
	case $s in
	(0)
		#### INITIAL TERMINAL SIZE CHECK
		s=4
		test $1 -ge 24 || s=1
		test $2 -ge 80 || s=1
		;;
	(1)
		#### TTY TOO SMALL REQUEST CHANGE
		p 'E: tty size too small' \
		  "N: ${2}x$1 actual" "N: 80x24 minimum"
		sleep 5
		s=2
		;;
	(2)
		#### SEE WHETHER THAT HELPED
		s=4
		test $1 -ge 24 || s=3
		test $2 -ge 80 || s=3
		;;
	(3)
		#### STILL REQUEST CHANGE
		w --title 'Terminal size' --msgbox \
		    "Your terminal is too small (only ${2}x$1 glyphs).

Please resize your terminal to at least 80x24 now, then press Enter to continue. Afterwards, DO *NOT* change the terminal size again! APT and debconf really do not like that, and your display will be garbled if you do…

Change size now, press Enter only afterwards to continue." 14 72
		s=5
		;;
	(4)
		#### INITIAL TTY SIZE OK
		w --title 'Terminal size' --msgbox \
		    "Your terminal size is okay: ${2}x$1 glyphs, minimum 80x24 required.

Please DO *NOT* change the terminal size for the entire runtime of this script, starting now! APT and debconf really do not like that, and your display will be garbled if you do…

Press Enter to continue." 14 72
		s=5
		;;
	(5)
		#### SEE THAT WE END UP AT CORRECT SIZE
		s=9
		test $1 -ge 24 || s=6
		test $2 -ge 80 || s=6
		;;
	(6)
		#### NOT GOOD ENOUGH
		if w --title 'Terminal size' --yes-button OK --no-button Exit \
		    --yesno "Your terminal still is too small (${2}x$1).

We requested you to change it to at least 80x24 (and keep the size constant afterwards). Please do so now, or press Escape or use the Exit button if you really can’t.

Remember to *NOT* change the size afterwards, since APT and debconf cache it and do not like sudden changes below them; if you do, your display will be garbled…

Change size now, press Enter only afterwards to continue." 17 72; then
			s=5
		else
			p '' 'I: aborted by user'
			exit 0
		fi
		;;
	esac
done

#################
# DIALOGUE LOOP #
#################

assign devices '' /dev/sd[a-z]
tgtdev=MANUAL
tgtimg=/dev/sdX
myfqdn=rpi3bplus.lan.tarent.invalid
userid=pi
setcma=
dropsd=--defaultno
pkgadd=-
s=0
while test x"$s" != x"9"; do
	case $s in
	(0)
		#### WHICH TARGET DEVICE? (CHOICE)
		set --
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
				s=$(($s+1))
			fi
		fi
		;;
	(1)
		#### WHICH TARGET DEVICE OR IMAGE? (FREETEXT)
		if dw --title 'Choose target device' \
		    --inputbox 'Enter path to target raw device (e.g. /dev/sdX) or to pre-existing, already correctly-sized, image file to use:' \
		    20 72 "$tgtimg"; then
			tgtimg=$res
		fi
		;;
	(2)
		#### VALIDATE IMAGE/DEVICE PATH/SIZE/ETC. / CREATE SPARSE FILE
		# step to go back to if things fail
		if test x"$tgtdev" = x"MANUAL"; then
			s=1
		else
			s=0
		fi
		# check image/device: path, existence, not a symlink (for stability)
		case $tgtimg in
		(/[!/]*) ;;
		(*)
			w --msgbox 'The chosen device/image path is not an absolute pathname!' 8 72
			continue ;;
		esac
		test -e "$tgtimg" || if w --title 'Nonexistent path chosen' \
		    --ok-button 'Create' --cancel-button 'Go back' \
		    --inputbox 'The chosen device/image path does not exist!

If you wish to create it, enter a size in the format accepted by GNU coreutils’ truncate(1) utility (that is, a number followed by M for MiB or G for GiB, in its most basic form) and select the “Create” button (or just press Enter). This will create a sparse image file (which will only take up the space actually used by data). We have pre-filled the input field with the minimum allowed image size.

The image will be created *immediately* and never deleted!

If you do not with to create it, press Escape to go back instead.' \
		    20 72 1536M; then
			truncate -s "$res" "$tgtimg" || \
			    die 'failed to create sparse file'
			test -e "$tgtimg" || die 'sparse file not created'
		else
			continue  # go back
		fi
		if test -h "$tgtimg"; then
			tgtimg=$(readlink -f "$tgtimg") || die 'error in readlink -f'
			s=2 # redo from start
			continue
		fi
		# whether block device, regular file or grounds for refusal
		if test -b "$tgtimg"; then
			dvname=$tgtimg
		elif test -f "$tgtimg"; then
			dvname=$(losetup -f) || die 'losetup failed in get'
			case $dvname in
			(/dev/loop*) ;;
			(*) die 'losetup shows weird result' "$dvname" ;;
			esac
			loopdev=$dvname
			losetup "$loopdev" "$tgtimg" || die 'losetup failed in set'
		else
			w --msgbox 'The chosen device/image path is neither a block special device nor a regular file!' 8 72
			continue
		fi
		# we now have a block (or loopback device) we can check
		sz=$(lsblk --nodeps --noheadings --output SIZE --bytes \
		    --raw "$dvname") || die 'lsblk failed'
		case $sz in
		(*[!0-9]*) die 'lsblk shows weird result' "$sz" ;;
		([0-9]*) ;;
		(*) die 'lsblk returned empty result' ;;
		esac
		case $(echo "a=0; if($sz<(1536*1048576)) a=1; a" | bc) in
		(0) ;;
		(1)
			w --msgbox 'The chosen device/image path is smaller than 1536 MiB!' 8 72
			dieteardown
			continue ;;
		(*) die 'bc returned weird result' ;;
		esac
		# and it’s big enough for the Debian installation; accept
		s=2
		sz=$(echo "scale=2; $sz/1048576" | bc) || die 'bc cannot divide'
		dw --title 'Accept target device' \
		    --yesno "Your chosen target device: $tgtimg

Block device $dvname of size $sz MiB

Do you REALLY want to use this as target device
and OVERWRITE ALL DATA with no chance of recovery?" 14 72
		;;
	(3)
		#### HOSTNAME FOR THE SYSTEM
		if dw --title 'Enter target hostname' \
		    --inputbox 'Enter fully-qualified hostname the target device should have:' \
		    20 72 "$myfqdn"; then
			# one trailing full stop is allowed (like DNS)
			myfqdn=${res%.}
			# check length [1; 255]
			if test "${#myfqdn}" -lt 1; then
				w --msgbox 'The given hostname is empty!' 8 72
				s=3; continue  # retry
			fi
			if test "${#myfqdn}" -gt 255; then
				w --msgbox 'The given hostname is too long!' 8 72
				s=3; continue  # retry
			fi
			# check characters used
			case $myfqdn in
			(.*|*.)
				w --msgbox 'The given hostname begins or ends with a full stop!' 8 72
				s=3; continue ;;
			(*[!.0-9A-Za-z-]*)
				w --msgbox 'The given hostname contains invalid characters!' 8 72
				s=3; continue ;;
			esac
			# similar for the component labels
			IFS=.; set -o noglob
			set -- $myfqdn
			IFS=" $ht$nl"; set +o noglob
			for x in "$@"; do
				if test "${#x}" -lt 1 || test "${#x}" -gt 63; then
					w --msgbox 'The given hostname contains parts that are empty or too long!' 8 72
					s=3; break
				fi
				# invalid label composition
				case $x in
				(-*)
					w --msgbox 'The given hostname contains parts that begin with a hyphen-minus!' 8 72
					s=3; break ;;
				(*-)
					w --msgbox 'The given hostname contains parts that end with a hyphen-minus!' 8 72
					s=3; break ;;
				(*[!0-9A-Za-z-]*)
					w --msgbox 'The given hostname contains invalid characters!' 8 72
					s=3; break ;;
				esac
			done
			# s is now 3=redo (msgbox shown) or 4=go on
		fi
		;;
	(4)
		#### USERNAME TO CREATE FOR INITIAL SSH AND SUDO
		if dw --title 'Enter initial username' \
		    --inputbox 'Enter UNIX username of the initially created user (which has full sudo access):' \
		    20 72 "$userid"; then
			userid=$res
			# Unix limitations
			if test -z "$userid"; then
				w --msgbox 'The given username is empty!' 8 72
				s=4; continue  # retry
			fi
			if test "${#userid}" -gt 32; then
				w --msgbox 'The given username is too long! (32 bytes max.)' 8 72
				s=4; continue  # retry
			fi
			# default /etc/adduser.conf NAME_REGEX
			case $userid in
			(*[!a-z0-9_-]*)
				w --msgbox 'The given username contains invalid characters!' 8 72
				s=4; continue ;;
			([!a-z]*)
				w --msgbox 'The given username does not start with a letter!' 8 72
				s=4; continue ;;
			esac
		fi
		;;
	(5)
		#### ADJUST DEFAULT CMA SIZE?
		if w --title 'Default CMA size' \
		    $setcma --yesno "Raise default CMA from 64 to 128 MiB?

This is especially useful when you’ll be using graphics." 10 72; then
			setcma=
			s=6
		elif test x"$rv" = x"1"; then
			setcma=--defaultno
			s=6
		else
			s=4
		fi
		;;
	(6)
		#### SELECT INIT SYSTEM
		if w --title 'Choose the init system' \
		    $dropsd --yesno "Change init system from systemd to sysvinit?

The default init system in Debian 10 “buster” is systemd with usrmerge.
This option allows you to change to traditional SysV init with classic
filesystem layout.

Most users will say “No” here." 10 72; then
			dropsd=
			s=7
		elif test x"$rv" = x"1"; then
			dropsd=--defaultno
			s=7
		else
			s=5
		fi
		;;
	(7)
		#### EXTRA PACKAGES TO INSTALL
		if test x"$pkgadd" = x"-"; then
			pkgadd='bind9-host bridge-utils postfix bsd-mailx curl etckeeper ethtool openssh-server patch pv reportbug unscd wget _WLAN_'
			blurb=' We have provided you with a selection of default useful system utilities and services, which you can change if you wish, of course.'
		else
			blurb=
		fi
		if dw --title 'Extra packages to install' \
		    --inputbox "Enter extra packages to install, separated by space.$blurb Some other extra packages, like less and sudo, are always installed.

You can use _WLAN_ to select packages needed to support WiFi. Press ^U (Ctrl-U) to delete the entire line; enter just - to restore the default and edit anew." \
		    20 72 "$pkgadd"; then
			pkgadd=$res
			test x"$pkgadd" = x"-" && s=7
		fi
		;;
	(8)
		#### SUMMARY BEFORE DOING ANYTHING (except sparse file creation)
		if test -n "$setcma"; then cma=64; else cma=128; fi
		if test -n "$dropsd"; then
			init='systemd with usrmerge'
		else
			init='sysvinit with standard filesystem'
		fi
		dw --title 'Proceed with installation?' --defaultno \
		    --yesno "Do you wish to proceed and DELETE ALL DATA from the target device? (Choosing “No” or pressing Escape allows you to go back to each individual step for changing the information.) Summary of settings:

Target  : $tgtimg
Hostname: $myfqdn
Username: $userid
CMA size: $cma MiB
init/FHS: $init

Packages: $pkgadd" 20 72
		;;
	esac
done

##########################
# PREPARE DISC STRUCTURE #
##########################

p 'I: ok, proceeding; this may take some time…' \
  'N: be prepared to interactively answer more questions though'
sleep 3
# store some random seed for later, 1ˢᵗ half
dd if=/dev/urandom bs=256 count=1 of=rnd 2>/dev/null || die 'dd rnd1 failed'
# create MBR with empty BIOS partition table
s='This SD card boots on a Raspberry Pi 3B+ only!'
printf '\xE8\x'$(echo "obase=16; ${#s}+5" | bc)'\0\r\n' >data
printf '%s' 'This SD card boots on a Raspberry Pi 3B+ only!' | tee txt >>data
printf '\r\n\0\x5E\16\x1F\xAC\10\xC0\x74\xFE\xB4\16\xBB\7\0\xCD\20\xEB\xF2' \
    >>data
dd if=/dev/zero bs=16 count=4 of=pt 2>/dev/null || die 'dd mbr1 failed'
printf '\x55\xAA' >>pt
# cobble together wiping partition first MiB “en passant”
dd if=/dev/urandom bs=256 count=4096 of=mbr 2>/dev/null || die 'dd mbr2 failed'
dd if=mbr bs=1048576 of="$dvname" seek=1 2>/dev/null || die 'dd clr1 failed'
dd if=mbr bs=1048576 of="$dvname" seek=128 2>/dev/null || die 'dd clr2 failed'
dd if=data of=mbr conv=notrunc 2>/dev/null || die 'dd mbr3 failed'
dd if=pt of=mbr bs=1 seek=446 conv=notrunc 2>/dev/null || die 'dd mbr4 failed'
dd if=mbr bs=1048576 of="$dvname" 2>/dev/null || die 'dd mbr5 failed'
rm mbr
# create partitions
dieif 'fdisk failed' \
    fdisk -c=nondos -t MBR -w always -W always "$tgtimg" <<'EOF'
n
p
1
2048
262143
n
p
2
262144

t
1
c
w
EOF
kpx=/dev/mapper/${dvname##*/}
kpartx -a -f -v -p p -t dos -s "$dvname" || die 'kpartx failed'
# create filesystems
eatmydata mkfs.msdos -f 1 -F 32 -m txt -n RPi3BpFirmw -v "${kpx}p1" || \
    die 'mkfs.msdos failed'
eatmydata mkfs.ext4 -e remount-ro -E discard -L RasPi3B+root \
    -O sparse_super2 -U random "${kpx}p2" || die 'mkfs.ext4 failed'
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
if test -n "$dropsd"; then
	init=
else
	init=--no-merged-usr
fi
eatmydata debootstrap --arch=arm64 --include=eatmydata,makedev,mksh $init \
    --force-check-gpg --verbose --foreign buster "$mpt" \
    http://deb.debian.org/debian sid || die 'debootstrap (first stage) failed'
    # script specified here as it’s normally what buster symlinks to,
    # to achieve compatibility with more host distros
# we need this early
(
	set -e
	cd "$mpt"
	for archive in var/cache/apt/archives/*eatmydata*.deb; do
		dpkg-deb --fsys-tarfile "$archive" >a
		tar -xkf a
	done
	rm -f a
) || die 'failure extracting eatmydata early'
# the user can delete this later, from the booted system (or apt will)
cp /usr/bin/qemu-aarch64-static "$mpt/usr/bin/" || die 'cp failed'

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
if test -n "$dropsd"; then
	rnd=/var/lib/systemd/random-seed
else
	rnd=/var/lib/urandom/random-seed
fi
(
	set -ex
	printf '%s\n' '0.0 0 0.0' 0 UTC >"$mpt/etc/adjtime"
	cat >"$mpt/etc/apt/sources.list" <<-'EOF'
deb http://deb.debian.org/debian buster main non-free contrib
deb http://deb.debian.org/debian-security buster/updates main non-free contrib
deb http://deb.debian.org/debian buster-updates main non-free contrib
deb http://deb.debian.org/debian buster-backports main non-free contrib
	EOF
	# from console-setup (1.193) config/keyboard
	cat >"$mpt/etc/default/keyboard" <<-'EOF'
		# KEYBOARD CONFIGURATION FILE

		# Consult the keyboard(5) manual page.

		XKBMODEL=pc105
		XKBLAYOUT=us
		XKBVARIANT=
		XKBOPTIONS=

		BACKSPACE=guess
	EOF
	: >"$mpt/etc/default/locale"
	cat >"$mpt/etc/fstab" <<-'EOF'
LABEL=RasPi3B+root  /               ext4   defaults,relatime,discard       0  2
LABEL=RPi3BpFirmw   /boot/firmware  vfat   defaults,noatime,discard        0  1
swap                /tmp            tmpfs  defaults,relatime,nosuid,nodev  0  0
	EOF
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
	rm -f "$mpt/etc/mtab"
	ln -sfT /proc/self/mounts "$mpt/etc/mtab"
	cat >>"$mpt/etc/network/interfaces" <<-'EOF'

		# The loopback network interface
		auto lo
		iface lo inet loopback
	EOF
	# for bootstrapping in chroot
	cat /etc/resolv.conf >"$mpt/etc/resolv.conf"
	# base directory, init system-dependent
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
		unset LANGUAGE
		export DEBIAN_FRONTEND=teletype HOME=/root LC_ALL=C.UTF-8 \
		    PATH=/usr/sbin:/usr/bin:/sbin:/bin POSIXLY_CORRECT=1
		print -ru2 -- 'I: the MAKEDEV step is extremely slow…'
		set -x
		(cd /dev && exec MAKEDEV std sd console ttyS0)
		hostname "$(</etc/hostname)"
		apt-get clean
		apt-get update
		# for debconf (required)
		apt-get --purge -y install --no-install-recommends \
		    libterm-readline-gnu-perl
		export DEBIAN_FRONTEND=readline
		# just in case
		apt-get --purge -y dist-upgrade
	EOF
	# switch to sysvinit?
	test -n "$dropsd" || cat <<-'EOF'
		apt-get --purge -y install --no-install-recommends \
		    sysvinit-core systemd-
		printf '%s\n' \
		    'Package: systemd' 'Pin: version *' 'Pin-Priority: -1' '' \
		    >/etc/apt/preferences.d/systemd
	EOF
	# install base packages
	cat <<-'EOF'
		rm -f /var/cache/apt/archives/*.deb
		apt-get --purge -y install --no-install-recommends \
		    busybox firmware-brcm80211 firmware-linux-free \
		    linux-image-arm64
		rm -f /var/cache/apt/archives/*.deb
		apt-get --purge -y install --no-install-recommends \
		    adduser ed linuxlogo raspi3-firmware whiptail
		rm -f /var/cache/apt/archives/*.deb
		export DEBIAN_FRONTEND=dialog
		# basic configuration
		print -r -- linux_logo -uy >/etc/profile.d/linux_logo.sh
		(whiptail --backtitle 'mkrpi3b+img.sh' --msgbox \
		    'We will now reconfigure some packages, so you can set up some basic things about your system: timezone (default UTC), keyboard layout, console font, and the system locale (and possibly whether additional locales are to be installed).

Press Enter to continue.' 12 72 || :)
		dpkg-reconfigure -plow tzdata
		rm -f /etc/default/locale  # force generation
		DEBIAN_PRIORITY=low \
		    apt-get --purge -y install --no-install-recommends \
		    console-{common,data,setup} locales
	EOF
	# adjust CMA size?
	test -n "$setcma" || cat <<-'EOF'
		ed -s /etc/default/raspi3-firmware <<-'EODB'
			,g/^#CMA=64M/s//CMA=128M/
			w
			q
		EODB
		/etc/initramfs/post-update.d/z50-raspi3-firmware
	EOF
	# remaining packages and configuration
	cat <<-'EOF'
		: remaining user configuration may error out
		set +e
		# make man-db faster at cost of no apropos(1) lookup database
		debconf-set-selections <<-'EODB'
			man-db man-db/build-database boolean false
			man-db man-db/auto-update boolean false
		EODB
		: install basic packages
		apt-get --purge -y install --no-install-recommends \
		    bc ca-certificates ifupdown iproute2 jupp joe-jupp less \
		    lsb-release lynx man-db mc mlocate molly-guard net-tools \
		    netcat-openbsd openssh-client popularity-contest procps \
		    rsync screen sharutils sudo
		rm -f /var/cache/apt/archives/*.deb
	EOF
	set -o noglob
	set -- $pkgadd
	set +o noglob
	pkgs= s=
	for pkg in "$@"; do
		case $pkg in
		(_WLAN_) pkg='crda wireless-tools wpasupplicant' ;;
		esac
		pkgs="$pkgs$s$pkg" s=' '
	done
	# list of groups from user-setup (1.81)
	# debian/user-setup.templates: passwd/user-default-groups
	set -- audio bluetooth cdrom debian-tor dip floppy lpadmin \
	    netdev plugdev scanner video
	# we add adm and sudo
	groups="$* adm sudo"
	cat <<-EOF
		: install extra packages
		apt-get --purge install --no-install-recommends $pkgs
		rm -f /var/cache/apt/archives/*.deb
		: create initial user account, do remember password set
		adduser '$userid'
		: ignore errors for nonexisting groups, please
		for group in $groups; do
			adduser '$userid' \$group
		done
		: end of pre-scripted post-bootstrap steps
	EOF
) >"$mpt/root/munge-it.sh" || die 'post-installation script creation failure'

# now place initial random seed
mv rnd "$mpt$rnd" || die 'mv rnd failed'
chown 0:0 "$mpt$rnd" || die 'chown rnd failed'
chmod 600 "$mpt$rnd" || die 'chmod rnd failed'
dd if=/dev/urandom bs=256 count=1 >>"$mpt$rnd" || die 'dd rnd2 failed'

########################################################
# POST-BOOTSTRAP SCRIPT RUN IN CHROOT, UNDER EMULATION #
########################################################

unshare --uts chroot "$mpt" /usr/bin/env -i TERM="$TERM" /usr/bin/eatmydata \
    /bin/mksh /root/munge-it.sh || die 'post-bootstrap failed'
rm -f "$mpt/root/munge-it.sh"

##############################################################
# PERMIT MANUAL STEPS BY CHROOTING (UNDER EMULATION) TO USER #
##############################################################

w --msgbox "We will now chroot into the target system (under emulation, so it will be really slooooow…) as the user account we just created ($userid), so you can do any manual post-installation steps desired.

Please use “sudo -S command” to run things as root, if necessary.

Press Enter to continue; exit the emulation with the “exit” command." 14 72
unshare --uts chroot "$mpt" /usr/bin/env -i TERM="$TERM" /usr/bin/eatmydata \
    /bin/mksh -c '
	unset LANGUAGE
	export HOME=/ LC_ALL=C.UTF-8 PATH=/usr/sbin:/usr/bin:/sbin:/bin
	export HOSTNAME=$(</etc/hostname)
	hostname "$HOSTNAME"
	print -r -- "$(date +"%b %d %T") ${HOSTNAME%%.*} mkrpi3b+img.sh[$$]:" \
	    soliciting manual post-installation steps >>/var/log/syslog
	chown 0:adm /var/log/syslog
	chmod 640 /var/log/syslog
	find /usr/lib -name libeatmydata.so\* -a -type f -print0 | \
	    xargs -0r chmod u+s --
	su - '"$userid"'
	find /usr/lib -name libeatmydata.so\* -a -type f -print0 | \
	    xargs -0r chmod u-s --
	apt-get clean
	print -r -- "$(date +"%b %d %T") ${HOSTNAME%%.*} mkrpi3b+img.sh[$$]:" \
	    finishing up installation, nuke /usr/bin/qemu-aarch64-static \
	    manually later, once booted up natively >>/var/log/syslog
'

#######################
# FINISH AND CLEAN UP #
#######################

w --infobox 'OK. We will now clean up the system.' 7 72

fstrim -v "$mpt/boot/firmware"
fstrim -v "$mpt"
dd if=/dev/urandom bs=64 count=1 conv=notrunc of="$mpt$rnd" || \
    p 'W: dd rnd3 failed'
p "I: done installing on $dvname ($tgtimg)"
# remaining cleanup and unwinding done in the EXIT trap
exit 0
