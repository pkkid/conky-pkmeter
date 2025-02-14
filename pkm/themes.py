"""
Theme Helper Classes
These classes provide convenience values for creating conkyrc and draw.lua
entries. The theme valeus themselevs are defined in config.json5 and
default.json5.
"""
from pkm import CONFIG


class ConkyTheme:
    """ Convenience values useful for creating conkyrc strings.
        https://conky.sourceforge.net/variables.html
    """
    def __init__(self):
        # Colors
        self.accent1 = f"${{color {CONFIG['accent1'][:7]}}}"
        self.bg = f"${{color {CONFIG['bg'][:7]}}}"
        self.graph_bg = f"${{color {CONFIG['graph_bg'][:7]}}}"
        self.header_bg = f"${{color {CONFIG['header_bg'][:7]}}}"
        self.header_color = f"${{color {CONFIG['header_color'][:7]}}}"
        self.label_color = f"${{color {CONFIG['label_color'][:7]}}}"
        self.subheader_color = f"${{color {CONFIG['subheader_color'][:7]}}}"
        self.value_color = f"${{color {CONFIG['value_color'][:7]}}}"
        # Fonts
        self.header_font = f"${{font {CONFIG['header_font']}}}"
        self.label_font = f"${{font {CONFIG['label_font']}}}"
        self.subheader_font = f"${{font {CONFIG['subheader_font']}}}"
        self.value_font = f"${{font {CONFIG['value_font']}}}"
        # Combined
        self.header = self.header_font + self.header_color
        self.label = self.label_font + self.label_color
        self.subheader = self.subheader_font + self.subheader_color
        self.value = self.value_font + self.value_color
        # Reset
        self.reset = '${font}${color}'
        self.debug = '${voffset 6}${goto 10}${color #442222}${hr 2}${voffset -6}'


class LuaTheme:
    """ Convenience values useful for creating draw.lua entries.
        Many of these values get massaged in base.py::_process_drawarg()
        https://github.com/fisadev/conky-draw
    """
    def __init__(self):
        # Colors
        self.accent1 = CONFIG['accent1']
        self.bg = CONFIG['bg']
        self.graph_bg = CONFIG['graph_bg']
        self.header_bg = CONFIG['header_bg']
        self.header_color = CONFIG['header_color']
        self.label_color = CONFIG['label_color']
        self.subheader_color = CONFIG['subheader_color']
        self.value_color = CONFIG['value_color']
        # Fonts
        self.header_font = CONFIG['header_font']
        self.label_font = CONFIG['label_font']
        self.subheader_font = CONFIG['subheader_font']
        self.value_font = CONFIG['value_font']
