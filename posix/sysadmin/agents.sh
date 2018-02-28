# $Id: agents.sh 5263+fixtty 2017-06-27 23:37:42Z tglase $
#-
# Copyright © 2009, 2012, 2015, 2017, 2018
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

test -n "$USER_ID" || USER_ID=$(id -u)
mkdir -p "$HOME/.ssh" "$HOME/.gnupg"
chmod 0700 "$HOME/.ssh" "$HOME/.gnupg"

for PID_FILE in .gnupg/gpg.conf .gnupg/gpg-agent.conf .ssh/config; do
	test -s /etc/skel/$PID_FILE || continue

	# list of known MD5 hashes of templates deployed by us
	# + note the spaces at beginning and end of md5list! +
	case $PID_FILE in
	.gnupg/gpg.conf)
		_md5list=" 2b7d7e47afb59ec164cf0ab512bb4ddc c8b796ed85a79e458a564645dcf38281 d5c4f4335d1eab08bfc9afe7ab494801 e6af3b74078a49db14f2f79fa82b7d3a 1f5d00be735cd1b1a57960c0128d2368 e51c210618d7dbc93c63e456d4dd4af1 7dfefaad0f417b7f50da1d80f8f0759b 07826f04f9e3b700e0f45da360d25877 "
		;;
	.gnupg/gpg-agent.conf)
		_md5list=" e7e9b7940f07c3cb447b30da27914f8d "
		;;
	*)
		_md5list=
		;;
	esac

	if test -s "$HOME/$PID_FILE"; then
		_md5=$( (fgrep -v '$Id' "$HOME/$PID_FILE" | md5sum) 2>&1 || \
		    echo fail)
		case $_md5list in
		*\ ${_md5%% *}\ *)
			# MD5 matches, remove file
			rm -f "$HOME/$PID_FILE"
			;;
		*)
			# MD5 does not match, do not touch file
			continue
			;;
		esac
	fi

	# file does not exist or was removed by us, install template
	cp /etc/skel/$PID_FILE "$HOME/$PID_FILE"
	chmod 0600 "$HOME/$PID_FILE"
done
unset _md5
unset _md5list

PID_FILE="/dev/shm/.ssh-$USER_ID"
test -n "$SSH_AGENT_PID" || test -z "$SSH_CONNECTION" || SSH_AGENT_PID=fwd
if test -n "$SSH_AUTH_SOCK"; then
	test -S "$SSH_AUTH_SOCK" || SSH_AGENT_PID=
else
	SSH_AGENT_PID=
fi
if test -z "$SSH_AGENT_PID" && \
    test -d "$PID_FILE/." && test -O "$PID_FILE/." && \
    test -s "$PID_FILE/info" && test -O "$PID_FILE/info"; then
	chmod -R go-rwx "$PID_FILE"
	. "$PID_FILE/info"
fi
if test -z "$SSH_AUTH_SOCK" || test -z "$SSH_AGENT_PID" || \
    test \! -S "$SSH_AUTH_SOCK"; then
	unset SSH_AUTH_SOCK SSH_AGENT_PID
	eval $(ssh-agent -s)
fi
if test -d "$PID_FILE/." && test -O "$PID_FILE/."; then
	: wonderful
else
	rm -rf "$PID_FILE"
	mkdir -p "$PID_FILE" && test -d "$PID_FILE/." && \
	    test -O "$PID_FILE/." && chmod -R go-rwx "$PID_FILE" || \
	    rm -rf "$PID_FILE"
fi
if test -d "$PID_FILE/." && test -O "$PID_FILE/."; then
	rm -f "$PID_FILE/info"
	:>"$PID_FILE/info"
	chmod 0600 "$PID_FILE/info"
fi
if test -f "$PID_FILE/info" && test -O "$PID_FILE/info" &&
    test -n "$SSH_AGENT_PID" && test -n "$SSH_AUTH_SOCK"; then
	echo "SSH_AGENT_PID=$SSH_AGENT_PID" >>"$PID_FILE/info"
	echo "SSH_AUTH_SOCK=$SSH_AUTH_SOCK" >>"$PID_FILE/info"
	export SSH_AUTH_SOCK SSH_AGENT_PID
else
	rm -f "$PID_FILE/info"
	unset SSH_AUTH_SOCK SSH_AGENT_PID
fi

: "${GNUPGHOME:=$HOME/.gnupg}"
find_gpg_agent() {
	local PID_FILE="$GNUPGHOME/gpg-agent-info-$(hostname)"
	local mytty

	if mytty=$(tty); then
		GPG_TTY=$mytty
		export GPG_TTY
	fi

	test -d "$GNUPGHOME" || return 0
	export GNUPGHOME

	test -n "$GPG_AGENT_INFO" && test -S "${GPG_AGENT_INFO%%:*}" && \
	    gpg-agent 2>/dev/null && return 0

	unset GPG_AGENT_INFO
	if test -s "$PID_FILE"; then
		. "$PID_FILE"
		export GPG_AGENT_INFO
		test -n "$GPG_AGENT_INFO" && \
		    test -S "${GPG_AGENT_INFO%%:*}" && \
		    gpg-agent 2>/dev/null && return 0
		rm -f "$PID_FILE"
	fi

	unset GPG_AGENT_INFO
	eval $(gpg-agent --daemon --sh)
	: "${GPG_AGENT_INFO:=$GNUPGHOME/S.gpg-agent:0:1}"
	export GPG_AGENT_INFO
	if test -n "$GPG_AGENT_INFO" && test -S "${GPG_AGENT_INFO%%:*}" && \
	    gpg-agent 2>/dev/null; then
		echo "GPG_AGENT_INFO=$GPG_AGENT_INFO" >"$PID_FILE"
		return 0
	fi

	unset GPG_AGENT_INFO
	return 0
}
find_gpg_agent
unset -f find_gpg_agent

:
