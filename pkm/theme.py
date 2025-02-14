from pkm import CONFIG


class ConkyTheme:
    """ A bunch of useful and reusable variables to use when createing the conky templates.
        This helps keep everythign same same by pre-defining font and color strings. These
        variables are purley for convenience and shorter widget definitions.
        https://conky.sourceforge.net/variables.html
    """

    def __init__(self):
        self.accent = f"${{color {CONFIG['accent']}}}"
        self.accent2 = f"${{color {CONFIG['accent2']}}}"
        self.header_color = f"${{color {CONFIG['header_color']}}}"
        self.subheader_color = f"${{color {CONFIG['subheader_color']}}}"
        self.label_color = f"${{color {CONFIG['label_color']}}}"
        self.value_color = f"${{color {CONFIG['value_color']}}}"
        self.header_font = f"${{font {CONFIG['header_font']}}}"
        self.subheader_font = f"${{font {CONFIG['subheader_font']}}}"
        self.label_font = f"${{font {CONFIG['label_font']}}}"
        self.value_font = f"${{font {CONFIG['value_font']}}}"
        self.header = f"{self.header_font}{self.header_color}"
        self.subheader = f"{self.subheader_font}{self.subheader_color}"
        self.label = f"{self.label_font}{self.label_color}"
        self.value = f"{self.value_font}{self.value_color}"
        # Draw.lua Colors
        self.bg = CONFIG['bg']
        self.graph_bg = CONFIG['graph_bg']
        self.header_bg = CONFIG['header_bg']
        self.header_graph_bg = CONFIG['header_graph_bg']
        self.reset = '${font}${color}'
        self.test = '${voffset 5}${goto 10}${color #442222}${hr}${voffset -5}'
