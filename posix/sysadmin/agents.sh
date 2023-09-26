# -*- mode: sh -*-
#-
# Copyright © 2009, 2012, 2015, 2017, 2018, 2019, 2023
#	Thorsten Glaser <t.glaser@tarent.de>
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
# /etc/profile.d/agents.sh (sourced by /etc/profile on Debian and derivates)
# • install gpg and ssh skeleton files
# • load gpg-agent and ssh-agent, unless already there
#
# You should comment out “use-ssh-agent” in /etc/X11/Xsession.options
# in order to use the shared per-user agent started from this script.

test -n "${USER_ID:-}" || USER_ID=$(id -u)
test "$USER_ID" -ge 1000 || return 0

agents_sh_skelcheck() {
	local fn=$1 md5s md5
	test -s "/etc/skel/$fn" || return 0
	shift
	md5s=' '
	while test -n "$1"; do
		md5s="$md5s$1 "
		shift
	done
	if test -s "$HOME/$fn"; then
		md5=$( (fgrep -v '$Id' "$HOME/$fn" | md5sum) 2>&1 || echo fail)
		case md5s in
		*" $md5 "*)
			# matches, remove the old file
			rm -f "$HOME/$fn"
			;;
		*)
			# does not match (or error), don’t touch the file
			return 0
			;;
		esac
	fi

	# file does not exist, is empty, or was removed by us
	# install template
	cp "/etc/skel/$fn" "$HOME/$fn"
	chmod 0600 "$HOME/$fn"
}

if test -n "${KSH_VERSION:-}"; then
	agents_sh_p() {
		local x
		for x in "$@"; do
			print -r -- "$x"
		done
	}
else
	agents_sh_p() {
		printf '%s\n' "$@"
	}
fi

agents_sh_sshcheck() {
	local x=$1 l1 l2 ofn fnd; shift

	# read out other agents’ info and append to PPs
	if test -d "$x/." && test -O "$x/." && \
	    test -s "$x/info2" && test -O "$x/info2"; then
		chmod -R go-rwx "$x"
		while IFS= read -r l1; do
			IFS= read -r l2 || break
			set -- "$@" "$l1" "$l2"
		done <"$x/info2"
	fi

	# create output dir/file
	if test -d "$x/." && test -O "$x/."; then
		: ok, it already belongs to us
	else
		rm -rf "$x"
		mkdir -p "$x" && test -d "$x/." && \
		    test -O "$x/." && chmod -R go-rwx "$x" || \
		    rm -rf "$x"
	fi
	if test -d "$x/." && test -O "$x/."; then
		ofn="$x/info2~.$$"
		rm -f "$ofn"
		:>"$ofn"
		chmod 0600 "$ofn"
	else
		ofn=/dev/null # but what can you do?
	fi

	# process agents
	fnd=' '
	while test $# -ge 2; do
		l1=$1; l2=$2; shift; shift
		test -n "$l2" || continue
		test -S "$l2" || continue
		test -n "$l1" || l1=unknown
		case $fnd in
		*" $l2 "*) ;;
		*)
			agents_sh_p "$l1" "$l2"
			if test x"$fnd" = x" "; then
				SSH_AGENT_PID=$l1
				SSH_AUTH_SOCK=$l2
			fi
			fnd="$fnd$l2 "
			;;
		esac
	done >"$ofn"

	# no agent found?
	while test x"$fnd" = x" "; do
		unset SSH_AUTH_SOCK SSH_AGENT_PID
		eval $(ssh-agent -s) >/dev/null
		test -n "$SSH_AUTH_SOCK" || break
		test -n "$SSH_AGENT_PID" || break
		test -S "$SSH_AUTH_SOCK" || break
		fnd=$SSH_AUTH_SOCK
		agents_sh_p "$SSH_AGENT_PID" "$SSH_AUTH_SOCK"
	done >>"$ofn"

	# finished info file v2
	test x"$ofn" = x"/dev/null" || mv "$ofn" "$x/info2"

	# did we have an agent, now?
	if test x"$fnd" = x" "; then
		unset SSH_AUTH_SOCK SSH_AGENT_PID
	else
		export SSH_AUTH_SOCK SSH_AGENT_PID
	fi
}

