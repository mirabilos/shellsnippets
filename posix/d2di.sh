#!/bin/sh
echo do not call, wip
exit 255
#-
# Copyright © 2020, 2021
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
# Converts the result of debootstrap into something that d-i (Debian
# Installer) would have produced.

LANGUAGE=C
LC_ALL=C
export LC_ALL

die() {
	echo >&2 "E: ${0##*/}: $*"
	exit 1
}

getslist() {
	case $relse in
	(buster) cat <<-'EOF'
deb http://deb.debian.org/debian/ buster main non-free contrib
deb http://deb.debian.org/debian-security/ buster/updates main non-free contrib
deb http://deb.debian.org/debian/ buster-updates main non-free contrib
deb http://deb.debian.org/debian/ buster-backports main non-free contrib
#deb http://deb.debian.org/debian/ buster-backports-sloppy main non-free contrib
		EOF
		;;
	(bullseye) cat <<-'EOF'
deb http://deb.debian.org/debian/ bullseye main non-free contrib
deb http://deb.debian.org/debian-security/ bullseye-security main non-free contrib
deb http://deb.debian.org/debian/ bullseye-updates main non-free contrib
deb http://deb.debian.org/debian/ bullseye-backports main non-free contrib
#deb http://deb.debian.org/debian/ bullseye-backports-sloppy main non-free contrib
		EOF
		;;
	(bookworm) cat <<-'EOF'
deb http://deb.debian.org/debian/ bookworm main non-free contrib
deb http://deb.debian.org/debian-security/ bookworm-security main non-free contrib
deb http://deb.debian.org/debian/ bookworm-updates main non-free contrib
#deb http://deb.debian.org/debian/ bookworm-backports main non-free contrib
#deb http://deb.debian.org/debian/ bookworm-backports-sloppy main non-free contrib
		EOF
		;;
	(testing) cat <<-'EOF'
deb http://deb.debian.org/debian/ testing main non-free contrib
deb http://deb.debian.org/debian-security/ testing-security main non-free contrib
deb http://deb.debian.org/debian/ testing-updates main non-free contrib
		EOF
		;;
	(sid) cat <<-'EOF'
deb http://deb.debian.org/debian/ sid main non-free contrib
		EOF
		;;
	(dpo) cat <<-'EOF'
deb http://deb.debian.org/debian-ports/ unstable main
deb http://deb.debian.org/debian-ports/ unreleased main
		EOF
		;;
	(*)
		die unknown release
		;;
	esac
}

