#!/bin/bash

/usr/bin/avahi-publish -a -R sonarr.local  $(avahi-resolve -4 -n media-pc.local | cut -f 2) &
/usr/bin/avahi-publish -a -R radarr.local  $(avahi-resolve -4 -n media-pc.local | cut -f 2) &
/usr/bin/avahi-publish -a -R bazarr.local  $(avahi-resolve -4 -n media-pc.local | cut -f 2) &
/usr/bin/avahi-publish -a -R prowlarr.local  $(avahi-resolve -4 -n media-pc.local | cut -f 2) &
/usr/bin/avahi-publish -a -R catalog.local  $(avahi-resolve -4 -n media-pc.local | cut -f 2) &
/usr/bin/avahi-publish -a -R tv.local  $(avahi-resolve -4 -n media-pc.local | cut -f 2) &
/usr/bin/avahi-publish -a -R qbittorrent.local  $(avahi-resolve -4 -n media-pc.local | cut -f 2) &
/usr/bin/avahi-publish -a -R sabnzbd.local  $(avahi-resolve -4 -n media-pc.local | cut -f 2) &