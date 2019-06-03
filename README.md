# PKMeter Conky Scripts

A Collection of scripts and a Conky configuration script for my setup. The scripts
help make fetching data easy and results are stored as json files in ~/.cache/pkmeter.

### Available Scripts
* darksky (Weather)
* externalip (Extenral IP)
* nvidia (GPU Temp)
* plexadded (Recently Added)
* plexsessions (Now Playing)
* sickrage (Coming Soon)

### Requirements
* Apt: conky-all, python3, python3-requests, python-plexapi
* Fonts: Ubuntu

### Installation
Copy the pkmeter scripts into place..
```bash
git clone https://github.com/mjs7231/pkmeter-conky.git
ln -s ~/Projects/pkmeter-conky/pkmeter ~/.pkmeter
ln -s ~/.pkmeter/conkyrc ~/.conkyrc
```

Create `~/.pkmeter/config.ini` with the following variables..
```ini
[darksky]
apikey=<APIKEY>
coords=<COORDS>

[sickrage]
host=<HOST>
apikey=<APIKEY>

[plex]
ignore=Bar Rescue,The Late Show,Last Week Tonight,Cops
```

Now you should be able to run conky..
```bash
conky
```

### Thanks
* Fisadev for creating the Conky Draw scripts.
* 

