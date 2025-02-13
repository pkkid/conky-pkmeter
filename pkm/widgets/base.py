

class BaseWidget:

    def __init__(self, wconfig, origin=0):
        self.wconfig = wconfig      # Widget configuration object
        self.origin = 0             # Starting ypos of the widget
        self.height = origin        # Height of the widget

    def get_conkyrc(self):
        """ Create the conkyrc template for the this widget. """
        # NOTE: To make sure the height lines up with the conkyrc text, I have been
        # putting the following at the end of the conkyrc templates and adjusting the
        # voffset to make sure any new backgrounds are half way between the two lines
        # of XXX's. ${{font}}${{color}}${{voffset 4}}XXX\nXXX\\
        return ''

    def get_lua_entries(self):
        """ Create the draw.lua entries for this widget. """
        return []

    def point(self, pos):
        """ Syntax for a point in draw.lua. """
        return f'{{x={pos[0]},y={pos[1]}}}'

    def line(self, start, end, color, alpha, thickness):
        """ Syntax for a line in draw.lua. """
        return (f"{{kind='line', from={self.point(start)}, to={self.point(end)}, "
            f"color='{color}', alpha={alpha}, thickness={thickness}}}")

    def image(self, filepath, start, width=None, height=None):
        """ Syntax for an image in draw.lua. """
        entry = f"{{kind='image', filepath='{filepath}', from={self.point(start)}"
        entry += f", width={width}" if width else ''
        entry += f", height={height}" if height else ''
        return f"{entry}}}"

    def bargraph(self, value, start, end, bgcolor, bgalpha, color, thickness, bgthickness=None):
        """ Syntax for a bar_graph in draw.lua. """
        bgthickness = bgthickness if bgthickness else thickness
        return (f"{{kind='bar_graph', conky_value='{value}', from={self.point(start)}, to={self.point(end)}, "
            f"background_color={bgcolor}, background_alpha={bgalpha}, background_thickness={bgthickness}, "
            f"bar_color={color}, bar_thickness={thickness}}}")

    def ringgraph(self, value, center, radius, bgcolor, bgalpha, color, thickness, bgthickness=None):
        """ Syntax for a ring_graph in draw.lua. """
        bgthickness = bgthickness if bgthickness else thickness
        return (f"{{kind='ring_graph', conky_value='{value}', center={self.point(center)}, "
            f"radius='{radius}', background_color={bgcolor}, background_alpha={bgalpha}, "
            f"background_thickness={bgthickness}, bar_color={color}, bar_thickness={thickness}}}")
