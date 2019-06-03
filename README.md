# PKMeter Conky Scripts
<img align="right" src="preview.png">
A collection of scripts and a Conky configuration for my setup. The scripts help
make fetching data easy and results are stored as json files in `~/.cache/pkmeter`.

### Available Scripts
* `pkmeter.py darksky` (Weather)
* `pkmeter.py externalip` (Extenral IP)
* `pkmeter.py nvidia` (GPU Temp)
* `pkmeter.py plexadded` (Recently Added)
* `pkmeter.py plexsessions` (Now Playing)
* `pkmeter.py sickrage` (Coming Soon)

### Requirements
* Packages: conky-all, python3-requests, python-plexapi
* Fonts: Ubuntu (already present in Ubuntu)

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