agents_sh_checks() {
	local x p

	for x in "$HOME/.ssh" "$HOME/.gnupg"; do
		test -d "$x" && continue
		mkdir -p "$x"
		chmod 0700 "$x"
	done

	# extra arguments are list of MD5sums of old files shipped by us, to replace
	agents_sh_skelcheck .gnupg/gpg.conf 2b7d7e47afb59ec164cf0ab512bb4ddc c8b796ed85a79e458a564645dcf38281 d5c4f4335d1eab08bfc9afe7ab494801 e6af3b74078a49db14f2f79fa82b7d3a 1f5d00be735cd1b1a57960c0128d2368 e51c210618d7dbc93c63e456d4dd4af1 7dfefaad0f417b7f50da1d80f8f0759b 07826f04f9e3b700e0f45da360d25877
	agents_sh_skelcheck .gnupg/gpg-agent.conf e7e9b7940f07c3cb447b30da27914f8d
	agents_sh_skelcheck .ssh/config

	# handle ssh-agent connections
	x="/dev/shm/.ssh-$USER_ID"
	test -n "$SSH_AGENT_PID" || test -z "$SSH_CONNECTION" || \
	    SSH_AGENT_PID=fwd
	agents_sh_sshcheck "$x" "$SSH_AGENT_PID" "$SSH_AUTH_SOCK"

	# handle gpg-agent
	: "${GNUPGHOME:=$HOME/.gnupg}"
	if x=$(tty); then
		GPG_TTY=$x
		export GPG_TTY
	fi
	test -d "$GNUPGHOME" || return 0
	export GNUPGHOME
	p="$GNUPGHOME/gpg-agent-info2-$(hostname)"
	# shortcut
	if test -n "$GPG_AGENT_INFO" && test -S "${GPG_AGENT_INFO%%:*}" && \
	    gpg-agent 2>/dev/null; then
		export GPG_AGENT_INFO
		agents_sh_p "$GPG_AGENT_INFO" >"$p"
		return 0
	fi
	# already noted down
	if test -s "$p" && IFS= read -r GPG_AGENT_INFO <"$p" && \
	    test -n "$GPG_AGENT_INFO" && test -S "${GPG_AGENT_INFO%%:*}" && \
	    gpg-agent 2>/dev/null; then
		export GPG_AGENT_INFO
		return 0
	fi

	unset GPG_AGENT_INFO
	for x in 1 2; do
		# start as necessary in round 2
		test 2 = "$x" && eval $(gpg-agent --daemon --sh)
		while test -z "$GPG_AGENT_INFO"; do
			# is a gpg-agent already running?
			gpg-agent 2>/dev/null || break
			# divine its connection
			# 2.1/2.2-old default socket
			x=$GNUPGHOME/S.gpg-agent
			if test -S "$x"; then
				GPG_AGENT_INFO=$x:0:1
				break
			fi
			# 2.2-new different socket path
			x=$(gpgconf --list-dirs agent-socket) || x=
			if test -n "$x" && test -S "$x"; then
				GPG_AGENT_INFO=$x:0:1
				break
			fi
			echo >&2 "E: gpg-agent running but cannot access it"
			break
		done
		test -n "$GPG_AGENT_INFO" && \
		    test -S "${GPG_AGENT_INFO%%:*}" && \
		    gpg-agent 2>/dev/null && break
	done

	if test -n "$GPG_AGENT_INFO" && test -S "${GPG_AGENT_INFO%%:*}" && \
	    gpg-agent 2>/dev/null; then
		export GPG_AGENT_INFO
		agents_sh_p "$GPG_AGENT_INFO" >"$p"
	else
		unset GPG_AGENT_INFO
	fi
}

agents_sh_surround() {
	local a=$-

	# drop nounset
	case $a in
	*u*) set +u ;;
	esac
	case $a in
	*e*) set +e ;;
	esac

	agents_sh_checks
	unset -f agents_sh_skelcheck
	unset -f agents_sh_p
	unset -f agents_sh_sshcheck
	unset -f agents_sh_checks
	:
	case $a in
	*e*) set -e ;;
	esac
	case $a in
	*u*) set -u ;;
	esac
}
agents_sh_surround
unset -f agents_sh_surround
:
