# Introduction

#### Reasoning
This is intended to get you into the world of securing your own media, storing it on your own drives and streaming it to your own devices. This guide is loosely based off of [Jellyfin with UnRAID](https://flemmingss.com/a-minimal-configuration-step-by-step-guide-to-media-automation-in-unraid-using-radarr-sonarr-prowlarr-jellyfin-jellyseerr-and-qbittorrent/) which first got me into self-hosting. So big thanks to them - I liked their file structure and based mine largely on that.

It's also documentation intended for myself. Please bear that in mind - if you would have done things differently or it doesn't fit your exact usecase, please feel free to change it to your liking. If you notice any bad practises, you're welcome to let me know why it's bad and how to do it instead.

I will not go into how to make your server available publically through DynDNS and streaming remotely. I just don't think it fits in the scope of this guide.
However, if you are interested in doing that, please look into DuckDNS, port forwarding in your router and using Let's Encrypt certificates in Nginx Proxy Manager.

#### Disclaimer
**I do NOT condone piracy. Please make sure to only download media that isn't copyrighted or that you own the rights to.
Keep in mind that many movies and TV-shows are protected by copyright law, these may be illegal to download or share in many countries.
My clear recommendation is to stick to media where the creators have given their consent for downloading and sharing.**

The idea is to use free software only with a focus on using open source software whereever possible. 
There are many options like Proxmox, Unraid or even just Ubuntu Server. I chose to go with OpenMediaVault because I feel like it works well as remotely manageable server with a web GUI.

# Hardware

#### Reasoning
The way I see it, there are 2 routes to go with a low cost system before factoring in a storage solution. 
As this guide won't focus on storage solutions, it is up to you how you handle that. The hardware suggested may not be the best choice if you want a storage and media server all in one solution. It's purely intended to get you a transcoding capable media server.

If you are looking to build a NAS, homeserver or something more advanced, you may look into NAS cases from U NAS or Silverstone. They have some of the best I've found in my research.
I was personally running a SATA to eSATA adapter with an external IcyDock enclosure for a while - but YMMV.

#### Choices
The cheapest way to go is likely to buy an Optiplex 3070 with an i5 8400 or i8 9400. Do not buy F processors.
The integrated Intel HD graphics are really good for transcoding if you ever need it.

Alternatively, if pricing in your area doesn't match (here in Germany, those Optiplex SFF systems cost about 300€), you should look towards a barebones Optiplex 7020, 9020 or HP ProDesk 400 G1/G2.5.
These are all SFF systems that will take a Xeon E3 1220L v3, 1230L v3, 1240L v3 etc. They are low powered chips - but you can buy the regular ones (non-L) as well if power isn'ta concern.
Keep in mind, that these do not have integrated graphics and you'll need to factor in the cost of a low profile used Nvidia Quadro P400 for transcoding.

As SanDisk Cruzer 2.0 USB is generally advised to keep the OS on for most solutions. Any internal SSD can then be used for storage.

## Installation
Download [OpenMediaVault](https://www.openmediavault.org/) and BalenaEtcher to flash it onto a USB drive. Install the system on the SanDisk Cruzer USB (or a similar one you purchased). If you are struggling, I believe there are plenty of YouTube tutorials.

After installation, log into the server and type:
```
sudo apt update
sudo apt install net-tools
```

You can now use `ifconfig` to find the IP your server was assigned by your router and should then be able to access it via a browser on a different system as `http://<your-ip>`. I've found that sometimes there are issues with DNS, so going to the web GUI, Network, Interfaces and editing your ethernet connection to use 8.8.8.8 or 1.1.1.1 as your preferred DNS can help resolve that.

## Configuration
At this point, it's probably smart to switch to SSH and remote into your server. You can find the setup in the web GUI. 
Most people recommend installing the [omv-extras plugin](https://forum.openmediavault.org/index.php?thread/5549-omv-extras-org-plugin/). I would also recommend you install it. I've found installing Docker and running it from the CLI is not an issue, but this is certainly easier. It will add tons of options to plugins you can install via the web GUI.

I recommend the following plugins:
- compose (for Docker)
- flashmemory (to run your OS from a USB drive)
- filebrowser (a file browser)
- mergerfs (allows combining drives into a folder)

I will be using mergerfs to mount my drives (just 1 for the purpose of this tutorial) to a single folder that's going to work as the root point for all media handled in this tutorial. Going to Storage -> mergerfs, you can now create a new pool out of all your disks (or only some). You are, of course, free to run btrfs instead of EXT4 on your drives or run them in software RAID instead. It all depends on how important data integrity is to you - maybe RAID feels like a waste of space if you can redownload your collection at any point if a drive fails or maybe you have a NAS taking care of the storage part anyway. **So please don't treat this as a tutorial for managing your data. You still need to frequently back up the USB drive that your system is on.** 

For the sake of this tutorial, we will assume that you created a pool using mergerfs called "pool" out of all your drives. In the file-system, you can now access it via** `/srv/mergerfs/pool`. You can do this via the mergerfs navigation option in your web GUI.

If you wish to keep your config files (database, etc) for your containers in a separate folder where they can easily be backed up, you need to create a second mergerfs pool named config, mounting all of your drives again, but this time using the options `cache.files=partial,dropcacheonclose=true,category.create=mfs`. This is due to a bug explained [here](https://wiki.servarr.com/sonarr/faq#i-am-getting-an-error-database-disk-image-is-malformed).

You should also create a share under Storage -> Shared Folders. Call it `share_media` and use the newly created `pool` as your file system. Another one for our docker compose files should be called `docker`. Lastly, you create a share for your docker containers' config files called `appdata` **this one needs to be on your `config` pool - not `pool`**.
You should now have 2 mergerfs mounts and 3 shares.
The docker-compose files attached ASSUME this path. Be sure to change it if you didn't follow this part.

Note: When creating those folders ('appdata', 'share_media'), they will belong to `root`. By default, they will not be accessible. It's adviseable you set `share_media` to be owned by `admin:users`. You can do this in the web GUI via the Access Control List or via `chown`. The PUID and PGID in the compose files assume this. If you want to use a custom user, you need to change those - **the permissions NEED to match**.

## Dockerizing your system
Under Services -> Compose, you can now find all your Docker settings. First, make sure Docker is actually installed. Otherwise click the Reinstall button. Make sure you've assigned the shared folder `docker` to Docker here.

You may have to start your docker daemon afterwards using `systemctl start docker`. Afterwards, we want to create our own docker network that keeps our containers isolated. Within this network, they will all be able to communicate with each other by their container names, but every port needs to be forwarded to the host explicitly, if you want to expose them. To do this, we use `docker network create htpc` where `htpc` is the name of our new network.

At this point, feel free to to install a container manager like Portainer. I'm going to stick to OMV's default GUI for the sake of portability for people who may follow this tutorial on a different OS and/or want to work with raw docker-compose files.

## Creating your shared file structure
These are the folders that will be used by a lot of your containers and mounted to them accordingly. For files to be shared between containers, this needs to happen. Your folder structure should be as follows:
```
/srv/mergerfs/pool/share_media
--- media
  |--- tv
  |--- movies
  |--- music
  |--- comics
--- torrents
  |--- tv
  |--- movies
--- usenet
  |--- tv
  |--- movies
--- incomplete  
```

## Containers
You can build these compose files from templates, but I'll add them all here as well. Little note regarding the mount of the `/config` folder. This is not strictly necessary, but I prefer putting everything the container would write, like a database, outside of the `docker.img` itself and next to the pid and other files managed by OMV.

**Note:** When doing this with mergerfs, there are [conflicts with SQLite](https://github.com/trapexit/mergerfs#plex-doesnt-work-with-mergerfs). This is why we mounted the file system twice, once for `pool` and once for `config`. The same files accessed through `.../config/appdata` and `.../pool/appdata` are therefore accessed through a differently mounted filesystem based on which path you use.

### Jellyfin
Start with Jellyfin. You can find the attached here. Once the container is started, you can find your installation here `http://<your-ip>:8096`. Go through the process of adding both the movies and TV show folder. From within the container, using the interface, you can find them under `/data/media/`. You need to create one library for type movies and one for type shows.

Technically, from this point on you can place media files here and play them, if you already own a library.

### Radarr
Radarr is next. Find the compose file and use it. You can find it under `http://<your-ip>:7878/`. Once it, go to movies and import existing movies. Choose `/data/media/movies` as per Jellyfin example above.

### Sonarr
Sonarr is next. Find the compose file and use it. You can find it under `http://<your-ip>:8989/`. Once it, go to tv and import existing tv shows. Choose `/data/media/tv` as per Jellyfin example above.

### Recyclarr - configuring both Sonarr and Radarr
This section will give you a short overview of configurations for quality profiles in those applications. I highly recommend you read [TRaSH Guides](https://trash-guides.info/) to understand what this is all about.

Use the recyclarr container with the respective compose.yml. I already set up a basic configuration for you, that uses Docker's container names to easily access other containers within our docker network, `htpc`. For any further changes, consult the Recyclarr documentation.
Place the `recyclarr.yml` file in `/srv/mergerfs/config/appdata/recyclarr/`. **You need to replace the API keys with your own Sonarr and Radarr API keys in their respective application's General Settings.**

You should really understand what you're doing and why. **If you're lazy here, you will regret it later**.

#### Instructions
- Go to Settings -> Media Management and turn off Hide Advanced Settings at the top
- Create empty Series/Movies folder
- Delete empty folders
- Use Hardlinks instead of Copy
- Import Extra files (srt)
- Propers and Repacks (Do not Prefer)
- Analyse video files
- Set Permissions 
- chmod Folder 755
- chown Group 100

#### Sonarr naming scheme
- Standard Episode Format `{Series TitleYear} - S{season:00}E{episode:00} - {Episode CleanTitle} [{Preferred Words }{Quality Full}]{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoCodec]}{-Release Group}`
- Daily Episode Format `{Series TitleYear} - {Air-Date} - {Episode CleanTitle} [{Preferred Words }{Quality Full}]{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoCodec]}{-Release Group}` 
- Anime Episode Format `{Series TitleYear} - S{season:00}E{episode:00} - {absolute:000} - {Episode CleanTitle} [{Preferred Words }{Quality Full}]{[MediaInfo VideoDynamicRangeType]}[{MediaInfo VideoBitDepth}bit]{[MediaInfo VideoCodec]}[{Mediainfo AudioCodec} { Mediainfo AudioChannels}]{MediaInfo AudioLanguages}{-Release Group}`
- Series Folder Format `{Series TitleYear} [imdb-{ImdbId}]`

#### Radar naming scheme
- Standard Movie Format `{Movie CleanTitle} {(Release Year)} [imdbid-{ImdbId}] - {Edition Tags }{[Custom Formats]}{[Quality Full]}{[MediaInfo 3D]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels}][{Mediainfo VideoCodec}]{-Release Group}`
- Movie Folder Format `{Movie CleanTitle} ({Release Year}) [imdbid-{ImdbId}]`

### Prowlarr
Prowlarr abstracts away all kinds of different Torrent and Usenet trackers. You give Prowlarr access to your accounts and it communicates with the trackers. Sonarr and Radarr then communicate with Prowlarr, because it pushes tracker information to them using their APIs.

Use the respective compose.yml and start your container. You'll find it under `http://<your-ip>:9696/`. Create an account and log in.
Go to Settings -> Apps
- add Radarr, in the Prowlarr server replace `localhost` with `prowlarr`
- for the Radarr server, replace `localhost` with `radarr`
- enter your API key as found in your Radarr Settings

- add Sonarr, in the Prowlarr server replace `localhost` with `prowlarr`
- for the Sonarr server, replace `localhost` with `sonarr`
- enter your API key as found in your Sonarr Settings

Indexers are not explained further in this part of the guide.

### Jellyseerr
Use the respective compose.yml to start the container. You'll find it under `http://<your-ip>:5055/`.  Don't be confused by the Plex account. Click "Use your Jellyfin account" at the bottom.
- log in with the jellyfin account you created previously
- use `http://jellyfin:8096/`
- he email doesn't matter
- click Sync Libraries, choose Movies and TV Shows and click Continue
- Add a Radarr server, name it Radarr and use `radarr` as the hostname
- enter your API key
- repeat for Sonarr respectively

This abstracts having to add shows and movies to Sonarr and Radarr manually. It'll let you curate a wishlist and shows you what's popular right now, so you'll always hear about the latest things going on in entertainment.

### Bazarr
Bazarr downloads subtitles for you, based on your shows.
Use the respective compose.yml to start the container. You'll find it under `http://<your-ip>:6767/`.
You need to add languages you want to download by going to Settings -> Languages. Create a New Profile that at least contains English.
In Settings -> Sonarr, use `sonarr` as the host, enter your API key, test and save.
In Settings -> Radarr, use `radarr` as the host, enter your API key, test and save.
**Don't forget to add subtitle providers of your choice, they are specific to your use case.**

There are sooo many options here, most of which are specific to your case. I recommend looking at the TRaSH Guides again.
Note: If you have a lot of old shows that it's hard or impossible to find subtitles for, you can use [OpenAPI's Whisper](https://wiki.bazarr.media/Additional-Configuration/Whisper-Provider/) to generate subtitles with your Nvidia GPU.

### SABnzbd - Usenet
Usenet is basically paying to get access to a network of servers that may or may not contain what you're looking for. However, those servers aren't indexed by common search engines like most HTTP/HTML based versions of the web. So in addition to buying access to Usenet itself, you also need to buy yourself into the most common and popular indexers like NZBGeek and DrunkenSlug. Prowlarr supports Usenet indexers as well. Since this guide focuses on free and open source solutions, I will not spend much time on this section of the guide ans not mention Usenet again later.

**Note:** If you feel you want/need to run SABnzbd behind a VPN, don't use the standalone-compose.yml.

After starting your container with the respective compose.yml, you need to go to `/srv/mergerfs/config/appdata/sabnzbd/` and edit `sabnzbd.ini` and set `username = "admin"` and `password = "admin"`. It's already set to `""`, so make sure to replace those lines.
Otherwise you cannot access the web GUI.

You can now access your installation at `http://<your-ip>:8080/`. You can then log into your Usenet server that you purchased access to. Keep in mind, you should set up maximum connections according to your purchase in the advanced settings.
Set your Temporary Download Folder to `/data/incomplete/` and your completed downloads folder to `/data/usenet`. 
Next, go to category and change the `Folder/Path` for movies and tv to use the respective movies and tv folders.

Note: I originally had the incomplete folder be part of the usenet folder. I vaguely remember this leading to some problems but can't recall what they were. You may try doing the same and keeping incomplete downloads in `/data/usenet/incomplete` YMMV.

Now all that's left is grabbing your API key from General -> Security -> API Key.
In Sonarr and Radarr, you then go to Settings, Download Clients and add SABnzbd. The hostname is `sabznbd` like the Docker container and the API key is the one you grabbed. Username and password not required.
**Note:** If you're routing your traffic through a Gluetun VPN container, the hostname here needs to be `gluetun`.

### Gluetun
Glueun is my preferred way of handling VPNs. There are many containers for torrenting and Usenet with VPNs already built in. I personally prefer having a single container that I can choose to route all my traffic through for whichever other container I choose. I can technically route 10 different clients all through the same connection here. 

It should be noted here, that if you intend to use private torrent trackers that usually have their own economy and depend on your ration, it is recommended to use a VPN with port-forwarding. I won't endorse any here, you will need to do your own research. But I will say that not many support port-forwarding at a reasonable price. 

Gluetun requires different setup, depending on your VPN provider. Your best bet is [reading the wiki](https://github.com/qdm12/gluetun-wiki). While I am including a compose.yml here, it's really just an example of how to set up a VPN with port forwarding.

**You will need to place your `client.key` and `username.cert` in `/srv/mergerfs/config/appdata/gluetun`. Read the wiki!**
The example compose.yml does not contain the necessary evironment variables. The bloat would make it less readable for an easy tutorial.

### qBittorrent
The torrent client should always hide behind a VPN. Bittorrent isn't encrypted by default and even if you don't care much about anonymity, the added security is not to be neglected. Therefore I'm not offering a compose.yml without connecting to gluetun. After spinning up the container, qBittorrent is available at `http://<your-ip>:8082/` to log in as `admin` with password `adminadmin`. You may change this later if you wish.

- go to Settings -> Connection and change the port to whichever port-forwarded port you chose when setting up your gluetun container, you'll find it in that compose.yml
- Torrent Management Mode -> Automatic
- When Category Changed -> Relocate Torrent
- When Default Save Path Changed -> Relocate Affected Torrents
- When Category Save Path Changed -> Relocate Affected Torrents
- Default Save Path: `/data/torrents`
- Keep incomplete torrents in `/data/incomplete`
- Go to Categories on the left -> All - Right Click -> Add Category -> name it radarr with path `/data/torrents/movies`
- Go to Categories on the left -> All - Right Click -> Add Category -> name it sonarr with path `/data/torrents/tv`

Now add the client 'qBittorrent' to both Radarr and Sonarr as you previously did with SABnzbd.
Settings -> Download Clients -> Add Client -> qBittorrent
The host needs to be `gluetun`, the port `8082` and the username and password as above - or whatever you changed them to.
The category needs to be either `radarr` or `sonarr`. They need to match the categories in the client you created above.

### Indexers
You can now add your preferred indexers and trackers to Prowlarr. It should support pretty much any available ones.

Please refer to Prowlarr's documentation if you have trouble setting uo an indexer that isn't already listed with them.
Once you've done so, you can go to System -> Tasks and manually trigger Application Indexer Sync. They should then appear in Sonarr and Radarr automatically.
If you now search for content via Sonarr and Radarr, they will scan all of your previously set up indexer and download matching results.

- [Usenet](trackers/usenet.md)
- [Torrents](trackers/torrents.md)

## Post-Install
First of all, congratulations. You've managed to make it past the hardest part. It's all smooth sailing from here on out. You should now have enough knowledge and understanding to run a second instance of Sonarr running on a different port just for Anime or run separate instances for 1080p and 4k, if you have plenty of storage but don't want to waste power on transcoding.
My personal opinion is that 4k -> 1080p/720p transcodes using hardware acceleration are cheaper than separate libraries.

## Making sure transcoding works
Most info taken from [Jellyfin's documentation](https://jellyfin.org/docs/general/administration/hardware-acceleration/nvidia/).
The reason we picked up the P400 is because it's a very small, cheap card of the Pascal generation and thus supports HEVC 10 bit encoding. 

Add `contrib` and `non-free` to your repositories inside the `/etc/apt/sources.list` file. You can use vi or nano to edit this file. Follow the instructions here to install your [Nvidia drivers](https://forum.openmediavault.org/index.php?thread/38013-howto-nvidia-hardware-transcoding-on-omv-5-in-a-plex-docker-container/&postID=313378#post313378) if you went with the Quadro P400.

Install proprietary packages to support transcoding via `sudo apt update && sudo apt install -y libnvcuvid1 libnvidia-encode1`.
Then call `nvidia-smi` to confirm your GPU is detected and running. If you have Secure Boot enabled in your BIOS, see the note about signing packages [here](https://wiki.debian.org/NvidiaGraphicsDrivers#Version_470.129.06).

You should be able to just install the entire CUDA toolkit, if you think you'll need anything else via `sudo apt-get install nvidia-cuda-toolkit`. Keep in mind, this is pretty large. If you don't know whether you need it, don't jump the gun.

After following all the instructions to install Nvidia drivers, run `nvidia-smi` to confirm the GPU is working. 
Add admin to the video user group: `sudo usermod -aG video admin`.

Use `the jellyfin-nvidia-compose.yml`, restart the container with it, then run `docker exec -it jellyfin ldconfig && sudo systemctl restart docker`. Open your Jellyfin interface, go to Administrator -> Dashboard -> Playback and enable transcoding. It's best you follow the Jellyfine documentation, but the general gist is to enable Nvidia NVENC and every codec besides AV1. Allow encoding to HEVC as well.

**Note:* If you are using the `linuxserver/jellyfin` image instead of the `jellyfin/jellyfin` image, you need to add `NVIDIA_VISIBLE_DEVICES=all` under environment in your compose.yml that the following may be required underneath 'container_name'.
```
group_add:
      - '109' #render
      - '44' #video
 ```
 
You can confirm transcoding works by forcing a lower quality via the settings when playing a video or playing something unsupported for DirectPlay. While a video is playing, going to Settings -> Playback Info will open a great debug menu.

#### Improving H264

I highly recommend you enable HEVC transcoding in Jellyfin's playback settings and find yourself a Jellyfin client (like Jellyfin Media Player) that supports preferring to transcode to HEVC. Nvidia's H264 is pretty terrible. If you won't transcode many streams simulatenously, it may be an option to play with the transcode settings in Jellyfin at force a higher quality at the expense of more GPU resources. You need to find what works best for you.

If you know for a fact you will have transcode to H264 a lot, something like a 10th gen i3 based media server with Intel QuickSync will result in much better quality. I personally only use the Nvidia card as a worst case scenario fallback and will play all H264 natively whenever possible.

#### Making HEVC/h265/x265 work
If you want support for HEVC transcoding in Chrome out of the box, [there's this PR](https://github.com/jellyfin/jellyfin-web/pull/4041). You could merge this and supply your own Docker image.

Jellyfin Media Player [has an option](https://github.com/jellyfin/jellyfin-media-player/issues/319) to transcode to HEVC over h264.

People have reported, that [using Kodi](https://github.com/jellyfin/jellyfin/issues/9458#issuecomment-1465300270) as a client or Jellyfin for Kodi preferred HEVC and will force your server to transcode to HEVC over h264, if transcoding happens.

If you're looking to primarily watch in your browser, it's worth merging the above PR yourself. However, you'd have to build the jellyfin-web project yourself and place the compiled frontend files on your server, so that you can use Docker to map it like so `/srv/mergerfs/pool/appdata/jellyfin/web/:/jellyfin/jellyfin-web` and overwrite the supplied contents of the docker image.

### DNS setup
Many people here will likely to fire up pihole or Adguard Home. These are valuable options, but in my experience they introduce another issue. If you run your DNS server on your media server and it ever goes down, you have a single point of failure. Your entire network won't be able to resolve any names. It'll become essentially unusable. If you already have DNS running on another server in your network or your router supports it, say through OpenWRT or OPNSense, just set up a few entries and skip to the explanation for Nginx Proxy Manager.

#### mDNS
To solve the issue(s) described above, we're going to set up mDNS. Every call to a name suffixed in `.local` is automatically sent to the entire network and your server can choose to respond to it or not. So your media server itself will be responsible for listening to a name like `media-pc.local`.

If it's not already installed, install avahi-daemon via `apt install avahi-daemon` and `apt install avahi-utils`.
To confirm this works, you should now be able to access your web GUI via `http://media-pc.local` assuming your host name is set to media-pc during installation or in the web GUI under Network -> Hostname.

We can now use `avahi-publish` to add an another alias, like sonarr, radarr, jellyfin, etc.
You can confirm this works, by executing `/bin/bash -c "/usr/bin/avahi-publish -a -R sonarr.local  $(avahi-resolve -4 -n media-pc.local | cut -f 2)"` and accessing your server via sonarr.local in the browser. Press Ctrl+C in your terminal to cancel it again.

Create a new file called `/etc/systemd/system/aliases.service`. The content should be as follows:
```
[Unit]
Description=Publish aliases for local media server
Wants=network-online.target
After=network-online.target
BindsTo=sys-subsystem-net-devices-enp0s31f6.device
Requires=avahi-daemon.service

[Service]
Type=forking
ExecStart=/srv/mergerfs/config/appdata/aliases.sh

[Install]
WantedBy=multi-user.target
```

**Note: The device under BindsTo, called `enp0s31f6`, needs to be changed to the device listed under Network -> Interfaces in your web GUI**. This will execute a file called aliases.sh whenever your network starts/restarts. It will then automatically publish all the available aliases you set in that file. You can find the aliases.sh file that serves as a template here and place it in `/srv/mergerfs/config/appdata`. Make sure to make the file executable via `chmod +x aliases.sh`.

Now do `systemctl daemon reload`, `systemctl start aliases` and `systemctl enable aliases`. The latter will set the script to auto start. You should now be able to access your server via `tv.local`, `sonarr.local`, etc.

#### Reverse Proxy
We're going to use nginx as a reverse proxy. If you're already familiar with that, set it up as you wish. I will, however, use Nginx Proxy Manager for an easy GUI. First, we need to change our web GUI's port. Go to System -> Workbench and change port 80 to 180.
You need to use `http://<your-ip>:180` to access it now.

Create a new docker container with respective compose.yml. You should then be able to access its web GUI via `http://<your-ip>:81/`.
Login with the default credentials and make an account.
```
Email:    admin@example.com
Password: changeme
```

You can now add a proxy host. Add domain `media-pc.local` and add port forward 180. For the forward host, you can add `media-pc.local` again. This will forward port 80 to 180. After saving, you should be able to access your server via `http://media-pc.local` again.

You may now add entries for all the other aliases.
- sonarr.local forward to host sonarr with port 8989
- radarr.local forward to host radarr with port 7878
- prowlarr.local forward to host prowlarr with port 9696
- bazarr.local forward to host bazarr with port 6767
- qbittorrent.local forward to gluetun with port 8082
- catalog.local forward to host jellyseerr with port 5055
- tv.local forward to host jellyfin with port 8096

All your services should now be reachable via their respective `<name>.local`. 
**Note:** Because nginx is accessing these services through the 'htpc' docker network, you could now remove port forwarding for individual containers, if you only want them reachable through HTTP behind your reverse proxy.


### Honorable mentions and other things you might want to look into
- [Rarrnomore](https://github.com/Schaka/rarrnomore) - lets you avoid grabbing rar'd releases
- [Unpackerr](https://github.com/Unpackerr/unpackerr) - lets you unrar releases automatically (if you have enough space to seed the rar and keep the content)
- [Audiobookshelf](https://www.audiobookshelf.org/) - similar to Jellyfin, but for audiobooks
- [cross-seed](https://github.com/cross-seed/cross-seed) - lets you automate seeding the same torrents on several trackers, if they were uploaded there
- [autobrr](https://autobrr.com/) - lets you connect to your trackers' IRC to automatically grab new releases rather than waiting for RSS updates
- [Komga](https://komga.org/) - similar to Jellyfin, for reading comic books and mangas
- [homepage](https://github.com/benphelps/homepage) - lets you create a dashboard for all your services
- [Lidarr](https://lidarr.audio/) - Sonarr/Radarr alternative for music
- [Unmanic](https://github.com/Unmanic/unmanic) - lets you transcode all your media; download REMUXES and transcode them to your own liking
