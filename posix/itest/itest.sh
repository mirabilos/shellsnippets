#!/bin/sh
# -*- mode: sh -*-
#-
# Application demonstration for GNU gettext in shell scripts.
# Copyright © 2015 mirabilos Ⓕ MirBSD or CC0
#-
# Call with, e.g: $ LC_ALL=de_DE.UTF-8 sh itest.sh x y z

. gettext.sh
TEXTDOMAIN=itest
TEXTDOMAINDIR=$(dirname "$0")/mo
export TEXTDOMAIN TEXTDOMAINDIR

test -z "$KSH_VERSION" || echo='print -r --'
_() {
	$echo "$(eval_gettext "$1")"
}

echo Internationalised program test: language:
locale
echo

_ "Hello, World!"
_ "Five O’Clock is tea time!"

nargs=$#
$echo "$(eval_ngettext "This script was called with one argument." \
    "This script was called with \${nargs} arguments." $nargs)"
