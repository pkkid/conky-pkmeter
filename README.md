# Conky-PKMeter
<img align="right" src="preview.png" style="z-index:999">
Conky configuration written entirely in Lua. Provides widgets for clock,
openmeteo (weather), system, nvidia, processes, networks, filesystems, and 
nowplaying (using playerctl).
<br/><br/>

### Installation
Clone this respositry and make sure you have the python-requirements installed
on your system and start it with the final command below.
```bash
sudo apt install conky-all lua-socket lua-sec playerctl
git clone https://github.com/pkkid/pkmeter-conky.git
cd pkmeter-conky
conky -c conkyrc
```
<br/>

### Configuration
Most of the configuration is in the file `config.lua`. If there are a few more
options available in conkyrc that help control the main conky window. At the
very least, I believe you'll want to take a look at the following:

1. `openmeteo` - This this is the weather widget. You will want to update these
   settings to grab the right weather for your area.
2. `networks` - To find out what your the network device names are on your system
   you can run the command `ifconfig`. Add the devices you want to monitor to
   the devices section.
3. `filesystems` - By default, this only watches the root filesystem. However,
   the io chart requires you input the proper device name to be monitored. You
   can list the filesystems on your device with the command `df -h`. Add which
   ever ones you want to monitor to the filesystems section.
<br/>

### Thanks
Fisadev & Zineddine SAIBI for creating the original Conky draw.lua scripts.
