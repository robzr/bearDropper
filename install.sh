#!/bin/sh
# https://github.com/robzr/bearDropper
# bearDropper install script - @robzr

download_github_file () {
  local output="$1" stub="$2"
  local https_url="https://raw.githubusercontent.com/$stub"
  local ca_bundle='/etc/ssl/certs/ca-certificates.crt'
  if [[ -f "$ca_bundle" ]]; then
    if [[ -x "$(command -v curl)" ]]; then
      curl -Ls --cacert "$ca_bundle" --output "$output" -- "$https_url"; return $?
    elif ldd "$(which wget)" | grep -qE 'tls|ssl|crypto' || \
         ldd "$(which wget)" | grep -q 'uclient' && test -f /lib/libustream-ssl.so; then
      wget -q --ca-certificate "$ca_bundle" -O "$output" -- "$https_url"; return $?
    fi
  else
    # rawgit stopped providing HTTP downloads
    return 1
  fi
}

if [ -f /etc/init.d/bearDropper ] ; then
  echo Detected previous version of bearDropper - stopping
  /etc/init.d/bearDropper stop
fi
echo -e 'Retrieving and installing latest version'
(
  download_github_file /etc/init.d/bearDropper robzr/bearDropper/master/src/init.d/bearDropper &&
  download_github_file /etc/config/bearDropper robzr/bearDropper/master/src/config/bearDropper &&
  download_github_file /usr/sbin/bearDropper robzr/bearDropper/master/bearDropper
) || { echo 'Failed to download script' 1>&2; exit 1; }
chmod 755 /usr/sbin/bearDropper /etc/init.d/bearDropper
echo -e 'Processing historical log data (this can take a while)'
/usr/sbin/bearDropper -m entire -f stdout
echo -e 'Starting background process'
/etc/init.d/bearDropper enable
/etc/init.d/bearDropper start

dropbear_count=$(uci show dropbear | grep -c =dropbear)
dropbear_count=$((dropbear_count - 1))
for instance in $(seq 0 $dropbear_count); do
  dropbear_verbose=$(uci -q get dropbear.@dropbear[$instance].verbose || echo 0)
  if [ $dropbear_verbose -eq 0 ]; then
    uci set dropbear.@dropbear[$instance].verbose=1 
    dropbear_conf_updated=1
  fi
done
if [ $dropbear_conf_updated ]; then
  uci commit
  echo "Verbose logging was configured for dropbear. Please restart the service to enable this change."
fi
