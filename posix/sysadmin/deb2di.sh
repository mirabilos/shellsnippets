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
	(KEEP) ;;
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
N: initsystem = systemd or sysv | release e.g. bullseye or sid, or KEEP
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
test -s debfstab.sh || die debfstab.sh missing in script directory
debfstab_embed=1
. ./debfstab.sh

debchroot__quiet=1
debchroot_start -P "$mp" -s dev || die could not initialise chroot
debchroot__quiet=
die() {
	echo >&2 "E: ${0##*/}: $*"
	test -z "$mp" || debchroot_stop -P "$mp"
	exit 1
}

debchroot_umtree "$mp/dev" || die something was sitting below chroot/dev/
debchroot_run -P "$mp" /bin/sh -ec '
	uit() {
		ec=$1; shift
		echo >&2 "$*"
		exit $ec
	}
	test x"$(uname -s)" = x"Linux" || \
	    uit 0 "I: not stomping on non-Linux /dev"
	cd /dev || uit 1 "E: cannot cd /dev"
	if test -c .devfsd; then
		uit 0 "I: devfs active, not stomping on /dev"
	fi
	d=/dev
	if test -d /dev/.static/dev && mountpoint -q /dev/.static/dev; then
		echo >&2 "I: udev active, creating in /dev/.static/dev/"
		d=/dev/.static/dev
	elif test -d /.dev && mountpoint -q /.dev; then
		echo >&2 "I: udev active, creating in /.dev/"
		d=/.dev
	elif test -d .udevdb || test -d .udev; then
		uit 0 "I: udev active, not stomping on /dev"
	fi
	cd $d || uit 1 "E: cannot cd $d"
	umask 022 || uit 1 "E: umask error"

	ec=0
	dvmk() {
		f=./$1
		if test -h "$f"; then
			echo >&2 "W: not stomping on symlink $d/$1"
			test -e "$f" && return 0 || :
			rm -f "$f"
		fi
		if test -h "$f"; then
			echo >&1 "E: cannot delete dangling link $d/$1"
			ec=1
			return 0
		fi
		case $2 in
		(b|c) test -$2 "$f" || rm -f "$f" ;;
		esac
		test -e "$f" || mknod -m0 "$f" "$2" "$3" "$4" || ec=1
		chown -- "$5" "$f" || ec=1
		chmod -- "$6" "$f" || ec=1
	}
	dlnk() {
		f=./$1

		if test -h "$f"; then
			rm -f "$f"
		elif test -e "$f"; then
			rm -rf "$f"
		fi
		if test -h "$f" || test -e "$f"; then
			echo >&1 "E: cannot delete dangling $d/$1"
			ec=1
			return 0
		fi
		ln -s -- "$2" "$1"
	}

	dvmk mem	c 1 1	0:kmem	0640
	dvmk kmem	c 1 2	0:kmem	0640
	dvmk null	c 1 3	0:0	0666
	dvmk port	c 1 4	0:kmem	0640
	dvmk zero	c 1 5	0:0	0666
	dlnk core	/proc/kcore
	dvmk full	c 1 7	0:0	0666
	dvmk random	c 1 8	0:0	0666
	dvmk urandom	c 1 9	0:0	0666
	dvmk kmsg	c 1 11	0:0	0644

	dvmk ram0	b 1 0	0:disk	0660
	dvmk ram1	b 1 1	0:disk	0660
	dvmk initrd	b 1 250	0:disk	0660

	for n in 0 1 2 3 4 5 6 7 8 9 10 11 12; do
	  dvmk tty$n	c 4 $n	0:tty	0620
	done
	dvmk ttyS0	c 4 64	0:dialout 0660
	dvmk ttyS1	c 4 65	0:dialout 0660
	dvmk ttyS2	c 4 66	0:dialout 0660
	dvmk ttyS3	c 4 67	0:dialout 0660

	dvmk tty	c 5 0	0:tty	0666
	dvmk console	c 5 1	0:tty	0620
	dvmk ptmx	c 5 2	0:tty	0666

	for n in 0 1 2 3 4 5 6 7; do
	  dvmk loop$n	b 7 $n	0:disk	0660
	done
	dvmk loop-control c 10 237 0:disk 0660

	dvmk ttyACM0	c 166 0	0:dialout 0660
	dvmk ttyACM1	c 166 1	0:dialout 0660
	dvmk ttyUSB0	c 168 0	0:dialout 0660
	dvmk ttyUSB1	c 168 1	0:dialout 0660

	dlnk fd		/proc/self/fd
	dlnk stdin	fd/0
	dlnk stdout	fd/1
	dlnk stderr	fd/2

	test -d pts/. || {
		rm -f pts
		mkdir pts || ec=1
	}
	chown 0:0 pts || ec=1
	chmod 755 pts || ec=1

	test -h shm || {
		test -d shm/. || {
			rm -f shm
			mkdir shm || ec=1
		}
		chown 0:0 shm || ec=1
		chmod 755 shm || ec=1
	}

	test x"$ec" = x"0" || echo >&2 "W: there were errors"
	exit $ec
    ' || die could not create initial device nodes
