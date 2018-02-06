
DCMP:=ldc
PREFIX:=/usr/local



.PHONY: all man install
all: bugd man

man: bugd.1

install: bugd man
	install -D -m 755 ./bugd $(PREFIX)/bin/
	install -D ./bugd.1 $(PREFIX)/man/man1/

bugd: bugd.d | doc/synopsis.txt doc/usage.txt
	$(DCMP) $^ -J.

bugd.1: bugd.1.template | doc/synopsis.txt doc/usage.txt
	./genman.sh


