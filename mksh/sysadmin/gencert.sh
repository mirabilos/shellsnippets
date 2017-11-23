#!/bin/mksh
# $Id: gencert.sh 1505 2010-10-11 12:26:46Z tglase $
# $MirOS: src/etc/rc,v 1.111 2010/07/11 17:35:09 tg Exp $
#-
# Copyright © 2010
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

seckeyname=/etc/ssl/private/default.key
pubkeyname=/etc/ssl/default.cer
chain_name=/etc/ssl/deflt-ca.cer

keyperms=640
keyusers=root:ssl-cert
#keyperms=600
#keyusers=0:0

# XXX 6000-8000 is recommended... choose less to be nice to old boxen
bitsize=4096

if [[ ! -s $seckeyname ]]; then
	print -n "openssl: generating new host RSA key... "
	rm -f $seckeyname $pubkeyname $chain_name
	if openssl genrsa -out $seckeyname $bitsize; then
		chown $keyusers $seckeyname
		chmod $keyperms $seckeyname
		print done.
	else
		print failed.
	fi
fi
if [[ ! -s $pubkeyname || ! -s $chain_name ]]; then
	print -n "openssl: generating new host X.509v3 certificate... "
	rm -f $pubkeyname $chain_name
	openssl req -batch -new -subj "/CN=$(hostname)/" \
	    -key $seckeyname \
	    -x509 -out $pubkeyname
	chmod 644 $pubkeyname
	cp $pubkeyname $chain_name
	print done
fi
