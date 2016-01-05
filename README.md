Outer while() loop;
  (default) a single full run (default)
     -or-
  -f runs through entire log, follows at the end indefinitely (same as logread)
     follow mode will have the side effects of limiting how often expired entries can be purged from the firewall
     because it is now event based
  -l 999 optional override length of history (same as logread)

based on logread -f output that matches the (uci activation pattern)

(time counter 0)
 Loops through logread with no filtering (logread [-f] )
(today flag is set) (determine $today; logread [-f] | fgrep $today)
 - if the today variable changes, we need to restart the logread | fgrep $today to prevent a stale grep term.  So once in follow mode we need to check
 for a clock date change every line.
(time counter > 0) (determine
 Logic can be used to make the logread command based on simple grep (day, possibly even hours?) if it is not going to follow (grep would void following once the date changes)
 Loops though remaining lines, running date conversion/comparison until it gets to the current time threshhold
 When the current time is met once, we can move into fast forwarding disabled (0) to prevent further logic comparisons, since it is guaranteed to be at least as new

create in memory a quasi-hash like:
 $_BD123.123.123.123=12342352,3248923,323940234,23423423

loop through variables periodically, quasi-array doing everything simultaneously
 - remove expired timestamps
 - remove firewall entry(ies) if necessary
 - add firewall entry(ies) if necessary

use a signal to

Loops through logread, fast fowarding until one of the following conditions is met:

 - ffd disabled (time counter == 0) (default mode)
 - today grep string matches (-t today)
   - once this condition is met once, it doesn't need to be checked any longer
 - date command is run and seconds are within threshold (-t <timeString>)
   - once this condition is met once, it doesn't need to be checked any longer

1) Uses logread circular buffer as only reference to be lightweight footprint,
  which could be increased for longer history.

2)
