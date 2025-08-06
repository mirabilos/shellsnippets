#!/bin/mksh
# -*- mode: sh -*-
#-
# Copyright © 2010, 2011, 2014
#	mirabilos <m$(date +%Y)@mirbsd.de>
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

feedback=
nl='
'
saveIFS=" 	$nl"
function trytodoit {
	if [[ $REQUEST_METHOD != GET ]]; then
		feedback="Not called via HTTP GET."
		return
	fi
	if [[ $HTTPS != on ]]; then
		feedback="Not called via HTTPS."
		return
	fi
	IFS='&'
	set -A flds -- $QUERY_STRING
	IFS=$saveIFS
	xfqdn=
	xstrength=
	xaction=0
	for fld in "${flds[@]}"; do
		case ${fld%%=*} {
		(fqdn) xfqdn=${fld#*=} ;;
		(strength) xstrength=${fld#*=} ;;
		(doit) xaction=${fld#*=} ;;
		(*) feedback="Invalid QUERY_STRING."; return ;;
		}
	done
	[[ $xaction = 0 ]] && return
	if [[ $xaction != Erstellen ]]; then
		feedback="Submit button not pressed."
		return
	fi
	if [[ $xstrength != @(2048|3072|4096) ]]; then
		feedback="Invalid strength given."
		return
	fi
	if [[ $xfqdn != ?('*.')[a-zA-Z0-9]?(*([a-zA-Z0-9-])[a-zA-Z0-9])+(.[a-zA-Z0-9]?(*([a-zA-Z0-9-])[a-zA-Z0-9])) ]]; then
		feedback="Invalid hostname (FQDN) given."
		return
	fi
	if ! K=$(openssl genrsa $xstrength 2>/dev/null); then
		feedback="Could not generate $xstrength bit secret key."
		return
	fi
	if ! R=$(print -r -- "$K" | openssl req -batch -new -sha1 \
	    -config /openssl.cnf -subj "/CN=${xfqdn}/" -key /dev/stdin \
	    2>/dev/null); then
		feedback="Could not generate CSR for ${xfqdn}."
		return
	fi
	cat <<-EOF
	Content-type: text/plain

	Congratulations, I generated a CSR for ${xfqdn} for you to
	copy and paste into the CA web form:

	$R


	The secret key (for /etc/ssl/private/\$foo.key - chown root:ssl-cert
	chmod 0640) of ${xstrength} bit length is:

	$K

	I will not save any copies of this, make sure to protect them!
EOF
	K=
	R=
	exit 0
}
trytodoit

cat <<'EOF'
Content-type: text/html; charset=UTF-8

<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
 "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en"><head>
 <meta name="tdm-reservation" content="1" />
 <title>Generierung eines Certificate Signing Request</title>
 <style type="text/css"><!--/*--><![CDATA[/*><!--*/
	strong { background-color:#FF0000; color:#000000; }
 /*]]>*/--></style>
</head><body>
<h1>Generierung eines Certificate Signing Request</h1>
EOF
[[ -z $feedback ]] || print -r -- "<p><strong>$feedback</strong></p>"
if [[ $HTTPS != on ]]; then
	echo '</body></html>'
	exit 1
fi
cat <<'EOF'
<form action="csrgen" method="get">
<p>Hostname: <input name="fqdn" type="text" size="32" maxlength="255" /></p>
<p>Stärke:<br />
 <input type="radio" name="strength" value="2048" checked="checked" />2048 Bit<br />
 <input type="radio" name="strength" value="3072" />3072 Bit<br />
 <input type="radio" name="strength" value="4096" />4096 Bit
</p>
<p><input type="submit" name="doit" value="Erstellen" /></p>
</form>
</body></html>
EOF
