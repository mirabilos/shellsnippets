# $Id: agents.sh 805 2010-01-04 15:35:33Z tglase $
#-
# Copyright © 2009
#	Thorsten Glaser <t.glaser@tarent.de>
# Licenced under the AGPLv3
#-
# /etc/profile.d/agents.sh (sourced by /etc/profile on *buntu)
# • install gpg and ssh skeleton files
# • load gpg-agent and ssh-agent, unless already there

test -n "$USER_ID" || USER_ID=$(id -u)
mkdir -p "$HOME/.ssh" "$HOME/.gnupg"
chmod 0700 "$HOME/.ssh" "$HOME/.gnupg"

for PID_FILE in .gnupg/gpg.conf .gnupg/gpg-agent.conf .ssh/config; do
	test -s /etc/skel/$PID_FILE || continue

	# list of known MD5 hashes of templates deployed by us
	# + note the spaces at beginning and end of md5list! +
	case $PID_FILE in
	.gnupg/gpg.conf)
		md5list=" 2b7d7e47afb59ec164cf0ab512bb4ddc c8b796ed85a79e458a564645dcf38281 d5c4f4335d1eab08bfc9afe7ab494801 e6af3b74078a49db14f2f79fa82b7d3a 1f5d00be735cd1b1a57960c0128d2368 e51c210618d7dbc93c63e456d4dd4af1 7dfefaad0f417b7f50da1d80f8f0759b "
		;;
	.gnupg/gpg-agent.conf)
		md5list=" e7e9b7940f07c3cb447b30da27914f8d "
		;;
	*)
		md5list=
		;;
	esac

	if test -s "$HOME/$PID_FILE"; then
		md5=$( (fgrep -v '$Id' "$HOME/$PID_FILE" | md5sum) 2>&1 || \
		    echo fail)
		case $md5list in
		*\ ${md5%% *}\ *)
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
	: >"$PID_FILE/info"
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

: ${GNUPGHOME=$HOME/.gnupg}
PID_FILE="$GNUPGHOME/gpg-agent-info-$(hostname)"
GPG_TTY=$(tty); export GPG_TTY
if test -n "$GPG_AGENT_INFO" && test -S "${GPG_AGENT_INFO%%:*}" && \
    gpg-agent 2>/dev/null; then
	: wonderful
else
	unset GPG_AGENT_INFO
	test -s "$PID_FILE" && . "$PID_FILE"
	export GPG_AGENT_INFO
	if test -n "$GPG_AGENT_INFO" && test -S "${GPG_AGENT_INFO%%:*}" && \
	    gpg-agent 2>/dev/null; then
		: wonderful
	else
		unset GPG_AGENT_INFO
		eval $(gpg-agent --daemon --sh "--write-env-file=$PID_FILE")
		export GPG_AGENT_INFO
		if test -n "$GPG_AGENT_INFO" && \
		    test -S "${GPG_AGENT_INFO%%:*}" && \
		    gpg-agent 2>/dev/null; then
			: works now
		else
			unset GPG_AGENT_INFO
		fi
	fi
fi

unset PID_FILE
:
