# -*- mode: sh -*-
#-
# Copyright © 2015
#	Dominik George <dominik.george@teckids.org>
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

pty_base='http://wr.ispsuite.portunity.de/webrequests'
curl=$(whence -p curl)

pty_wr() {
	local product command data x
	product=$1; shift
	command=$1; shift
	set -A data
	for x in "$@"; do
		data+=(-F "$x")
	done

	$curl \
	    -F "sCommand=$command" \
	    -F "sProductLogin=$pty_product" -F "sProductCode=$pty_secret" \
	    "${data[@]}" \
	    "$pty_base/$product/"
}

pty_creds() {
	pty_product=$1
	pty_secret=$2
}

pty_sms() {
	local from to text
	from=$1
	to=$2
	text=$3

	pty_wr product-voip SendSMS "sSMSText=$text" "sSMSNumber=$to" "sSrcNumber=$from"
}

pty_fax() {
	local to file email
	to=$1
	file=$2
	email=$3

	pty_wr product-voip SendFax "sDestination=$to" "sFax=@$file" "sEmail=$email" "mimeType=application/pdf"
}
