import dbus, os, random, requests
from shutil import copyfile
from pkm.widgets.base import BaseWidget
from pkm import CACHE, PKMETER, ROOT
from pkm import log, utils

DEFAULT_ART = f"{ROOT}/pkm/img/nowplaying.jpg"
NOWPLAYING_ART = f"{CACHE}/nowplaying/nowplaying.jpg"
EMPTY_DATA = {'application':'', 'status':'', 'title':'Current Track', 'artist':'Artist', 'arturl':'', 'length':'0:00', 'position':'0:00', 'percent':0}
QUIPS = ["All is calm", "Enjoying the peace and quiet", "I can hear my thoughts", "It's quiet in here",
    "No beats detected", "No jams right now", "No melodies at the moment", "No music detected",
    "No music in the queue", "No music playing", "No music, no problem", "No rhythm in the air",
    "No songs in the queue", "No sound waves detected", "No tracks available", "No tracks spinning",
    "No tunes at the moment", "No tunes available", "No tunes playing", "No tunes to groove to",
    "Nothing playing right now", "Quiet as a mouse", "Shhh...it's quiet time", "Silence is golden",
    "The audio is on hold", "The band is on a break", "The beats are on break", "The concert is paused",
    "The dance floor is empty", "The DJ is taking a nap", "The jukebox is silent",
    "The music has gone fishing", "The music has left the building", "The music has taken a break",
    "The music is off-duty", "The music is on a break", "The music is on break", "The music is on hiatus",
    "The music is on hold", "The music is on pause", "The music is on standby", "The music is on standby",
    "The music is on vacation", "The music is taking a nap", "The orchestra is tuning up",
    "The playlist is empty", "The playlist is on break", "The playlist is on hold",
    "The playlist is on vacation", "The playlist is paused", "The playlist is silent",
    "The playlist is taking five", "The sound is on sabbatical", "The sound of silence",
    "The sound system is idle", "The sound system is idle", "The sound system is resting",
    "The sound system is silent", "The soundscape is barren", "The speakers are off",
    "The speakers are on mute", "The speakers are resting", "The stage is empty"]


class NowPlayingWidget(BaseWidget):
    """ Displays the NVIDIA gpu metrics. """

    def __init__(self, wsettings, origin=0):
        super().__init__(wsettings, origin)
        # Header and footer are 67px
        # Each row of Ubuntu:size=8 adds 13px height
        self.height = 111

    def get_conkyrc(self, theme):
        """ Create the conkyrc template for the this widget. """
        return utils.clean_spaces(f"""
            ${{texeci {self.update_interval} {PKMETER} update {self.name}}}\\
            ${{voffset 20}}${{goto 10}}{theme.header}Now Playing
            ${{goto 10}}{theme.subheader}${{execi 2 {PKMETER} get {self.name}.application}}
            ${{voffset 22}}${{goto 10}}{theme.value}${{execi 2 {PKMETER} get {self.name}.title | cut -c 1-23}}
            ${{goto 10}}{theme.label}${{execi 2 {PKMETER} get {self.name}.artist | cut -c 1-23}}
            ${{goto 10}}{theme.label}${{execi 2 {PKMETER} get {self.name}.position}} of ${{execi 5 {PKMETER} get {self.name}.length}}
        """)  # noqa

    def get_lua_entries(self, theme):
        """ Create the draw.lua entries for this widget. """
        origin, width, height = self.origin, self.width, self.height
        pct = f'execi 2 {PKMETER} get {self.name}.percent'
        return [
            self.draw('line', frm=(100,origin), to=(100,origin+40), thickness=width, color=theme.header_bg),  # header bg
            self.draw('line', frm=(100,origin+40), to=(100,origin+height), thickness=width, color=theme.bg),  # main bg
            self.draw('bar_graph', conky_value=pct, frm=(10,origin+50), to=(130,origin+50), bar_color=theme.accent1,
                bar_thickness=2, background_color=theme.graph_bg, critical_threshold=105),  # percent playing
            self.draw('image', filepath=NOWPLAYING_ART, frm=(140,origin+48), width=50),  # album art
        ]

    def update_cache(self):
        """ Fetch current track information from dbus and update cache. """
        newdata = {}
        olddata = utils.load_cached_data(self.cachepath) or EMPTY_DATA
        # Fetch the track information from dbus
        session = dbus.SessionBus()
        players = (session.get_object('org.freedesktop.DBus', '/org/freedesktop/DBus')
            .ListNames(dbus_interface='org.freedesktop.DBus'))
        players = [name for name in players if name.startswith('org.mpris.MediaPlayer2.')]
        for player in players:
            try:
                playerobj = session.get_object(player, '/org/mpris/MediaPlayer2')
                properties = dbus.Interface(playerobj, 'org.freedesktop.DBus.Properties')
                metadata = properties.Get('org.mpris.MediaPlayer2.Player', 'Metadata')
                newdata['status'] = properties.Get('org.mpris.MediaPlayer2.Player', 'PlaybackStatus')
                newdata['title'] = str(metadata.get('xesam:title', 'Unknown Title'))
                if newdata['status'] == 'Playing' and newdata['title'] != 'Unknown':
                    newdata['application'] = str(properties.Get('org.mpris.MediaPlayer2', 'Identity'))
                    newdata['artist'] = str(metadata.get('xesam:artist', ['Unknown Artist'])[0])
                    newdata['length'] = metadata.get('mpris:length', 0) // 1000000
                    newdata['position'] = properties.Get('org.mpris.MediaPlayer2.Player', 'Position') // 1000000
                    newdata['percent'] = utils.percent(newdata['position'], newdata['length'])
                    newdata['position'] = self._format_duration(newdata['position'])
                    newdata['length'] = self._format_duration(newdata['length'])
                    newdata['arturl'] = str(metadata.get('mpris:artUrl', ''))
                    self._download_art(newdata['arturl'])
                    return newdata
            except Exception as err:
                log.error(f"Error fetching player info: {err}")
        # No track information was found
        copyfile(DEFAULT_ART, NOWPLAYING_ART)
        newdata = dict(**EMPTY_DATA)
        quip = olddata['application']
        newdata['application'] = quip if quip in QUIPS else random.choice(QUIPS)
        return newdata
        
    def _download_art(self, url):
        """ Download album art to cache and return path. """
        if not url: return None
        os.makedirs(f'{CACHE}/{self.name}', exist_ok=True)
        log.info(f"Downloading album art from {url}")
        response = requests.get(url, stream=True)
        if response.status_code == 200:
            with open(NOWPLAYING_ART, 'wb') as handle:
                handle.write(response.content)

    def _format_duration(self, seconds):
        """Convert seconds to a string in the format n:nn."""
        minutes, seconds = divmod(seconds, 60)
        return f'{minutes}:{seconds:02d}'
