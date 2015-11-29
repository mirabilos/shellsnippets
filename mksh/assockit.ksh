# $MirOS: contrib/hosted/tg/assockit.ksh,v 1.7 2015/11/29 20:24:19 tg Exp $
# -*- mode: sh -*-
#-
# Copyright © 2011, 2013, 2015
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
#-
# Associative, multi-dimensional arrays in Pure mksh™ (no exec!)
#-
# An item in an assockit array has the following properties:
# – the base-identifier of the shell array it’s in
# – the index into the shell array it’s in
# – an entry called flags
#   • data type: ASSO_{VAL,STR,INT,REAL,BOOL,NULL,AIDX,AASS}
# – an entry called key
# – an entry called value, unless NULL/AIDX/AASS
# Shell array paths are constructed like this:
# { 'foo': [ { 'baz': 123 } ] } named 'test' becomes:
# ‣ root-level lookup
#   – Asso__f[16#AE0C1A48] = ASSO_AASS | ASSO_ISSET|ASSO_ALLOC
#   – Asso__k[16#AE0C1A48] = 'test' (hash: AE0C1A48)
# ‣ Asso_AE0C1A48 = top-level
#   – Asso_AE0C1A48_f[16#BF959A6E] = ASSO_AIDX | ASSO_ISSET|ASSO_ALLOC
#   – Asso_AE0C1A48_k[16#BF959A6E] = 'foo' (hash: BF959A6E)
# ‣ Asso_AE0C1A48BF959A6E = next-level
#   – Asso_AE0C1A48BF959A6E_f[0] = ASSO_AASS | ASSO_ISSET|ASSO_ALLOC
#   – Asso_AE0C1A48BF959A6E_k[0] = 0
# ‣ Asso_AE0C1A48BF959A6E00000000 = last-level (below FOO)
#   – FOO_f[16#57F1BA9A] = ASSO_INT | ASSO_ISSET|ASSO_ALLOC
#   – FOO_k[16#57F1BA9A] = 'baz' (hash: 57F1BA9A)
#   – FOO_v[16#57F1BA9A] = 123
# When assigning a value, by default, the type of the
# intermediates is set to ASSO_AASS unless it already
# is ASSO_AIDX; the type of the terminals is ASSO_VAL
# unless it’s ASSO_{STR,INT,REAL,BOOL,NULL} before.

