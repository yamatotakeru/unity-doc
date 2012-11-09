all: srcen srcja

create-dirs:
	rm -rf wikicache

# source
srcen: create-dirs
	./GetSource.pl en http://docwiki.hq.unity3d.com -specific desktop -specific ios -specific android -specific u40 -specific jpn
	rm -rf wikicache

srcja: create-dirs
	./GetSource.pl ja http://docwiki.unity3d.co.jp -specific desktop -specific ios -specific android -specific u40 -specific jpn
	rm -rf wikicache
