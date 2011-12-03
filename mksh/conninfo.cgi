#!/bin/mksh
# $MirOS: contrib/hosted/tg/conninfo.cgi,v 1.4 2008/12/10 15:06:00 tg Exp $
#-
# Copyright (c) 2008
#	Thorsten Glaser <tg@mirbsd.org>
#
# Provided that these terms and disclaimer and all copyright notices
# are retained or reproduced in an accompanying document, permission
# is granted to deal in this work without restriction, including un-
# limited rights to use, publicly perform, distribute, sell, modify,
# merge, give away, or sublicence.
#
# This work is provided "AS IS" and WITHOUT WARRANTY of any kind, to
# the utmost extent permitted by applicable law, neither express nor
# implied; without malicious intent or gross negligence. In no event
# may a licensor, author or contributor be held liable for indirect,
# direct, other damage, loss, or other issues arising in any way out
# of dealing in the work, even if advised of the possibility of such
# damage or existence of a defect, except proven that it results out
# of said person's immediate fault when using the work as intended.

print Content-type: text/plain
print Entropy: $RANDOM
print RCSID: '$MirOS: contrib/hosted/tg/conninfo.cgi,v 1.4 2008/12/10 15:06:00 tg Exp $'
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