# check prerequisites
asso_x=${KSH_VERSION#????MIRBSD KSH R}
asso_x=${asso_x%% *}
if [[ $asso_x != +([0-9]) ]] || (( asso_x < 40 )); then
	print -u2 'assockit.ksh: need at least mksh R40'
	exit 1
fi

# set up variables
typeset -Uui16 -Z11 asso_h=0 asso_f=0 asso_k=0
typeset asso_b=""
set -A asso_y
set -A Asso__f
set -A Asso__k

# define constants
typeset -Uui16 -Z11 -r ASSO_VAL=2#000		# type: any Korn Shell scalar
typeset -Uui16 -Z11 -r ASSO_STR=2#001		# type: string
typeset -Uui16 -Z11 -r ASSO_INT=2#010		# type: integral
typeset -Uui16 -Z11 -r ASSO_REAL=2#011		# type: JSON float (string)
typeset -Uui16 -Z11 -r ASSO_BOOL=2#100		# type: JSON "true" / "false"
typeset -Uui16 -Z11 -r ASSO_NULL=2#101		# type: JSON "null"
typeset -Uui16 -Z11 -r ASSO_AIDX=2#110		# type: indexed array
typeset -Uui16 -Z11 -r ASSO_AASS=2#111		# type: associative array
typeset -Uui16 -Z11 -r ASSO_MASK_ARR=2#110	# bitmask for array type
typeset -Uui16 -Z11 -r ASSO_MASK_TYPE=2#111	# bitmask for type
typeset -Uui16 -Z11 -r ASSO_ISSET=16#40000000	# element is set
typeset -Uui16 -Z11 -r ASSO_ALLOC=16#80000000	# ksh element is set

# notes:
# – the code assumes ASSO_VAL=0 < all scalar types with value \
#   < ASSO_NULL < all array types

# public functions

# set a value
# example: asso_setv 123 'test' 'foo' 0 'baz'
function asso_setv {
	if (( $# < 2 )); then
		print -u2 'assockit.ksh: syntax: asso_setv value key [key ...]'
		return 2
	fi
	local _v=$1 _f _i
	shift

	# look up the item, creating paths as needed
	asso__lookup 1 "$@"
	# if it’s an array, free that recursively
	if (( ((_f = asso_f) & ASSO_MASK_ARR) == ASSO_MASK_ARR )); then
		asso__r_free 1
		(( _f &= ~ASSO_MASK_TYPE ))
	fi
	# if it’s got a type, check for a match
	if (( _i = (_f & ASSO_MASK_TYPE) )); then
		asso__typeck $_i "$_v" || (( _f &= ~ASSO_MASK_TYPE ))
	fi
	# set the new flags and value
	asso__r_setfv $_f "$_v"
}

# get the flags of an item, or return 1 if not set
# result is in the global variable asso_f
function asso_isset {
	if (( $# < 1 )); then
		print -u2 'assockit.ksh: syntax: asso_isset key [key ...]'
		return 2
	fi

	asso__lookup 0 "$@"
}

# get the type of an item (return 1 if unset, 2 if error)
# example: x=$(asso_gett 'test' 'foo' 0 'baz') => $((ASSO_VAL))
function asso_gett {
	asso_isset "$@" || return
	print -n -- $((asso_f & ASSO_MASK_TYPE))
}

# get the value of an item (return 1 if unset, 2 if error)
# example: x=$(asso_getv 'test' 'foo' 0 'baz') => 123
function asso_getv {
	asso_loadv "$@" || return
	print -nr -- "$asso_x"
}

# get the value of an item, but result is in the global variable asso_x
function asso_loadv {
	if (( $# < 1 )); then
		print -u2 'assockit.ksh: syntax: asso_loadv key [key ...]'
		return 2
	fi

	asso__lookup 2 "$@" || return 1
	if (( (asso_f & ASSO_MASK_TYPE) < ASSO_NULL )); then
		nameref _Av=${asso_b}_v
		asso_x=${_Av[asso_k]}
	else
		asso_x=""
	fi
}

# get all set keys of an item of array type (return 1 if no array)
# result is in the global variable asso_y
function asso_loadk {
	if (( $# < 1 )); then
		print -u2 'assockit.ksh: syntax: asso_loadk key [key ...]'
		return 2
	fi

	set -A asso_y
	asso__lookup 0 "$@" || return 1
	(( (asso_f & ASSO_MASK_ARR) == ASSO_MASK_ARR )) || return 1
	nameref _keys=${asso_b}${asso_k#16#}_k
	set -sA asso_y -- "${_keys[@]}"
}

# set a string value
# example: asso_sets 'abc' 'test' 'foo' 0 'baz'
function asso_sets {
	if (( $# < 2 )); then
		print -u2 'assockit.ksh: syntax: asso_sets value key [key ...]'
		return 2
	fi

	asso__settv $ASSO_STR "$@"
}

# set an integral value
# example: asso_seti 123 'test' 'foo' 0 'baz'
function asso_seti {
	if (( $# < 2 )); then
		print -u2 'assockit.ksh: syntax: asso_seti value key [key ...]'
		return 2
	fi

	if ! asso__typeck $ASSO_INT "$1"; then
		print -u2 "assockit.ksh: not an integer: '$1'"
		return 1
	fi
	asso__settv $ASSO_INT "$@"
}

# set a floating point (real) value
# example: asso_setr -123.45e+67 'test' 'foo' 0 'baz'
function asso_setr {
	if (( $# < 2 )); then
		print -u2 'assockit.ksh: syntax: asso_setr value key [key ...]'
		return 2
	fi

	if ! asso__typeck $ASSO_REAL "$1"; then
		print -u2 "assockit.ksh: not a real: '$1'"
		return 1
	fi
	asso__settv $ASSO_REAL "$@"
}

# set a boolean value
# example: asso_setb t 'test' 'foo' 0 'baz'
function asso_setb {
	if (( $# < 2 )); then
		print -u2 'assockit.ksh: syntax: asso_setb value key [key ...]'
		return 2
	fi

	if ! asso__typeck $ASSO_BOOL "$1"; then
		print -u2 "assockit.ksh: not a truth value: '$1'"
		return 1
	fi
	asso__settv $ASSO_BOOL "$@"
}

# set value to null
# example: asso_setnull 'test' 'foo' 0 'baz'
function asso_setnull {
	if (( $# < 1 )); then
		print -u2 'assockit.ksh: syntax: asso_setnull key [key ...]'
		return 2
	fi

	asso__settv $ASSO_NULL 0 "$@"
}

# set type and scalar value
# example: asso_settv $ASSO_INT 123 'test' 'foo' 0 'baz'
function asso_settv {
	if (( $# < 3 )) || ! asso__intck "$1" || \
	    (( $1 != ($1 & ASSO_MASK_TYPE) )); then
		print -u2 'assockit.ksh: syntax: asso_settv type value key...'
		return 2
	fi

	if ! asso__typeck $1 "$2"; then
		print -u2 "assockit.ksh: wrong type scalar: '$2'"
		return 1
	fi
	asso__settv "$@"
}

# unset value
# example: asso_unset 'test' 'foo' 0 'baz'
function asso_unset {
	if (( $# < 1 )); then
		print -u2 'assockit.ksh: syntax: asso_unset key [key ...]'
		return 2
	fi

	# look up the item, not creating paths
	if asso__lookup 0 "$@"; then
		# free the item recursively
		asso__r_free 0
	fi
	return 0
}

# make an entry into an indexed array
# from scalar => data into [0]
# from associative array => data lost
function asso_setidx {
	if (( $# < 1 )); then
		print -u2 'assockit.ksh: syntax: asso_setidx key [key ...]'
		return 2
	fi

	local _f _v

	asso__lookup 1 "$@"
	if (( ((_f = asso_f) & ASSO_MASK_ARR) != ASSO_MASK_ARR )); then
		nameref _Av=${asso_b}_v
		_v=${_Av[asso_k]}
	elif (( (_f & ASSO_MASK_TYPE) == ASSO_AIDX )); then
		return 0
	fi
	asso__r_free 1
	asso__r_setf $ASSO_AIDX
	if (( (_f & ASSO_MASK_ARR) != ASSO_MASK_ARR )); then
		asso__lookup 1 "$@" 0
		asso__r_setfv $_f "$_v"
	fi
}

# make an entry into an associative array
# from scalar => data lost
# from indexed array => data converted
function asso_setasso {
	if (( $# < 1 )); then
		print -u2 'assockit.ksh: syntax: asso_setasso key [key ...]'
		return 2
	fi

	local _f

	asso__lookup 1 "$@"
	if (( ((_f = asso_f) & ASSO_MASK_ARR) != ASSO_MASK_ARR )); then
		asso__r_free 1
		asso__r_setf $ASSO_AASS
	elif (( (_f & ASSO_MASK_TYPE) == ASSO_AIDX )); then
		asso__r_idx2ass
	fi
	return 0
}

# private functions

# set type and scalar value, unchecked
function asso__settv {
	local _t=$1 _v=$2 _f
	shift; shift

	# look up the item, creating paths as needed
	asso__lookup 1 "$@"
	# if it’s an array, free that recursively
	if (( ((_f = asso_f) & ASSO_MASK_ARR) == ASSO_MASK_ARR )); then
		asso__r_free 1
	fi
	(( _f = (_f & ~ASSO_MASK_TYPE) | _t ))
	# set the new flags and value
	asso__r_setfv $_f "$_v"
}

# check if this is a numeric (integral) value (0=ok 1=error)
function asso__intck {
	local _v=$1

	[[ $_v = ?(+([0-9])'#')+([0-9a-zA-Z]) ]] || return 2
	{ : $((_v)) ; } 2>&-
}

# map a boolean value (0=false 1=true 2=error)
function asso__boolmap {
	local _v=$1

	if asso__intck "$_v"; then
		(( _v == 0 ))
		return
	fi
	case $_v {
	([Tt]?([Rr][Uu][Ee])|[Yy]?([Ee][Ss])|[Oo][NnKk])
		return 1 ;;
	([Ff]?([Aa][Ll][Ss][Ee])|[Nn]?([Oo])|[Oo][Ff][Ff])
		return 0 ;;
	}
	return 2
}

# check if the type matches the value (0=ok 1=error)
function asso__typeck {
	if (( $# != 2 )); then
		print -u2 'assockit.ksh: syntax: asso__typeck type value'
		return 2
	fi
	local _t=$1 _v=$2
	(( _t == ASSO_VAL || _t == ASSO_STR || _t == ASSO_NULL )) && return 0
	if (( _t == ASSO_INT )); then
		asso__intck "$_v"
		return
	fi
	if (( _t == ASSO_BOOL )); then
		asso__boolmap "$_v"
		(( $? < 2 ))
		return
	fi
	(( (_t & ASSO_MASK_ARR) == ASSO_MASK_ARR )) && return 1
	# ASSO_REAL
	[[ $_v = ?(-)@(0|[1-9]*([0-9]))?(.+([0-9]))?([Ee]?([+-])+([0-9])) ]]
}

# look up an item ($1 &1: create paths as necessary; &2: only scalar values)
function asso__lookup {
	local _c=$1 _k _n _r
	shift

	_n=Asso_
	_r=0
	asso_f=$ASSO_AASS
	for _k in "$@"; do
		if (( _r || (asso_f & ASSO_MASK_ARR) != ASSO_MASK_ARR )); then
			(( _r )) || asso__r_free 1
			asso__r_setf $ASSO_AASS
		elif (( (asso_f & ASSO_MASK_TYPE) == ASSO_AIDX )); then
			asso__intck "$_k" || asso__r_idx2ass
		fi
		asso_b=$_n
		asso__lookup_once "$_k"
		if (( _r = $? )); then
			# not found. not create?
			(( _c & 1 )) || return 1
			asso__r_setk "$_k"
		fi
		_n=$_n${asso_k#16#}
	done
	(( _c & 2 )) || return 0
	# assume $1==3 does not happen
	while (( (asso_f & ASSO_MASK_ARR) == ASSO_MASK_ARR )); do
		asso_b=$_n
		asso__lookup_once 0 || return 1
		_n=$_n${asso_k#16#}
	done
}

# set flags for asso_b[asso_k] and update asso_f
function asso__r_setf {
	nameref _Af=${asso_b}_f

	asso_f=$(($1 | ASSO_ISSET | ASSO_ALLOC))
	_Af[asso_k]=$asso_f
}

# set flags and value for asso_b[asso_k] and update asso_f
function asso__r_setfv {
	nameref _Af=${asso_b}_f
	nameref _Av=${asso_b}_v

	_Av[asso_k]=$2
	asso_f=$(($1 | ASSO_ISSET | ASSO_ALLOC))
	_Af[asso_k]=$asso_f
}

# set key for not yet existing asso_b[asso_k] and update asso_f
function asso__r_setk {
	nameref _Af=${asso_b}_f
	nameref _Ak=${asso_b}_k

	_Ak[asso_k]=$1
	asso_f=$((ASSO_ALLOC))
	_Af[asso_k]=$asso_f
}

# in asso_b of type asso_f look up element $1
# set its asso_f and asso_k or return 1 when not found
function asso__lookup_once {
	local _e=$1 _seth=0
	nameref _Af=${asso_b}_f
	nameref _Ak=${asso_b}_k

	if (( (asso_f & ASSO_MASK_TYPE) == ASSO_AIDX )); then
		asso_k=$((_e))
	else
		asso_k=16#${_e@#}
		while :; do
			asso_f=${_Af[asso_k]}
			(( asso_f & ASSO_ALLOC )) || break
			if (( !(asso_f & ASSO_ISSET) )); then
				if (( !_seth )); then
					# save index
					asso_h=$asso_k
					_seth=1
				fi
				(( --asso_k ))
				continue
			fi
			[[ ${_Ak[asso_k]} = "$_e" ]] && break
			# iterate
			(( --asso_k ))
		done
	fi
	asso_f=${_Af[asso_k]}
	# found?
	(( asso_f & ASSO_ISSET )) && return 0
	# not found.
	if (( _seth )); then
		# when allocating, use this one instead
		asso_k=$asso_h
	fi
	return 1
}

# free the currently selected asso_b[asso_k] recursively
function asso__r_free {
	local _keepkey=$1
	nameref _Af=${asso_b}_f

	asso_f=${_Af[asso_k]}
	(( asso_f & ASSO_ALLOC )) || return
	if (( asso_f & ASSO_ISSET )); then
		if (( (asso_f & ASSO_MASK_ARR) == ASSO_MASK_ARR )); then
			local _ob=$asso_b _ok=$asso_k
			asso_b=$asso_b${asso_k#16#}
			nameref _s=${asso_b}_f
			for asso_k in "${!_s[@]}"; do
				asso__r_free
			done
			eval unset ${asso_b}_f ${asso_b}_k ${asso_b}_v
			asso_b=$_ob asso_k=$_ok
		fi
		eval unset $asso_b'_v[asso_k]'
		(( _keepkey )) || eval unset $asso_b'_k[asso_k]'
	fi
	asso_f=$((ASSO_ALLOC))
	_Af[asso_k]=$asso_f
}

# make indexed asso_b[asso_k] into associative array
function asso__r_idx2ass {
	print -u2 'assockit.ksh: warning: asso__r_idx2ass not implemented'
	print -u2 'assockit.ksh: warning: data will be lost'
	asso__r_free
	asso__r_setf $ASSO_AASS
}
