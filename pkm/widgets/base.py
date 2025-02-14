from pkm import CONFIG, utils


class BaseWidget:
    """ Base class for all widgets. """

    def __init__(self, wsettings, origin):
        self.wsettings = wsettings                      # Widget configuration object
        for key, value in wsettings.items():            # Copy settings to class variables
            setattr(self, key, value)
        self.origin = origin                            # Starting ypos of the widget
        self.width = CONFIG['conky']['maximum_width']   # Width of the widget
        self.height = 0                                 # Height of the widget

    @property
    def name(self):
        """ This widgets name. """
        return utils.get_widget_name(self.__class__.__name__)

    def get_conkyrc(self, theme):
        """ Create the conkyrc template for the this widget.
            https://conky.sourceforge.net/variables.html
        """
        return ''

    def get_lua_entries(self):
        """ Create the draw.lua entries for this widget. """
        return []

    def draw(self, kind, **kwargs):
        """ Create the syntax to draw an element in draw.lua. Returns a string like:
            {kind='line', from={x=100,y=0}, to={x=100,y=100}, color=0xffffff, alpha=0.1, thickness=1}
            See draw.lua for items and arguments.
        """
        args = [f"kind='{kind}'"]
        for name, value in kwargs.items():
            args.extend(self._process_drawarg(name, value))
        return f"{{{', '.join(args)}}}"

    def _process_drawarg(self, name, value):
        """ Process individual draw argument based on its name and value. """
        name = 'from' if name == 'frm' else name
        if name in ('to', 'from', 'center'): return [f"{name}={{x={value[0]},y={value[1]}}}"]
        if name in ('font',): return self._fontstr_to_drawargs(value)
        if 'color' in name: return self._hexcolor_to_drawargs(name, value)
        if isinstance(value, (int, float)): return [f"{name}={value}"]
        return [f"{name}='{value}'"]

    def _hexcolor_to_drawargs(self, name, hex):
        """ Converts a hex color to draw.lua arguments. Allows a hex alpha channel.
            The name is needed to help generate the alpha channel name.
        """
        hex = hex.lstrip('#')
        color, alpha = hex[:6], hex[6:]
        color = f"{name}={int(color, 16)}"
        if len(alpha):
            alphaname = name.replace('color', 'alpha')
            alpha = round(int(alpha, 16) / 255, 1)
            alpha = f"{alphaname}={alpha}"
            return [color, alpha]
        return [color]

    def _fontstr_to_drawargs(self, fontstr):
        """ Converts a conky font string to draw.lua arguments.
            Example input: ubuntu:bold:italic:size=9
            Returns ["font='ubuntu'", "bold=true", "italic=true", "font_size=9"]
        """
        args = [f"font='{fontstr.split(':')[0]}'"]
        if ':' in fontstr:
            for attr in fontstr.lower().split(':')[1:]:
                if attr in ('bold', 'italic'):
                    args.append(f"{attr}=true")
                if 'size=' in attr:
                    args.append(f"font_size={attr.split('=')[1]}")
        return args
