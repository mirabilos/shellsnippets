#!/usr/bin/make -f
#-
# Application demonstration for GNU gettext in shell scripts.
# Copyright © 2015 mirabilos Ⓕ MirBSD or CC0

P=itest
V=1.0
B=t.glaser@tarent.de
D=itest

all:

clean:
	rm -rf mo po/*.pot po/*~

all: update-translations install-translations

update-translations:
	-rm -f po/$D.pot
	find * -name \*.sh | xargs perl -pi -e 's!^(TEXTDOMAIN=).*$$!$$1$D!'
	find * -name \*.sh | xgettext -f - -d $D -o po/$D.pot \
	    -L Shell --from-code=UTF-8 --check=ellipsis-unicode \
	    --check=space-ellipsis --check=quote-unicode \
	    --sentence-end=single-space -k_ -F --foreign-user \
	    --package-name=$P --package-version=$V \
	    --msgid-bugs-address=$B
	set -e; for x in po/*.po; do \
		msgmerge -U "$$x" po/$D.pot; \
	done

install-translations:
	rm -rf mo
	set -e; for x in po/*.po; do \
		l=$${x##*/}; l=$${l%.po}; \
		mkdir -p "mo/$$l/LC_MESSAGES"; \
		msgfmt -o "mo/$$l/LC_MESSAGES/$D.mo" "$$x"; \
	done

.PHONY: all clean update-translations install-translations
