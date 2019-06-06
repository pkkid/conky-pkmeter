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
* Packages: conky-all, nethogs, python-plexapi, python3-requests, python3-jinja2
* Fonts: Ubuntu (already present in Ubuntu)

### Installation
Copy the pkmeter scripts into place..
```bash
cd ~/Projects && git clone https://github.com/mjs7231/pkmeter-conky.git
ln -s ~/Projects/pkmeter-conky/pkmeter ~/.pkmeter
cp ~/.pkmeter/config-example.json ~/.pkmeter/config.json
```

Edit `config.json` with your desired configuration then run
`genconkyrc` to generate the config.lua and conkyrc files.
```bash
vim ~/.pkmeter/config.json
python3 ~/.pkmeter/pkmeter.py genconkyrc
conky
```

### Thanks
* Fisadev for creating the Conky Draw scripts.
