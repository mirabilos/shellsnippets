#!/bin/mksh
# © mirabilos Ⓕ MirBSD or CC0

print Content-type: text/plain
print X-Entropy: $RANDOM
print X-RCSID: '$MirOS: contrib/hosted/tg/conninfo.cgi,v 1.5 2024/10/29 15:05:44 tg Exp $'
print
if [[ -z $HTTPS ]]; then
	print -n "INSECURE (non-SSL) "
else
	print -n "SSL "
	[[ -z $SSL_PROTOCOL ]] || print -nr "($SSL_PROTOCOL"
	[[ -z $SSL_CIPHER ]] || print -nr ":$SSL_CIPHER"
	print -n ") "
fi
if [[ $REMOTE_ADDR = +([0-9]).+([0-9]).+([0-9]).+([0-9]) ]]; then
	print -n IPv4
elif [[ $REMOTE_ADDR = +([0-9a-fA-F:]):+([0-9a-fA-F:]) ]]; then
	print -n IPv6
else
	print -n AF_UNKNOWN
fi
print -r " connection from [$REMOTE_ADDR]:$REMOTE_PORT
$SERVER_PROTOCOL request to [$SERVER_ADDR]:$SERVER_PORT ($SERVER_NAME)"
[[ ,$QUERY_STRING, = *,ua,* ]] && print "using $HTTP_USER_AGENT"
exit 0
