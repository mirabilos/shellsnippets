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

debchroot__mpt=
die() {
	echo >&2 "E: ${0##*/}: $*"
	test -z "$debchroot__mpt" || debchroot_stop -P "$debchroot__mpt"
	exit 1
}

usage() {
	echo >&2 "E: Usage: ${0##*/} [-p prio] /path/to/chroot"
	echo >&2 "N: prio for debconf [low|medium|high|critical]"
	exit ${1:-1}
}

setp=no
while getopts "hp:" ch; do
	case $ch in
	(h) usage 0 ;;
	(p) setp=$OPTARG ;;
	(*) usage ;;
	esac
done
shift $(($OPTIND - 1))
case $setp in
(no|low|medium|high|critical) ;;
(*) usage ;;
esac

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

debchroot_umtree "$mp/dev" || die something was sitting below chroot/dev/
chroot "$debchroot__mpt" /bin/sh -c '
	(cd /dev && exec MAKEDEV std consoleonly ttyS0)
    ' || die could not create initial device nodes
debchroot__quiet=1
debchroot_start -P "$mp" || die could not reload chroot
debchroot__quiet=

# as set by d-i
printf '%s\n' '0.0 0 0.0' 0 UTC >"$mp/etc/adjtime"
#XXX TODO: /etc/apt/sources.list
# from console-setup (1.193) config/keyboard (d-i)
cat >"$mp/etc/default/keyboard" <<-'EOF'
	# KEYBOARD CONFIGURATION FILE

	# Consult the keyboard(5) manual page.

	XKBMODEL=pc105
	XKBLAYOUT=us
	XKBVARIANT=
	XKBOPTIONS=

	BACKSPACE=guess
EOF
# avoids early errors, configured properly later
: >"$mp/etc/default/locale"
#XXX TODO /etc/fstab
#XXX TODO ask for $myfqdn
# hostname and hosts (generic)
case $myfqdn in
(*.*)	myhost="$myfqdn ${myfqdn%%.*}" ;;
(*)	myhost=$myfqdn ;;
esac
printf '%s\n' "$myfqdn" >"$mp/etc/hostname"
cat >"$mp/etc/hosts" <<-EOF
	127.0.0.1	$myhost localhost localhost.localdomain

	::1     ip6-localhost ip6-loopback localhost6 localhost6.localdomain6
	fe00::0 ip6-localnet
	ff00::0 ip6-mcastprefix
	ff02::1 ip6-allnodes
	ff02::2 ip6-allrouters
	ff02::3 ip6-allhosts
EOF
# like d-i
rm -f "$mp/etc/mtab"
ln -sfT /proc/self/mounts "$mp/etc/mtab"
cat >>"$mp/etc/network/interfaces" <<-'EOF'

	# The loopback network interface
	auto lo
	iface lo inet loopback
EOF
# for bootstrapping in chroot
cat /etc/resolv.conf >"$mp/etc/resolv.conf"
#XXX TODO rnd
	rnd=/var/lib/systemd/random-seed
	rnd=/var/lib/urandom/random-seed
