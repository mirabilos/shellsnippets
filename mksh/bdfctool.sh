#!/bin/mksh
# $MirOS: X11/extras/bdfctool/bdfctool.sh,v 1.12 2013/05/17 21:51:40 tg Exp $
#-
# Copyright © 2012, 2013
#	Thorsten Glaser <tg@mirbsd.org>
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
while getopts "acdeFh" ch; do
	case $ch {
	(a) uascii=1 ;;
	(+a) uascii=0 ;;
	(c|d|e|+e) mode=$ch ;;
	(F) ufast=1 ;;
	(+F) ufast=0 ;;
	(h) mode=$ch ;;
	(*) mode= ;;
	}
done
shift $((OPTIND - 1))
(( $# )) && mode=

if [[ $mode = ?(h) ]] || [[ $mode != e && $uascii != -1 ]] || \
    [[ $mode != d && $ufast != 0 ]]; then
	print -ru2 "Usage: ${0##*/} -c | -d [-F] | -e [-a] | +e"
	[[ $mode = h ]]; exit $?
fi

lno=0
if [[ $mode = e ]]; then
	if (( uascii == 1 )); then
		set -A BITv -- '.' '#' '|'
	else
		set -A BITv -- '　' '䷀' '▌'
	fi
	while IFS= read -r line; do
		(( ++lno ))
		if [[ $line = 'e '* ]]; then
			set -A f -- $line
			i=${f[3]}
			print -r -- "$line"
			while (( i-- )); do
				if IFS= read -r line; then
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
		if (( (w = f[2]) > 32 || w < 1 )); then
			print -ru2 "E: width ${f[2]} not in 1‥32 at line $lno"
			exit 2
		fi
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
	while IFS= read -r line; do
		(( ++lno ))
		if [[ $line = C ]]; then
			Fprop+=("${last[@]}")
			state=1
			return
		elif [[ $line = '=bdfc 1' ]]; then
			continue
		fi
		last+=("$line")
		[[ $line = \' || $line = "' "* ]] && continue
		if [[ $line = h* ]]; then
			Fhead+=("${last[@]}")
		elif [[ $line = p* ]]; then
			Fprop+=("${last[@]}")
		else
			print -ru2 "E: invalid line #$lno: '$line'"
			exit 2
		fi
		set -A last
	done
	Fprop+=("${last[@]}")
	state=2
}

function parse_bdfc_edit {
	local w shiftbits uw line r i

	if (( (w = f[2]) <= 8 )); then
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

	if (( (i = f[3]) < 1 || i > 999 )); then
		print -ru2 "E: nonsensical number of lines '${f[3]}' in" \
		    "line $lno, U+${ch#16#}"
		exit 2
	fi

	while (( i-- )); do
		if ! IFS= read -r line; then
			print -ru2 "E: Unexpected end of 'e' command" \
			    "at line $lno, U+${ch#16#}"
			exit 2
		fi
		(( ++lno ))
		linx=${line//　/.}
		linx=${linx//䷀/#}
		linx=${linx//▌/|}
		linx=${linx//[ .]/0}
		linx=${linx//[#*]/1}
		if [[ $linx != +([01])'|' || ${#linx} != $((w + 1)) ]]; then
			print -ru2 "E: U+${ch#16#} (line #$lno) bitmap line" \
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
	while IFS= read -r line; do
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
			continue
		fi
		if [[ ${f[0]} != [ce] ]]; then
			print -ru2 "E: invalid line #$lno: '$line'"
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
		if (( ${#f[*]} < 4 || ${#f[*]} > 5 )); then
			print -ru2 "E: invalid number of fields on line $lno" \
			    "at U+${ch#16#}: ${#f[*]}: '$line'"
			exit 2
		fi
		if (( f[2] < 1 || f[2] > 32 )); then
			print -ru2 "E: width ${f[2]} not in 1‥32 at line $lno"
			exit 2
		fi
		[[ ${f[4]} = "uni${ch#16#}" ]] && unset f[4]
		if [[ ${f[0]} = e ]]; then
			parse_bdfc_edit
		else
			if (( f[2] <= 8 )); then
				x='+([0-9A-F][0-9A-F]:)'
			elif (( f[2] <= 16 )); then
				x='+([0-9A-F][0-9A-F][0-9A-F][0-9A-F]:)'
			elif (( f[2] <= 24 )); then
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
	while IFS= read -r line; do
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
		(*)
			Fhead+=("h$line")
			;;
		}
	done
	set -A f -- $line
	numprop=${f[1]}
	while IFS= read -r line; do
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
	while IFS= read -r line; do
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
	while IFS= read -r line; do
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
			[[ ${f[4]} = "uni${ch#16#}" ]] && unset f[4]
			if (( f[2] <= 8 )); then
				ck='[0-9A-F][0-9A-F]'
			elif (( f[2] <= 16 )); then
				ck='[0-9A-F][0-9A-F][0-9A-F][0-9A-F]'
			elif (( f[2] <= 24 )); then
				ck='[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]'
			else
				ck='[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]'
			fi
			if (( (numlines = cb[2]) )); then
				bmps=
				typeset -u linu
				while IFS= read -r linu; do
					(( ++lno ))
					if eval [[ '$linu' != "$ck" ]]; then
						print -ru2 "E: invalid hex encoding" \
						    "for U+${ch#16#} (dec. $((ch)))" \
						    "on line $lno: '$linu'"
						exit 2
					fi
					bmps+=$linu:
					(( --numlines )) || break
				done
				f[3]=${bmps%:}
			else
				f[2]=1
				f[3]=00
			fi
			if ! IFS= read -r line || [[ $line != ENDCHAR ]]; then
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
	while IFS= read -r line; do
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

if [[ $mode = c ]]; then
	if ! IFS= read -r line; then
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
	while IFS= read -r line; do
		(( ++lno ))
		if [[ $line = \' || $line = "' "* ]]; then
			print -r -- "$line"
			continue
		fi
		set -A f -- $line
		if [[ ${f[0]} != [ce] ]]; then
			print -ru2 "E: invalid line #$lno: '$line'"
			exit 2
		fi
		if [[ ${f[1]} != [0-9A-F][0-9A-F][0-9A-F][0-9A-F] ]]; then
			print -ru2 "E: invalid encoding '${f[1]}' at line $lno"
			exit 2
		fi
		typeset -Uui16 -Z7 ch=16#${f[1]}
		if (( ${#f[*]} < 4 || ${#f[*]} > 5 )); then
			print -ru2 "E: invalid number of fields on line $lno" \
			    "at U+${ch#16#}: ${#f[*]}: '$line'"
			exit 2
		fi
		if (( f[2] < 1 || f[2] > 32 )); then
			print -ru2 "E: width ${f[2]} not in 1‥32 at line $lno"
			exit 2
		fi
		[[ ${f[4]} = "uni${ch#16#}" ]] && unset f[4]
		if [[ ${f[0]} = e ]]; then
			parse_bdfc_edit
		else
			if (( f[2] <= 8 )); then
				x='+([0-9A-F][0-9A-F]:)'
			elif (( f[2] <= 16 )); then
				x='+([0-9A-F][0-9A-F][0-9A-F][0-9A-F]:)'
			elif (( f[2] <= 24 )); then
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

if ! IFS= read -r line; then
	print -ru2 "E: read error at BOF"
	exit 2
fi
lno=1
if [[ $line != '=bdfc 1' ]]; then
	print -ru2 "E: not bdfc at BOF: '$line'"
	exit 2
fi

if (( ufast )); then
	if ! T=$(mktemp /tmp/bdfctool.XXXXXXXXXX); then
		print -u2 E: cannot make temporary file
		exit 4
	fi
	# quickly parse bdfc header
	set -A last
	while IFS= read -r line; do
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
else
	# parse entire bdfc file into memory
	parse_bdfc
fi

# analyse data for BDF
numprop=0
for line in "${Fprop[@]}"; do
	[[ $line = p* ]] && let ++numprop
done
(( ufast )) || numchar=${#Gdata[*]}

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
	while IFS= read -r line; do
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
