#!/bin/sh
# https://github.com/robzr/bearDropper
# bearDropper install script - @robzr

if [ -f /etc/init.d/bearDropper ] ; then
  echo Detected previous version of bearDropper - stopping
  /etc/init.d/bearDropper stop
fi
echo -e 'Retrieving and installing latest version'
wget -qO /etc/init.d/bearDropper http://rawgit.com/robzr/bearDropper/master/src/init.d/bearDropper 
wget -qO /etc/config/bearDropper http://rawgit.com/robzr/bearDropper/master/src/config/bearDropper
wget -qO /usr/sbin/bearDropper http://rawgit.com/robzr/bearDropper/master/bearDropper
chmod 755 /usr/sbin/bearDropper /etc/init.d/bearDropper
echo -e 'Processing historical log data (this can take a while)'
/usr/sbin/bearDropper -m entire -f stdout
echo -e 'Starting background process'
/etc/init.d/bearDropper enable
/etc/init.d/bearDropper start