# base directory, init system-dependent but identical
mkdir -p "$mp${rnd%/*}"
test -d "$mp${rnd%/*}"/.
chown 0:0 "$mp${rnd%/*}"
chmod 755 "$mp${rnd%/*}"
(
	set -e
	# beginning
	cat <<-'EOF'
		#!/bin/sh
		eval '(set -o pipefail)' >/dev/null 2>&1 && set -o pipefail || :
		set -e
		# reset environment so we can work
		HOME=/root LC_ALL=C PATH=/usr/sbin:/usr/bin:/sbin:/bin
		export HOME LC_ALL PATH
		LANGUAGE="C"; unset LANGUAGE
		# for etckeeper
		SUDO_USER=root USER=root
		export SUDO_USER USER
		# go on
		set -x
		# because this is picked up by packages, e.g. postfix
		hostname "$(cat /etc/hostname)"
#XXX set $HOSTNAME
		# sanitise APT state
		apt-get clean
		apt-get update
		# for debconf (required) and speed
		apt-get --purge -y install --no-install-recommends \
		    eatmydata libterm-readline-gnu-perl
		# just in case there were security uploads
		eatmydata apt-get --purge -y dist-upgrade
	EOF
	# switch to sysvinit?
	test -n "$dropsd" || cat <<-'EOF'
		eatmydata apt-get --purge -y install --no-install-recommends \
		    sysvinit-core systemd-
		printf '%s\n' \
		    'Package: systemd' 'Pin: version *' 'Pin-Priority: -1' '' \
		    >/etc/apt/preferences.d/systemd
		# make it suck slightly less, mostly already in sid
		(: >/etc/init.d/.legacy-bootordering)
		grep FANCYTTY /etc/lsb-base-logging.sh >/dev/null 2>&1 || \
		    echo FANCYTTY=0 >>/etc/lsb-base-logging.sh
	EOF
#XXX TODO query kernel
kernel=linux-image-amd64
	# install base packages
	echo "kernel=$kernel"
	cat <<-'EOF'
		rm -f /var/cache/apt/archives/*.deb  # save temp space
		# kernel, initrd and base firmware
		eatmydata apt-get --purge -y install --no-install-recommends \
		    busybox firmware-linux-free $kernel whiptail
		rm -f /var/cache/apt/archives/*.deb  # save temp space
		DEBIAN_FRONTEND=dialog; export DEBIAN_FRONTEND
		dpkg-reconfigure -plow tzdata
		rm -f /etc/default/locale  # force generation
		DEBIAN_PRIORITY=low \
		    eatmydata apt-get --purge -y install --no-install-recommends \
		    console-{common,data,setup} locales
		# whether the user just hit Enter
		case $(cat /etc/default/locale) in
		(''|'#  File generated by update-locale')
			# empty, add sensible default (same as update-locale)
			echo 'LANG=C.UTF-8' >>/etc/default/locale
			;;
		esac
		: remaining user configuration may error out intermittently
		set +e
		: 'make man-db faster at cost of no apropos(1) lookup database'
		debconf-set-selections <<-'EODB'
			man-db man-db/build-database boolean false
			man-db man-db/auto-update boolean false
		EODB
		: install basic packages
		eatmydata apt-get --purge -y install --no-install-recommends \
		    adduser ca-certificates ed ifupdown iproute2 less \
		    lsb-release man-db net-tools netcat-openbsd \
		    openssh-client popularity-contest procps sudo
		rm -f /var/cache/apt/archives/*.deb  # save temp space
	EOF
#XXX TODO
pkgs='bc etckeeper jupp lynx mc molly-guard openssh-server rsync screen sharutils'
userid=user
	cat <<-EOF
		: install extra packages
		eatmydata apt-get --purge install --no-install-recommends $pkgs
		rm -f /var/cache/apt/archives/*.deb  # save temp space
		: create initial user account, asking for password
		adduser '$userid'
		# groups from d-i plus adm and sudo (d-i does sudo, too?)
		: ignore errors for nonexisting groups, please
		for group in audio bluetooth cdrom debian-tor dip floppy \
		    lpadmin netdev plugdev scanner video adm sudo; do
			adduser '$userid' \$group
		done
		: end of pre-scripted post-bootstrap steps
		set +x
		# prepare for manual steps as desired
		userid='$userid'
	EOF
	cat <<-'EOF'
		# instruct the user what they can do now
		whiptail --backtitle 'd2di.sh' \
		    --msgbox "We will now (chrooted into the target system, under emulation, so it will be really slooooow…) run a login shell as the user account we just created ($userid), so you can do any manual post-installation steps desired.

Please use “sudo -S command” to run things as root, if necessary.

Press Enter to continue; exit the emulation with the “exit” command." 14 72
		# clean environment for interactive use
		unset DEBIAN_FRONTEND POSIXLY_CORRECT
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
	EOF
) >"$mp/root/munge-it.sh" || die 'post-installation script creation failure'

# now place initial random seed in the target location
mv rnd "$mp$rnd" || die 'mv rnd failed'
chown 0:0 "$mp$rnd" || die 'chown rnd failed'
chmod 600 "$mp$rnd" || die 'chmod rnd failed'
# second half (collected from host’s CSPRNG now)
dd if=/dev/urandom bs=256 count=1 >>"$mp$rnd" || die 'dd rnd2 failed'

debchroot_run -P "$mp" -w 'exec unshare --uts chroot' \
    /usr/bin/env -i TERM="$TERM" /bin/sh /root/munge-it.sh || die 'post-bootstrap failed'
# remove the oneshot script
rm -f "$mp/root/munge-it.sh"


debchroot_stop -P "$mp"
