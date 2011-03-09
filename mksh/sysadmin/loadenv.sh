# $Id: loadenv.sh 1202 2010-07-20 07:07:14Z tglase $
#-
# Not complicated enough for copyright.

[[ -s /usr/share/tarent/.Xresources ]] && xrdb /usr/share/tarent/.Xresources
# load ~/.Xmodmap and ~/.Xresources if they exist
[[ -s ~/.Xmodmap ]] && xmodmap ~/.Xmodmap
[[ -s ~/.Xresources ]] && xrdb ~/.Xresources

# load the ssh public key into the agent via the KDE Wallet
[[ -x /usr/bin/kwalletaskpass && -s /etc/profile.d/agents.sh ]] && (
	sleep 1
	# attempt to preopen the wallet
	kwalletcli -f foo -e bar >/dev/null 2>&1 &
	sleep 3

	. /etc/profile.d/agents.sh
	export SSH_ASKPASS=/usr/bin/kwalletaskpass
	/usr/bin/ssh-add
) <&- >/dev/null 2>&1 &

:
