#!/bin/mksh
# $Id: gencert.sh 1505+cvs 2010-10-11 12:26:46Z tglase $
# $MirOS: src/etc/rc,v 1.133 2020/03/05 19:54:37 tg Exp $
#-
# Copyright © 2010
#	mirabilos <t.glaser@tarent.de>
# Copyright © 2020
#	mirabilos <m@mirbsd.org>
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

seckeyname=/etc/ssl/private/default.key
pubkeyname=/etc/ssl/default.cer
chain_name=/etc/ssl/deflt-ca.cer

keyperms=640
keyusers=root:ssl-cert
pubperms=644
pubusers=0:0
umask 077

bitsize=4096

if [[ ! -s $seckeyname ]]; then
	print -n "openssl: generating new host RSA key... "
	rm -f "$seckeyname" "$pubkeyname" "$chain_name"
	if x=$(openssl genrsa -out "$seckeyname" "$bitsize" 2>&1); then
		chown "$keyusers" "$seckeyname"
		chmod "$keyperms" "$seckeyname"
		print done.
	else
		rm -f "$seckeyname"
		print failed:
		print -r -- "$x" | sed 's/^/| /'
	fi
	x=
fi
[[ -s $pubkeyname && -s $chain_name ]] || \
    if [[ -s $seckeyname ]]; then
	print -n "openssl: generating new host X.509v3 certificate... "
	rm -f "$pubkeyname" "$chain_name"
	if openssl req -batch -new -subj "/CN=$(hostname)/" \
	    -key "$seckeyname" \
	    -x509 -out "$pubkeyname"; then
		cp "$pubkeyname" "$chain_name"
		chown "$pubusers" "$pubkeyname" "$chain_name"
		chmod "$pubperms" "$pubkeyname" "$chain_name"
		print done.
	else
		rm -f "$pubkeyname" "$chain_name"
		print failed!
	fi
else
	rm -f "$pubkeyname" "$chain_name"
	print "openssl: cannot generate new host X.509v3 certificate: no key"
fi
