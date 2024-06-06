#!/bin/mksh
# $Id: gencert.sh 1505+cvs 2010-10-11 12:26:46Z tglase $
# $MirOS: src/etc/rc,v 1.139 2024/06/06 00:30:02 tg Exp $
#-
# Copyright © 2010
#	mirabilos <t.glaser@tarent.de>
# Copyright © 2020, 2024
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

export LC_ALL=C.UTF-8
unset LANGUAGE

pubdirname=/etc/ssl
pubdirperm=00755
pubdir_uid=0
pubdir_gid=0
chain_name=$pubdirname/deflt-ca.cer
dhparmname=$pubdirname/dhparams.pem
pubkeyname=$pubdirname/default.cer
secdirname=$pubdirname/private
secdirperm=00710
secdir_uid=0
secdir_gid=ssl-cert
seckeyname=$secdirname/default.key

keyperms=0640
keyusers=$secdir_uid:$secdir_gid
pubperms=0644
pubusers=$pubdir_uid:$pubdir_gid
umask 077

keybits=4096
dh_bits=2048

[[ -d $pubdirname ]] || install -d \
    -o "$pubdir_uid" -g "$pubdir_gid" -m "$pubdirperm" "$pubdirname"
[[ -d $secdirname ]] || install -d \
    -o "$secdir_uid" -g "$secdir_gid" -m "$secdirperm" "$secdirname"

if [[ ! -s $seckeyname ]]; then
	print -n "openssl: generating new host RSA key... "
	rm -f "$seckeyname" "$pubkeyname" "$chain_name"
	if x=$(openssl genrsa -out "$seckeyname" "$keybits" 2>&1); then
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
if [[ ! -s $dhparmname ]]; then
	print "openssl: generating DH parameters"
	rm -f "$dhparmname"
	if openssl dhparam -out "$dhparmname" "$dh_bits"; then
		chown "$pubusers" "$dhparmname"
		chmod "$pubperms" "$dhparmname"
		print done.
	else
		rm -f "$dhparmname"
		print failed!
	fi
fi
if [[ -s $pubkeyname && -s $dhparmname ]]; then
	case $(set +e; grep -Fqxe '-----BEGIN DH PARAMETERS-----' "$pubkeyname"; echo $?) in
	(0)	;;
	(1)
		print openssl: appending DH parameters to certificate for httpd
		cat "$dhparmname" >>"$pubkeyname"
		;;
	(*)	print openssl: error appending DH parameters to certificate
		;;
	esac
fi
