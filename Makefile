CC = g++
CFLAGS ?= -O3

PREFIX ?= /usr/local
INSTALLDIR ?= $(PREFIX)/bin
MANDIR ?= $(PREFIX)/share/man/man1

#DESTDIR ?= 

SRC = src
DOC = doc
BUILD = build

$(shell mkdir -p $(BUILD))

default: mkgig

all:	mkgig manpage

mkgig: $(SRC)/mkgig.cpp
	@echo "checking prerequisites..."
	which $(CC)
	which pkg-config
	pkg-config --exists gig
	pkg-config --exists sndfile
	@echo "ok."

	$(CC) -o mkgig $(SRC)/mkgig.cpp $(CFLAGS) `pkg-config --cflags --libs gig sndfile`

	#if the mkgig binary can't find libgig.so for any reason, set LD_RUN_PATH in shell, make clean && make
	#export LD_RUN_PATH=/usr/local/lib/libgig

manpage:
	@echo "checking prerequisites..."
	which asciidoc \
	&& asciidoc --filter list | grep graphviz \
	&& which a2x \
	&& which gzip \
	&& which dblatex
	@echo "ok."
	@echo ""
	@echo "creating manpage with asciidoc"
	@echo "------------------------------"
	@echo ""

	#man
	a2x --doctype manpage --format manpage $(DOC)/mkgig.man.asciidoc
	gzip -9 -f $(DOC)/mkgig.1

	#html
	asciidoc $(DOC)/mkgig.man.asciidoc

	#pdf, xml (docbook)
	a2x --format pdf --keep-artifacts --dblatex-opts " -P doc.layout=\"coverpage mainmatter\" -P doc.publisher.show=0" $(DOC)/mkgig.man.asciidoc

	mv $(DOC)/mkgig.man.pdf $(DOC)/mkgig.pdf
	mv $(DOC)/mkgig.man.xml $(DOC)/mkgig.xml
	mv $(DOC)/mkgig.man.html $(DOC)/mkgig.html

	@echo ""
	@echo "done."
	@echo ""

install:
	$(shell mkdir -p $(DESTDIR)$(INSTALLDIR))
	$(shell mkdir -p $(DESTDIR)$(MANDIR))
	install -m755 mkgig $(DESTDIR)$(INSTALLDIR)/
	install -m755 $(SRC)/gigload.sh $(DESTDIR)$(INSTALLDIR)/gigload
	install -m644 $(DOC)/mkgig.1.gz $(DESTDIR)$(MANDIR)/

uninstall:
	-rm -f $(DESTDIR)$(INSTALLDIR)/mkgig
	-rm -f $(DESTDIR)$(INSTALLDIR)/gigload
	-rm -f $(DESTDIR)$(MANDIR)/mkgig.1.gz

clean:
	-rm mkgig
	-rm -rf $(BUILD)
