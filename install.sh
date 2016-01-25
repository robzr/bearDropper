#!/bin/sh
# https://github.com/robzr/bearDropper
# bearDropper install script - @robzr

[ -f /etc/init.d/bearDropper ] && /etc/init.d/bearDropper stop
wget -O /etc/init.d/bearDropper http://cdn.rawgit.com/robzr/bearDropper/master/src/init.d/bearDropper 
wget -O /etc/config/bearDropper http://cdn.rawgit.com/robzr/bearDropper/master/src/config/bearDropper
wget -O /usr/sbin/bearDropper http://cdn.rawgit.com/robzr/bearDropper/master/bearDropper
chmod 755 /usr/sbin/bearDropper /etc/init.d/bearDropper
/usr/sbin/bearDropper -m entire -f stdout
/etc/init.d/bearDropper enable
/etc/init.d/bearDropper start