defpkgs='bc etckeeper ifupdown iproute2 jupp lynx mc molly-guard net-tools netcat-openbsd openssh-client openssh-server rsync screen sharutils'
usage() {
	cat >&2 <<EOF
Usage:	${0##*/} -I initsystem [-k kernelpackage] -n hostname [-P pkgs]
	[-p prio] -r release [-u user] /path/to/chroot
N: initsystem = systemd or sysv | release e.g. bullseye or sid
N: default kernelpackage: linux-image-\$dpkgarch
N: default pkgs: $defpkgs
N: prio for debconf [low|medium|high|critical]
N: without -u no admin user is created (not recommended)
EOF
	exit ${1:-1}
}

isys=
kpkg='linux-image-@'
hostn=
xpkgs=
setp=no
relse=
mkuser=
while getopts "hI:k:n:P:p:r:u:" ch; do
	case $ch in
	(h) usage 0 ;;
	(I) isys=$OPTARG ;;
	(k) kpkg=$OPTARG ;;
	(n) hostn=$OPTARG ;;
	(P) xpkgs=$OPTARG ;;
	(p) setp=$OPTARG ;;
	(r) relse=$OPTARG ;;
	(u) mkuser=$OPTARG ;;
	(*) usage ;;
	esac
done
shift $(($OPTIND - 1))
case $isys in
# file-rc or openrc could, runit could, etc.
(systemd|sysv) ;;
(*) usage ;;
esac
case x$hostn in
(x.*|*.) usage ;;
(x-*|*-) usage ;;
(*[!A-Za-z0-9.-]*) usage ;;
(x) usage ;;
esac
case $setp in
(no|low|medium|high|critical) ;;
(*) usage ;;
esac
getslist >/dev/null # to check $relse validity

mp=$1
case $mp in
(///*) ;;
(//*) mp= ;;
(/*) ;;
(*) mp= ;;
esac
test -n "$mp" || usage

cd "$(dirname "$0")" || die cannot go to script directory
test -s debchroot.sh || die debchroot.sh missing in script directory
debchroot_embed=1
. ./debchroot.sh

debchroot__quiet=1
debchroot_start -P "$mp" -s dev || die could not initialise chroot
debchroot__quiet=
die() {
	echo >&2 "E: ${0##*/}: $*"
	test -z "$mp" || debchroot_stop -P "$mp"
	exit 1
}

debchroot_umtree "$mp/dev" || die something was sitting below chroot/dev/
chroot "$mp" /bin/sh -c '
	(cd /dev && exec MAKEDEV std consoleonly ttyS0)
    ' || die could not create initial device nodes
debchroot__quiet=1
debchroot_start -P "$mp" || die could not reload chroot
debchroot__quiet=

(
	set -e
	# beginning
	cat <<-'EOS'
		#!/bin/sh
		eval '(set -o pipefail)' >/dev/null 2>&1 && set -o pipefail || :
		set -e
		# reset environment so we can work
		DEBIAN_FRONTEND=teletype HOME=/root LANGUAGE=C LC_ALL=C
		PATH=/usr/sbin:/usr/bin:/sbin:/bin
		export DEBIAN_FRONTEND HOME LC_ALL PATH
		unset LANGUAGE
		cd /
		# for etckeeper
		SUDO_USER=root USER=root
		export SUDO_USER USER
		# go on
	EOS
	for k in isys kpkg hostn xpkgs setp relse mkuser; do
		eval "v=\$$k"
		echo "$k=$(debchroot__q "$v")"
	done
	cat <<-'EOS'
		case $isys in
		(systemd)
			rnd=/var/lib/systemd/random-seed ;;
		(*)
			rnd=/var/lib/urandom/random-seed ;;
		esac
		case $setp in
		(no) unset DEBIAN_PRIORITY ;;
		(*) DEBIAN_PRIORITY=$setp; export DEBIAN_PRIORITY ;;
		esac
		set -x
		# as set by d-i
		printf '%s\n' '0.0 0 0.0' 0 UTC >/etc/adjtime
		cat >/etc/apt/sources.list <<\EOF
	EOS
	getslist
	cat <<-'EOS'
		EOF
		# from console-setup (1.193) config/keyboard (d-i)
		cat >/etc/default/keyboard <<-'EOF'
			# KEYBOARD CONFIGURATION FILE

			# Consult the keyboard(5) manual page.

			XKBMODEL=pc105
			XKBLAYOUT=us
			XKBVARIANT=
			XKBOPTIONS=

			BACKSPACE=guess
		EOF
		# avoids early errors, configured properly later
		:>/etc/default/locale
#XXX TODO /etc/fstab
		# because this is picked up by packages, e.g. postfix
		HOSTNAME=$hostn
		hostname "$HOSTNAME"
		case $HOSTNAME in
		(*.*)	hostn="$HOSTNAME ${HOSTNAME%%.*}" ;;
		esac
		printf '%s\n' "$HOSTNAME" >/etc/hostname
		cat >/etc/hosts <<-EOF
			127.0.0.1	$hostn localhost localhost.localdomain

			::1     ip6-localhost ip6-loopback localhost6 localhost6.localdomain6
			fe00::0 ip6-localnet
			ff00::0 ip6-mcastprefix
			ff02::1 ip6-allnodes
			ff02::2 ip6-allrouters
			ff02::3 ip6-allhosts
		EOF
		# like d-i
		rm -f /etc/mtab
		ln -sfT /proc/self/mounts /etc/mtab
		cat >>/etc/network/interfaces <<-'EOF'

			# The loopback network interface
			auto lo
			iface lo inet loopback
		EOF
		# for bootstrapping in chroot
		base64 -d >/etc/resolv.conf <<'_/'
	EOS
	base64 </etc/resolv.conf
	cat <<-'EOS'
		_/
		# init system-dependent path
		mkdir -p "${rnd%/*}"
		test -d "${rnd%/*}"/.
		dd if=/dev/urandom bs=256 count=1 conv=notrunc of="$rnd"
		chown 0:0 "${rnd%/*}" "$rnd"
		chmod 755 "${rnd%/*}"
		chmod 600 "$rnd"
		# sanitise APT state
		apt-get clean
		apt-get update
		# for debconf (required) and speed
		apt-get --purge -y install --no-install-recommends \
		    eatmydata libterm-readline-gnu-perl
		DEBIAN_FRONTEND=readline
		# switch to sysvinit?
		test x"$isys" = systemd || {
			eatmydata apt-get --purge -y install --no-install-recommends \
			    sysv-rc sysvinit-core systemd-
			printf '%s\n' \
			    'Package: systemd' 'Pin: version *' 'Pin-Priority: -1' '' \
			    >/etc/apt/preferences.d/systemd
			# make it suck slightly less, mostly already in sid
			(: >/etc/init.d/.legacy-bootordering)
			grep FANCYTTY /etc/lsb-base-logging.sh >/dev/null 2>&1 || \
			    echo FANCYTTY=0 >>/etc/lsb-base-logging.sh
		}
		eatmydata apt-get --purge -y install --no-install-recommends \
		    whiptail
		DEBIAN_FRONTEND=dialog
		rm -f /var/cache/apt/archives/*.deb  # save temp space
		# just in case there were security uploads
		eatmydata apt-get --purge -y dist-upgrade
		rm -f /var/cache/apt/archives/*.deb  # save temp space
		# kernel, initrd and base firmware
		case $kpkg in
		(*'@'*)
			kpkg=$(printf '%s\n' "$kpkg" | sed \
			    "s/@/$(dpkg --print-architecture)/g") ;;
		esac
		eatmydata apt-get --purge -y install --no-install-recommends \
		    busybox firmware-linux-free $kpkg
		rm -f /var/cache/apt/archives/*.deb  # save temp space
		# basic configuration
		dpkg-reconfigure -plow tzdata
		rm -f /etc/default/locale  # force generation
		DEBIAN_PRIORITY=low; export DEBIAN_PRIORITY
		eatmydata apt-get --purge -y install --no-install-recommends \
		    --reinstall locales
		# whether the user just hit Enter
		case $(cat /etc/default/locale) in
		(''|'#  File generated by update-locale')
			# empty, add sensible default (same as update-locale)
			echo 'LANG=C.UTF-8' >>/etc/default/locale
			;;
		esac
		: remaining user configuration may error out intermittently
		set +e
		eatmydata apt-get --purge -y install --no-install-recommends \
		    console-common console-data console-setup
		case $setp in
		(no) unset DEBIAN_PRIORITY ;;
		(*) DEBIAN_PRIORITY=$setp; export DEBIAN_PRIORITY ;;
		esac
		: 'make man-db faster at cost of no apropos(1) lookup database'
		debconf-set-selections <<-'EODB'
			man-db man-db/build-database boolean false
			man-db man-db/auto-update boolean false
		EODB
		: install basic packages
		eatmydata apt-get --purge -y install --no-install-recommends \
		    adduser ca-certificates ed less lsb-release man-db \
		    popularity-contest procps sudo $(case $relse in
			(buster) echo bsdmainutils ;;
			(*) echo bsdextrautils ;;
		    esac)
		rm -f /var/cache/apt/archives/*.deb  # save temp space
		: install extra packages
		eatmydata apt-get --purge install --no-install-recommends $xpkgs
		rm -f /var/cache/apt/archives/*.deb  # save temp space
		: create initial user account, asking for password
		if test -n "$mkuser" && adduser -- "$mkuser"; then
			# groups from d-i plus adm and sudo (d-i does sudo, too?)
			: ignore errors for nonexisting groups, please
			for group in audio bluetooth cdrom debian-tor dip floppy \
			    lpadmin netdev plugdev scanner video adm sudo; do
				adduser -- "$mkuser" $group
			done
		else
			passwd root
		fi
		: end of pre-scripted post-bootstrap steps
		# prepare for manual steps as desired
		set +x
		# instruct the user what they can do now
		whiptail --backtitle 'd2di.sh' \
		    --msgbox "We will now (chrooted into the target system, under emulation, so it will be really slooooow…) run a login shell as the user account we just created ($userid), so you can do any manual post-installation steps desired.

Please use “sudo -S command” to run things as root, if necessary.

Press Enter to continue; exit the emulation with the “exit” command." 14 72
		# clean environment for interactive use
		export HOME=/  # later overridden by su
		# create an initial entry in syslog
		>>/var/log/syslog print -r -- "$(date +"%b %d %T")" \
		    "${HOSTNAME%%.*} d2di.sh[$$]:" \
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
		fstrim -v /
		>>/var/log/syslog print -r -- "$(date +"%b %d %T")" \
		    "${HOSTNAME%%.*} d2di.sh[$$]:" \
		    finishing up post-installation
		dd if=/dev/urandom bs=256 count=1 seek=1 conv=notrunc of="$rnd"
	EOS
) >"$mp/root/munge-it.sh" || die 'post-installation script creation failure'

debchroot_run -P "$mp" -w 'exec unshare --uts chroot' \
    /usr/bin/env -i TERM="$TERM" /bin/sh /root/munge-it.sh || die 'post-bootstrap failed'
# remove the oneshot script
rm -f "$mp/root/munge-it.sh"


debchroot_stop -P "$mp"