debchroot__quiet=1
debchroot_start -P "$mp" || die could not reload chroot with /dev from host
debchroot__quiet=

sfn=$(mktemp "$mp/tmp.XXXXXXXXXX") || sfn=
case $sfn in
("$mp/tmp."*) ;;
(*) die unable to create temporary file ;;
esac

(
	set -e
	# beginning
	cat <<-'EOS'
		#!/bin/sh
		eval '(set -o pipefail)' >/dev/null 2>&1 && set -o pipefail || :
		set -e
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
		# init system-dependent path
		case $isys in
		(systemd)
			rnd=/var/lib/systemd/random-seed ;;
		(*)
			rnd=/var/lib/urandom/random-seed ;;
		esac
		mkdir -p "${rnd%/*}"
		test -d "${rnd%/*}"/.
		dd if=/dev/urandom bs=256 count=1 conv=notrunc of="$rnd"
		chown 0:0 "${rnd%/*}" "$rnd"
		chmod 755 "${rnd%/*}"
		chmod 600 "$rnd"
		# from user -p
		case $setp in
		(no) unset DEBIAN_PRIORITY ;;
		(*) DEBIAN_PRIORITY=$setp; export DEBIAN_PRIORITY ;;
		esac
		set -x
		# as set by d-i
		printf '%s\n' '0.0 0 0.0' 0 UTC >/etc/adjtime
		test x"$relse" = x"KEEP" || \
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
		base64 -d >/etc/fstab <<'_/'
	EOS
	debfstab "$mp" | base64
	cat <<-'EOS'
		_/
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
		grep -q 'iface lo inet loopback' /etc/network/interfaces || \
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
			touch /etc/init.d/.legacy-bootordering
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
		notinst() {
			case $(dpkg-query -Wf '${Status}\n' "$1" 2>/dev/null) in
			(|*\ ok\ not-installed)
				return 0 ;;
			(*)	return 1 ;;
			esac
		}
		toinst=
		notinst tzdata && toinst="$toinst tzdata" || :
		if notinst locales; then
			yn=
			notinst locales-all || yn=--defaultno
			if whiptail --backtitle 'd2di.sh' $yn \
			    --yesno "Do you want to install the locales package?" 7 47; then
				toinst="$toinst locales"
			fi
		else
			toinst="$toinst locales"
		fi
		if notinst console-data && notinst console-setup && \
		   notinst kbd && notinst keyboard-configuration; then
			if whiptail --backtitle 'd2di.sh' --defaultno \
			    --yesno "Do you want to install console/kbd setup?" 7 45; then
				toinst="$toinst console-common console-data console-setup kbd keyboard-configuration"
			fi
		else
			toinst="$toinst console-common console-data console-setup kbd keyboard-configuration"
		fi
		DEBIAN_PRIORITY=critical; export DEBIAN_PRIORITY
		test -z "$toinst" || eatmydata apt-get --purge -y install \
		    --no-install-recommends $toinst
		DEBIAN_PRIORITY=low; export DEBIAN_PRIORITY
		toinst=tzdata
		for pkg in locales console-setup keyboard-configuration \
		    console-data console-common; do
			notinst $pkg || toinst="$toinst $pkg"
		done
		rm -f /etc/default/locale  # force generation
		dpkg-reconfigure -plow $toinst
		# whether the user just hit Enter
		case $(cat /etc/default/locale) in
		(''|'#  File generated by update-locale')
			# empty, add sensible default (same as update-locale)
			echo 'LANG=C.UTF-8' >>/etc/default/locale
			;;
		esac
		case $setp in
		(no) unset DEBIAN_PRIORITY ;;
		(*) DEBIAN_PRIORITY=$setp; export DEBIAN_PRIORITY ;;
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
		    adduser ca-certificates ed less lsb-release man-db \
		    popularity-contest procps sudo $(case $relse in
			(KEEP) ;;
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
		whiptail --backtitle 'deb2di.sh' \
		    --msgbox "A login shell will now be run inside the chroot for any manual post-installation steps desired. Make sure to edit /etc/fstab!

Please use “sudo -S command” to run things as root, if necessary.

Press Enter to continue; use the “exit” command to quit." 12 69
		# clean environment for interactive use
		HOME=/  # later overridden by su
		# create an initial entry in syslog
		>>/var/log/syslog echo "$(date +"%b %d %T")" \
		    "${HOSTNAME%%.*} deb2di.sh[$$]:" \
		    soliciting manual post-installation steps
		chown 0:adm /var/log/syslog
		chmod 640 /var/log/syslog
		# avoids warnings with sudo, cf. Debian #922349
		find /usr/lib -name libeatmydata.so\* -a -type f -print0 | \
		    xargs -0r chmod u+s --
		(unset SUDO_USER USER; exec su - ${mkuser:+"$mkuser"})
		# revert the above change again
		find /usr/lib -name libeatmydata.so\* -a -type f -print0 | \
		    xargs -0r chmod u-s --
		# might not do anything, but allow the user refusal
		echo >&2 I: running apt-get autoremove, \
		    acknowledge as desired
		eatmydata apt-get --purge autoremove
		# remove installation debris
		echo >&2 'I: finally, cleaning up'
		eatmydata apt-get clean
		pwck -s
		grpck -s
		rm -f /etc/passwd- /etc/group- /etc/shadow- /etc/gshadow- \
		    /etc/subuid- /etc/subgid-
		# record initial /etc state
		if command -v etckeeper >/dev/null 2>&1; then
			etckeeper commit 'Finish installation'
			etckeeper vcs gc
		fi
		rm -f /var/log/bootstrap.log
		# from /lib/init/bootclean.sh
		cd /run
		find . ! -xtype d ! -name utmp ! -name innd.pid -delete
		# fine𝄐
		fstrim -v /
		>>/var/log/syslog echo "$(date +"%b %d %T")" \
		    "${HOSTNAME%%.*} deb2di.sh[$$]:" \
		    finishing up post-installation
		dd if=/dev/urandom bs=256 count=1 seek=1 conv=notrunc of="$rnd"
	EOS
) >"$sfn" || die 'post-installation script creation failure'

debchroot_run -P "$mp" -w 'exec unshare --uts chroot' /bin/sh -c '
    exec /usr/bin/env -i \
	DEBIAN_FRONTEND=teletype \
	HOME=/root \
	LC_ALL=C \
	PATH=/usr/sbin:/usr/bin:/sbin:/bin \
	TERM="$TERM" \
	debian_chroot="$debian_chroot" \
    /bin/sh '"/${sfn##*/}" || die 'post-bootstrap failed'
# remove the oneshot script
rm -f "$sfn"

debchroot_stop -P "$mp"
