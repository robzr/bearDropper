bearDropper: bearDropper.sh bddb.sh
	sed -n '1,/_LOAD_MEAT_/p' bearDropper.sh | fgrep -v _MEAT_ > bearDropper
	sed -n '/_BEGIN_MEAT_/,/_END_MEAT_/p' bddb.sh | fgrep -v _MEAT_ >> bearDropper
	sed -n '/_LOAD_MEAT_/,$$p' bearDropper.sh | fgrep -v _MEAT_ >> bearDropper
	chmod 755 bearDropper

clean:
	rm bearDropper
