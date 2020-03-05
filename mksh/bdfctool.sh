#!/bin/mksh
# $MirOS: X11/extras/bdfctool/bdfctool.sh,v 1.25 2020/02/14 04:42:39 tg Exp $
#-
# Copyright © 2007, 2008, 2009, 2010, 2012, 2013, 2015, 2019, 2020
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

set -o noglob

uascii=-1
ufast=0
oform=0
unimap=
while getopts "acdeFGghP:p:" ch; do
	case $ch {
	(a) uascii=1 ;;
	(+a) uascii=0 ;;
	(c|d|e|+e) mode=$ch oform=0 ;;
	(F) ufast=1 oform=0 ;;
	(G) oform=4 ;;
	(g) oform=3 ;;
	(h) mode=$ch ;;
	(p) oform=5 unimap=$OPTARG ;;
	(P) oform=6 unimap=$OPTARG ;;
	(*) mode= ;;
	}
done
shift $((OPTIND - 1))
(( $# )) && mode=

if [[ $mode = ?(h) ]] || [[ $mode != e && $uascii != -1 ]] || \
    [[ $mode != d && $ufast$oform != 00 ]]; then
	print -ru2 "Usage: ${0##*/} -c | -d [-FGg | -Pp unimap] | -e [-a] | +e"
	[[ $mode = h ]]; exit $?
fi

# check padding on input, currently
(( chkpad = (oform == 3 || oform == 4 || oform == 5 || oform == 6) ))

# disable -F if -g or -p
(( ufast = (oform == 3 || oform == 4 || oform == 5 || oform == 6) ? 0 : ufast ))

set -A psfumap
psfflag=0

rln=0
function rdln {
	local e
	nameref rdln_ln=$1

	IFS= read -r rdln_ln
	e=$?
	(( e )) && return $e
	let ++rln
	rdln_ln=${rdln_ln%%*( )?()}
	[[ $rdln_ln = *([ -~]) ]] && return 0
	print -ru2 "E: non-ASCII line $rln: ${rdln_ln@Q}"
	exit 5
}
function rdln_parsE {
	local e
	nameref rdln_ln=$1

	IFS= read -r rdln_ln
	e=$?
	(( e )) && return $e
	let ++rln
	rdln_ln=${rdln_ln%%*( )?()}
	linx=${rdln_ln//　/.}
	linx=${linx//䷀/#}
	linx=${linx//▌/|}
	linx=${linx//[ .]/0}
	linx=${linx//[#*]/1}
	[[ $linx = *([ -~]) ]] && return 0
	print -ru2 "E: non-ASCII line $rln: ${rdln_ln@Q}"
	exit 5
}

function chknameline {
	local uc=$1 nf=${#f[*]}

	if (( nf < 4 || nf > 5 )); then
		local cp=U+$uc ln=$2 es
		[[ -n $uc ]] || cp="U<${f[1]@Q}>"
		[[ -n $ln ]] || ln="${f[*]}"

		if (( nf < 4 )); then
			es='not enough'
		else
			es='too many'
		fi
		print -ru2 "E: $es fields $nf in name line $lno at $cp: ${ln@Q}"
		exit 2
	fi

	if [[ -z ${f[4]} || ( -n $uc && ${f[4]} = "uni$uc" ) ]]; then
		unset f[4]
	else
		[[ ${f[4]} = "${f[4]::14}" ]] || print -ru2 \
		    "W: overlong glyph name ${f[4]@Q} at line $lno"
		#f[4]=${f[4]::14}
	fi

	if [[ ${f[2]} != [1-9]*([0-9]) ]] || \
	    (( (w = f[2]) > 32 || w < 1 )); then
		print -ru2 "E: width ${f[2]@Q} not in 1‥32 at line $lno"
		exit 2
	fi
}

lno=0
if [[ $mode = e ]]; then
	if (( uascii == 1 )); then
		set -A BITv -- '.' '#' '|'
	else
		set -A BITv -- '　' '䷀' '▌'
	fi
	while rdln line; do
		(( ++lno ))
		if [[ $line = 'e '* ]]; then
			set -A f -- $line
			chknameline
			print -r -- "${f[*]}"
			i=${f[3]}
			while (( i-- )); do
				if rdln line; then
					print -r -- "$line"
					continue
				fi
				print -ru2 "E: Unexpected end of 'e' command" \
				    "at line $lno"
				exit 2
			done
			(( lno += f[3] ))
			continue
		fi
		if [[ $line != 'c '* ]]; then
			print -r -- "$line"
			continue
		fi
		set -A f -- $line
		chknameline
		if (( w <= 8 )); then
			adds=000000
		elif (( w <= 16 )); then
			adds=0000
		elif (( w <= 24 )); then
			adds=00
		else
			adds=
		fi
		(( shiftbits = 32 - w ))
		(( uw = 2 + w ))
		IFS=:
		set -A bmp -- ${f[3]}
		IFS=$' \t\n'
		f[0]=e
		f[3]=${#bmp[*]}
		print -r -- "${f[*]}"
		chl=0
		for ch in "${bmp[@]}"; do
			(( ++chl ))
			if [[ $ch != +([0-9A-F]) ]]; then
				print -ru2 "E: char '$ch' at #$chl in line $lno not hex"
				exit 2
			fi
			ch=$ch$adds
			if (( ${#ch} != 8 )); then
				print -ru2 "E: char '$ch' at #$chl in line $lno not valid"
				exit 2
			fi
			typeset -Uui2 -Z$uw bbin=16#$ch
			(( bbin >>= shiftbits ))
			b=${bbin#2#}
			b=${b//0/${BITv[0]}}
			b=${b//1/${BITv[1]}}
			print -r -- $b${BITv[2]}
		done
	done
	exit 0
fi

Fdef=		# currently valid 'd' line
set -A Fhead	# lines of file header, including comments intersparsed
set -A Fprop	# lines of file properties, same
set -A Gprop	# glyph property line (from Fdef), per glyph
set -A Gdata	# glyph data line, per glyph
set -A Gcomm	# glyph comments (if any) as string, per glyph
set -A Fcomm	# lines of comments at end of file

state=0

function parse_bdfc_file {
	local last

	set -A last
	while rdln line; do
		(( ++lno ))
		if [[ $line = C ]]; then
			Fprop+=("${last[@]}")
			state=1
			return
		elif [[ $line = '=bdfc 1' ]]; then
			set -A hFBB
			continue
		fi
		last+=("$line")
		case $line {
		(\'|\'\ *)
			continue
			;;
		(hFONTBOUNDINGBOX\ +([0-9])\ +([0-9])\ +([0-9-])\ +([0-9-]))
			set -A hFBB -- $line
			Fhead+=("${last[@]}")
			;;
		(h*)
			Fhead+=("${last[@]}")
			;;
		(p*)
			Fprop+=("${last[@]}")
			;;
		(*)
			print -ru2 "E: invalid line $lno: '$line'"
			exit 2
			;;
		}
		set -A last
	done
	Fprop+=("${last[@]}")
	(( chkpad )) && if [[ -z $hFBB ]]; then
		print -ru2 "E: missing FONTBOUNDINGBOX header"
		exit 2
	fi
	state=2
}

function parse_bdfc_edit {
	local shiftbits uw line r i

	if (( w <= 8 )); then
		(( shiftbits = 8 - w ))
		(( uw = 5 ))
	elif (( w <= 16 )); then
		(( shiftbits = 16 - w ))
		(( uw = 7 ))
	elif (( w <= 24 )); then
		(( shiftbits = 24 - w ))
		(( uw = 9 ))
	else
		(( shiftbits = 32 - w ))
		(( uw = 11 ))
	fi

	if [[ ${f[3]} != [1-9]*([0-9]) ]] || \
	    (( (i = f[3]) < 1 || i > 999 )); then
		print -ru2 "E: nonsensical number of lines ${f[3]@Q} in" \
		    "line $lno, U+${ch#16#}"
		exit 2
	fi

	while (( i-- )); do
		if ! rdln_parsE line; then
			print -ru2 "E: Unexpected end of 'e' command" \
			    "at line $lno, U+${ch#16#}"
			exit 2
		fi
		(( ++lno ))
		if [[ $linx != +([01])'|' || ${#linx} != $((w + 1)) ]]; then
			print -ru2 "E: U+${ch#16#} (line $lno) bitmap line" \
			    $((f[3] - i)) "invalid: '$line'"
			exit 2
		fi
		linx=${linx%'|'}
		typeset -Uui16 -Z$uw bhex=2#$linx
		(( bhex <<= shiftbits ))
		r+=${bhex#16#}:
	done
	f[3]=${r%:}
	f[0]=c
}

function parse_bdfc_glyph {
	local last

	set -A last
	while rdln line; do
		(( ++lno ))
		if [[ $line = . ]]; then
			Fcomm+=("${last[@]}")
			state=0
			return
		fi
		if [[ $line = \' || $line = "' "* ]]; then
			last+=("$line")
			continue
		fi
		set -A f -- $line
		if [[ ${f[0]} = d ]]; then
			Fdef="${f[*]}"
			(( chkpad )) && if [[ ${f[5]},${f[6]} != ${hFBB[3]},${hFBB[4]} ]]; then
				print -ru2 "E: d line $lno does not match FONTBOUNDINGBOX … ${hFBB[3]} ${hFBB[4]}"
				exit 2
			fi
			continue
		fi
		if [[ ${f[0]} != [ce] ]]; then
			print -ru2 "E: invalid line $lno: '$line'"
			exit 2
		fi
		if [[ $Fdef != 'd '* ]]; then
			print -ru2 "E: char at line $lno without defaults set"
			exit 2
		fi
		if [[ ${f[1]} != [0-9A-F][0-9A-F][0-9A-F][0-9A-F] ]]; then
			print -ru2 "E: invalid encoding '${f[1]}' at line $lno"
			exit 2
		fi
		typeset -Uui16 -Z7 ch=16#${f[1]}
		chknameline "${ch#16#}" "$line"
		(( chkpad )) && if [[ $w != "${hFBB[1]}" ]]; then
			print -ru2 "E: c line $lno width $w does not match FONTBOUNDINGBOX ${hFBB[1]}"
			exit 2
		fi
		if [[ ${f[0]} = e ]]; then
			parse_bdfc_edit
		else
			if (( w <= 8 )); then
				x='+([0-9A-F][0-9A-F]:)'
			elif (( w <= 16 )); then
				x='+([0-9A-F][0-9A-F][0-9A-F][0-9A-F]:)'
			elif (( w <= 24 )); then
				x='+([0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]:)'
			else
				x='+([0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]:)'
			fi
			if eval [[ '${f[3]}:' != "$x" ]]; then
				print -ru2 "E: invalid hex encoding for" \
				    "U+${ch#16#}, line $lno: '${f[3]}'"
				exit 2
			fi
		fi
		if (( chkpad )); then
			x=${f[3]//[!:]}
			if (( (${#x} + 1) != hFBB[2] )); then
				print -ru2 "E: c line $lno height $((${#x} + 1)) does not match FONTBOUNDINGBOX ${hFBB[2]}"
				exit 2
			fi
		fi
		Gdata[ch]="${f[*]}"
		for line in "${last[@]}"; do
			Gcomm[ch]+=$line$'\n'
		done
		set -A last
		Gprop[ch]=$Fdef
	done
	Fcomm+=("${last[@]}")
	state=2
}

function parse_bdfc {
	while :; do
		case $state {
		(0) parse_bdfc_file ;;
		(1) parse_bdfc_glyph ;;
		(2) return 0 ;;
		}
	done
	print -ru2 "E: internal error (at line $lno), shouldn't happen"
	exit 255
}

function parse_bdf {
	set -A hFBB
	while rdln line; do
		(( ++lno ))
		case $line {
		(COMMENT)
			Fhead+=("'")
			;;
		(COMMENT@([	 ])*)
			Fhead+=("' ${line#COMMENT[	 ]}")
			;;
		(STARTPROPERTIES\ +([0-9]))
			break
			;;
		(FONTBOUNDINGBOX\ +([0-9])\ +([0-9])\ +([0-9-])\ +([0-9-]))
			set -A hFBB -- $line
			Fhead+=("h$line")
			;;
		(*)
			Fhead+=("h$line")
			;;
		}
	done
	(( chkpad )) && if [[ -z $hFBB ]]; then
		print -ru2 "E: missing FONTBOUNDINGBOX header"
		exit 2
	fi
	set -A f -- $line
	numprop=${f[1]}
	while rdln line; do
		(( ++lno ))
		case $line {
		(COMMENT)
			Fprop+=("'")
			;;
		(COMMENT@([	 ])*)
			Fprop+=("' ${line#COMMENT[	 ]}")
			;;
		(ENDPROPERTIES)
			break
			;;
		(*)
			Fprop+=("p$line")
			let --numprop
			;;
		}
	done
	if (( numprop )); then
		print -ru2 "E: expected ${f[1]} properties, got" \
		    "$((f[1] - numprop)) in line $lno"
		exit 2
	fi
	while rdln line; do
		(( ++lno ))
		case $line {
		(COMMENT)
			Fprop+=("'")
			;;
		(COMMENT@([	 ])*)
			Fprop+=("' ${line#COMMENT[	 ]}")
			;;
		(CHARS\ +([0-9]))
			break
			;;
		(*)
			print -ru2 "E: expected CHARS not '$line' in line $lno"
			exit 2
			;;
		}
	done
	set -A f -- $line
	numchar=${f[1]}
	set -A cc
	set -A cn
	set -A ce
	set -A cs
	set -A cd
	set -A cb
	while rdln line; do
		(( ++lno ))
		case $line {
		(COMMENT)
			cc+=("'")
			;;
		(COMMENT@([	 ])*)
			cc+=("' ${line#COMMENT[	 ]}")
			;;
		(STARTCHAR\ *)
			set -A cn -- $line
			;;
		(ENCODING\ +([0-9]))
			set -A ce -- $line
			;;
		(SWIDTH\ +([0-9-])\ +([0-9-]))
			set -A cs -- $line
			;;
		(DWIDTH\ +([0-9-])\ +([0-9-]))
			set -A cd -- $line
			;;
		(BBX\ +([0-9])\ +([0-9])\ +([0-9-])\ +([0-9-]))
			set -A cb -- $line
			(( chkpad )) && if [[ ${cb[1]},${cb[2]},${cb[3]},${cb[4]} != ${hFBB[1]},${hFBB[2]},${hFBB[3]},${hFBB[4]} ]]; then
				print -ru2 "E: BBX in line $lno does not match FONTBOUNDINGBOX ${hFBB[1]} ${hFBB[2]} ${hFBB[3]} ${hFBB[4]}"
				exit 2
			fi
			;;
		(BITMAP)
			if [[ -z $cn ]]; then
				print -ru2 "E: missing STARTCHAR in line $lno"
				exit 2
			fi
			if [[ -z $ce ]]; then
				print -ru2 "E: missing ENCODING in line $lno"
				exit 2
			fi
			if [[ -z $cs ]]; then
				print -ru2 "E: missing SWIDTH in line $lno"
				exit 2
			fi
			if [[ -z $cd ]]; then
				print -ru2 "E: missing DWIDTH in line $lno"
				exit 2
			fi
			if [[ -z $cb ]]; then
				print -ru2 "E: missing BBX in line $lno"
				exit 2
			fi
			typeset -Uui16 -Z7 ch=10#${ce[1]}
			if (( ch < 0 || ch > 0xFFFF )); then
				print -ru2 "E: encoding ${ce[1]} out of" \
				    "bounds in line $lno"
				exit 2
			fi
			Gprop[ch]="d ${cs[1]} ${cs[2]} ${cd[1]} ${cd[2]} ${cb[3]} ${cb[4]}"
			set -A f c ${ch#16#} ${cb[1]} - ${cn[1]}
			chknameline "${ch#16#}"
			if (( w <= 8 )); then
				ck='[0-9A-F][0-9A-F]'
			elif (( w <= 16 )); then
				ck='[0-9A-F][0-9A-F][0-9A-F][0-9A-F]'
			elif (( w <= 24 )); then
				ck='[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]'
			else
				ck='[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]'
			fi
			if (( (numlines = cb[2]) )); then
				bmps=
				typeset -u linu
				while rdln linx; do
					(( ++lno ))
					linu=$linx
					while eval [[ '$linu' != "$ck" ]]; do
						if [[ $linu = *00 ]]; then
							linu=${linu%00}
							continue
						fi
						print -ru2 "E: invalid hex encoding" \
						    "for U+${ch#16#} (dec. $((ch)))" \
						    "on line $lno: '$linx'"
						exit 2
					done
					bmps+=$linu:
					(( --numlines )) || break
				done
				f[3]=${bmps%:}
			else
				f[2]=1
				f[3]=00
			fi
			if ! rdln line || [[ $line != ENDCHAR ]]; then
				print -ru2 "E: expected ENDCHAR after line $lno"
				exit 2
			fi
			(( ++lno ))
			Gdata[ch]="${f[*]}"
			[[ -n $cc ]] && for line in "${cc[@]}"; do
				Gcomm[ch]+=$line$'\n'
			done
			set -A cc
			set -A cn
			set -A ce
			set -A cs
			set -A cd
			set -A cb
			;;
		(ENDFONT)
			break
			;;
		(*)
			print -ru2 "E: unexpected '$line' in line $lno"
			exit 2
			;;
		}
	done
	Fcomm+=("${cc[@]}")
	for line in "${cn[*]}" "${ce[*]}" "${cs[*]}" "${cd[*]}" "${cb[*]}"; do
		[[ -n $line ]] || continue
		print -ru2 "E: unexpected '$line' between last char and ENDFONT"
		exit 2
	done
	if (( numchar != ${#Gdata[*]} )); then
		print -ru2 "E: expected $numchar glyphs, got ${#Gdata[*]}"
		exit 2
	fi
	while rdln line; do
		(( ++lno ))
		case $line {
		(COMMENT)
			Fcomm+=("'")
			;;
		(COMMENT@([	 ])*)
			Fcomm+=("' ${line#COMMENT[	 ]}")
			;;
		(*)
			print -ru2 "E: unexpected '$line' past ENDFONT" \
			    "in line $lno"
			exit 2
			;;
		}
	done
}

function read_psfumap {
	[[ $unimap = . ]] && return
	local has_seq=0 cp map x
	local -u linu
	while IFS= read -r line; do
		[[ $line = *([	 ])?('#'*) ]] && continue
		linu=$line
		if [[ $linu != @(0X+([0-9A-F])|+([0-9]))'	'* ]]; then
			print -ru2 "E: invalid unimap line:	$line"
			exit 2
		fi
		cp=${linu%%	*}
		if [[ -n ${psfumap[cp]} ]]; then
			print -ru2 "E: duplicate unimap in line:	$line"
			exit 2
		fi
		linu=\ ${linu#*	}
		if [[ $linu != +(+([	 ])U+[0-9A-F][0-9A-F][0-9A-F][0-9A-F]*(,U+[0-9A-F][0-9A-F][0-9A-F][0-9A-F])) ]]; then
			print -ru2 "E: invalid unimap line:	$line"
			exit 2
		fi
		[[ $linu = *,* ]] && has_seq=1
		psfumap[cp]=${linu//U+}
	done <"$unimap"
	(( psfflag |= has_seq ? 4 : 2 ))
}

function twiddle_psfumapent {
	set -A pmap
	set -A smap
	for x in ${psfumap[curch]}; do
		if [[ $x = *,* ]]; then
			smap+=($x)
		else
			pmap+=($x)
		fi
	done
	if [[ -z $pmap$smap ]]; then
		print -ru2 "E: missing unicode map for 0x${curch#16#}"
		exit 2
	fi
	o=
}

function twiddle_wchar {
	local x
	typeset -Uui16 -Z7 i

	for x in "$@"; do
		i=0x$x
		o+=\\u${i#16#}
	done
}

if [[ $mode = c ]]; then
	if ! rdln line; then
		print -ru2 "E: read error at BOF"
		exit 2
	fi
	lno=1
	if [[ $line = 'STARTFONT 2.1' ]]; then
		parse_bdf
	elif [[ $line = '=bdfc 1' ]]; then
		parse_bdfc
	else
		print -ru2 "E: not BDF or bdfc at BOF: '$line'"
		exit 2
	fi

	# write .bdfc stream

	for line in '=bdfc 1' "${Fhead[@]}" "${Fprop[@]}"; do
		print -r -- "$line"
	done
	print C
	Fdef=
	for x in ${!Gdata[*]}; do
		if [[ ${Gprop[x]} != "$Fdef" ]]; then
			Fdef=${Gprop[x]}
			print -r -- $Fdef
		fi
		print -r -- "${Gcomm[x]}${Gdata[x]}"
	done
	for line in "${Fcomm[@]}"; do
		print -r -- "$line"
	done
	print .
	exit 0
fi

if [[ $mode = +e ]]; then
	while rdln line; do
		(( ++lno ))
		if [[ $line = \' || $line = "' "* ]]; then
			print -r -- "$line"
			continue
		fi
		set -A f -- $line
		if [[ ${f[0]} != [ce] ]]; then
			print -ru2 "E: invalid line $lno: '$line'"
			exit 2
		fi
		if [[ ${f[1]} != [0-9A-F][0-9A-F][0-9A-F][0-9A-F] ]]; then
			print -ru2 "E: invalid encoding '${f[1]}' at line $lno"
			exit 2
		fi
		typeset -Uui16 -Z7 ch=16#${f[1]}
		chknameline "${ch#16#}" "$line"
		if [[ ${f[0]} = e ]]; then
			parse_bdfc_edit
		else
			if (( w <= 8 )); then
				x='+([0-9A-F][0-9A-F]:)'
			elif (( w <= 16 )); then
				x='+([0-9A-F][0-9A-F][0-9A-F][0-9A-F]:)'
			elif (( w <= 24 )); then
				x='+([0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]:)'
			else
				x='+([0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]:)'
			fi
			if eval [[ '${f[3]}:' != "$x" ]]; then
				print -ru2 "E: invalid hex encoding for" \
				    "U+${ch#16#}, line $lno: '${f[3]}'"
				exit 2
			fi
		fi
		print -r -- "${f[@]}"
	done
	exit 0
fi

if [[ $mode != d ]]; then
	print -ru2 "E: cannot happen (control flow issue in ${0##*/}:$LINENO)"
	exit 255
fi

if ! rdln line; then
	print -ru2 "E: read error at BOF"
	exit 2
fi
lno=1

if (( ufast )); then
	if [[ $line != '=bdfc 1' ]]; then
		print -ru2 "E: not bdfc at BOF: '$line'"
		exit 2
	fi
	if ! T=$(mktemp /tmp/bdfctool.XXXXXXXXXX); then
		print -u2 E: cannot make temporary file
		exit 4
	fi
	# quickly parse bdfc header
	set -A last
	while rdln line; do
		[[ $line = C ]] && break
		last+=("$line")
		[[ $line = \' || $line = "' "* ]] && continue
		if [[ $line = h* ]]; then
			Fhead+=("${last[@]}")
		else
			Fprop+=("${last[@]}")
		fi
		set -A last
	done
	Fprop+=("${last[@]}")
elif [[ $line = 'STARTFONT 2.1' ]]; then
	# parse entire BDF file into memory
	parse_bdf
elif [[ $line = '=bdfc 1' ]]; then
	# parse entire bdfc file into memory
	parse_bdfc
else
	print -ru2 "E: not BDF or bdfc at BOF: '$line'"
	exit 2
fi

# analyse data for BDF
numprop=0
for line in "${Fprop[@]}"; do
	[[ $line = p* ]] && let ++numprop
done
(( ufast )) || numchar=${#Gdata[*]}

# handle diverging and non-ufast output formats
case $oform {
(3|6)
	# little-endian .gdf
	function out_int32 {
		typeset -Uui16 value=$1
		typeset -Uui8 ba bb bc bd

		(( bd = (value >> 24) & 0xFF ))
		(( bc = (value >> 16) & 0xFF ))
		(( bb = (value >> 8) & 0xFF ))
		(( ba = value & 0xFF ))
		print -n "\\0${ba#8#}\\0${bb#8#}\\0${bc#8#}\\0${bd#8#}"
	}
	;|
(4)
	# big-endian .gdf
	function out_int32 {
		typeset -Uui16 value=$1
		typeset -Uui8 ba bb bc bd

		(( ba = (value >> 24) & 0xFF ))
		(( bb = (value >> 16) & 0xFF ))
		(( bc = (value >> 8) & 0xFF ))
		(( bd = value & 0xFF ))
		print -n "\\0${ba#8#}\\0${bb#8#}\\0${bc#8#}\\0${bd#8#}"
	}
	;|
(3|4|5|6)
	# do some input analysis for .gdf and .pcf output
	if [[ -z $hFBB ]]; then
		print -ru2 "E: missing FONTBOUNDINGBOX header"
		exit 2
	fi
	;|
(3|4)
	# .gdf output
	nullch=
	x=$((hFBB[1] * hFBB[2]))
	while (( x-- )); do
		nullch+=\\0
	done
	if (( hFBB[1] <= 8 )); then
		adds=000000
	elif (( hFBB[1] <= 16 )); then
		adds=0000
	elif (( hFBB[1] <= 24 )); then
		adds=00
	else
		adds=
	fi
	# write .gdf stream
	out_int32 $((# lastch - firstch + 1))
	out_int32 $((# firstch))
	out_int32 $((# hFBB[1]))
	out_int32 $((# hFBB[2]))
	typeset -i curch
	((# curch = firstch - 1 ))
	while ((# ++curch <= lastch )); do
		set -A f -- ${Gdata[curch]}
		if [[ -z $f ]]; then
			print -n "$nullch"
			continue
		fi
		IFS=:
		set -A bmp -- ${f[3]}
		IFS=$' \t\n'
		s=
		for line in "${bmp[@]}"; do
			typeset -Uui2 bbin=16#$line$adds
			x=${hFBB[1]}
			while (( x-- )); do
				s+=\\0$(( (bbin & 0x80000000) ? 377 : 0 ))
				(( bbin <<= 1 ))
			done
		done
		print -n "$s"
	done
	exit 0
	;;
(5)
	# .psf{,u} v1 output
	read_psfumap
	if (( numchar == 512 )); then
		(( psfflag |= 1 ))
	elif (( numchar != 256 )); then
		print -ru2 "E: number of chars $numchar invalid"
		exit 2
	fi
	set -A f -- ${!Gdata[*]}
	typeset -i firstch=${f[0]} lastch=${f[${#f[*]} - 1]}
	if (( firstch != 0 )) || (( lastch != (numchar - 1) )); then
		print -ru2 "E: not $numchar chars: $firstch .. $lastch"
		exit 2
	fi
	if (( hFBB[1] != 8 )); then
		print -ru2 "E: invalid width ${hFBB[1]}"
		exit 2
	fi
	print -nA 0x36 0x04 psfflag hFBB[2]
	typeset -Uui16 -Z$((numchar == 512 ? 6 : 5)) curch=-1
	while (( ++curch < numchar )); do
		set -A f -- ${Gdata[curch]}
		if [[ -z $f ]]; then
			print -ru2 "E: missing char 0x${curch#16#}"
			exit 2
		fi
		bmp=:${f[3]}
		print -nA ${bmp//:/ 0x}
	done
	curch=-1
	(( psfflag & (2|4) )) && while (( ++curch < numchar )); do
		twiddle_psfumapent
		for x in "${pmap[@]}"; do
			o+="0x${x:2} 0x${x::2} "
		done
		for s in "${smap[@]}"; do
			o+="0xFE 0xFF "
			for x in ${s//,/ }; do
				o+="0x${x:2} 0x${x::2} "
			done
		done
		print -nA $o 0xFF 0xFF
	done
	exit 0
	;;
(6)
	# .psf{,u} v2 output
	read_psfumap
	print -nA 0x72 0xB5 0x4A 0x86 0 0 0 0 0x20 0 0 0 \
	    $(((psfflag & (2|4)) ? 1 : 0)) 0 0 0
	out_int32 $((# numchar))
	out_int32 $((# ((hFBB[1] + 7) / 8) * hFBB[2]))
	out_int32 $((# hFBB[2]))
	out_int32 $((# hFBB[1]))
	for curch in ${!Gdata[*]}; do
		set -A f -- ${Gdata[curch]}
		bmp=${f[3]//:}
		print -nA ${bmp@/??/ 0x$KSH_MATCH}
	done
	(( psfflag & (2|4) )) && for curch in ${!Gdata[*]}; do
		twiddle_psfumapent
		twiddle_wchar "${pmap[@]}"
		for s in "${smap[@]}"; do
			o+='\xFE'
			twiddle_wchar ${s//,/ }
		done
		print -n "${o[@]}\\xFF"
		unset psfumap[curch]
	done
	if [[ -n "${psfumap[*]}" ]]; then
		print -ru2 "E: extra Unicode map entries"
		for x in "${!psfumap[@]}"; do
			print -ru2 "N: $x(${psfumap[x]})"
		done
		exit 2
	fi
	exit 0
	;;
}

# write BDF stream
print 'STARTFONT 2.1'
for line in "${Fhead[@]}"; do
	if [[ $line = h* ]]; then
		print -r -- "${line#h}"
	else
		print -r -- "COMMENT${line#\'}"
	fi
done
set -A last
print STARTPROPERTIES $((numprop))
for line in "${Fprop[@]}"; do
	if [[ $line = p* ]]; then
		last+=("${line#p}")
	else
		last+=("COMMENT${line#\'}")
		continue
	fi
	for line in "${last[@]}"; do
		print -r -- "$line"
	done
	set -A last
done
print ENDPROPERTIES
for line in "${last[@]}"; do
	print -r -- "$line"
done
if (( ufast )); then
	numchar=0
	# directly transform font data
	set -A last
	while rdln line; do
		[[ $line = . ]] && break
		if [[ $line = \' || $line = "' "* ]]; then
			last+=("$line")
			continue
		fi
		set -A f -- $line
		if [[ ${f[0]} = d ]]; then
			set -A xprop -- $line
			continue
		fi
		typeset -Uui16 -Z7 ch=16#${f[1]}
		for line in "${last[@]}"; do
			print -r -- "COMMENT${line#\'}"
		done
		set -A last
		IFS=:
		set -A bmp -- ${f[3]}
		IFS=$' \t\n'
		cat <<-EOF
			STARTCHAR ${f[4]:-uni${ch#16#}}
			ENCODING $((ch))
			SWIDTH ${xprop[1]} ${xprop[2]}
			DWIDTH ${xprop[3]} ${xprop[4]}
			BBX ${f[2]} ${#bmp[*]} ${xprop[5]} ${xprop[6]}
			BITMAP
		EOF
		for line in "${bmp[@]}"; do
			print $line
		done
		print ENDCHAR
		let ++numchar
	done >"$T"
	Fcomm+=("${last[@]}")
	print CHARS $((numchar))
	cat "$T"
	rm -f "$T"
else
	print CHARS $((numchar))
	for x in ${!Gdata[*]}; do
		IFS=$'\n'
		set -A xcomm -- ${Gcomm[x]}
		IFS=$' \t\n'
		for line in "${xcomm[@]}"; do
			print -r -- "COMMENT${line#\'}"
		done
		set -A xprop -- ${Gprop[x]}
		set -A f -- ${Gdata[x]}
		IFS=:
		set -A bmp -- ${f[3]}
		IFS=$' \t\n'
		typeset -Uui16 -Z7 ch=16#${f[1]}
		cat <<-EOF
			STARTCHAR ${f[4]:-uni${ch#16#}}
			ENCODING $((ch))
			SWIDTH ${xprop[1]} ${xprop[2]}
			DWIDTH ${xprop[3]} ${xprop[4]}
			BBX ${f[2]} ${#bmp[*]} ${xprop[5]} ${xprop[6]}
			BITMAP
		EOF
		for line in "${bmp[@]}"; do
			print $line
		done
		print ENDCHAR
	done
fi
for line in "${Fcomm[@]}"; do
	print -r -- "COMMENT${line#\'}"
done
print ENDFONT
exit 0
