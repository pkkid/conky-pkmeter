"""
Theme Helper Classes
These classes provide convenience values for creating conkyrc and draw.lua
entries. The theme valeus themselevs are defined in config.json5 and
default.json5.
"""


class ConkyTheme:
    """ Convenience values useful for creating conkyrc strings.
        https://conky.sourceforge.net/variables.html
    """
    def __init__(self, config):
        # Colors
        self.accent1 = f"${{color {config['accent1'][:7]}}}"
        self.bg = f"${{color {config['bg'][:7]}}}"
        self.graph_bg = f"${{color {config['graph_bg'][:7]}}}"
        self.header_bg = f"${{color {config['header_bg'][:7]}}}"
        self.header_color = f"${{color {config['header_color'][:7]}}}"
        self.label_color = f"${{color {config['label_color'][:7]}}}"
        self.subheader_color = f"${{color {config['subheader_color'][:7]}}}"
        self.value_color = f"${{color {config['value_color'][:7]}}}"
        # Fonts
        self.header_font = f"${{font {config['header_font']}}}"
        self.label_font = f"${{font {config['label_font']}}}"
        self.subheader_font = f"${{font {config['subheader_font']}}}"
        self.value_font = f"${{font {config['value_font']}}}"
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
    def __init__(self, config):
        # Colors
        self.accent1 = config['accent1']
        self.bg = config['bg']
        self.graph_bg = config['graph_bg']
        self.header_bg = config['header_bg']
        self.header_color = config['header_color']
        self.label_color = config['label_color']
        self.subheader_color = config['subheader_color']
        self.value_color = config['value_color']
        # Fonts
        self.header_font = config['header_font']
        self.label_font = config['label_font']
        self.subheader_font = config['subheader_font']
        self.value_font = config['value_font']
