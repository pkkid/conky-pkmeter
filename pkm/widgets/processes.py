from pkm.widgets.base import BaseWidget
from pkm import utils

NEWLINE = '\n'


class ProcessesWidget(BaseWidget):
    """ Displays the NVIDIA gpu metrics. """

    def __init__(self, wsettings, origin=0):
        super().__init__(wsettings, origin)
        # Header and footer are 67px
        # Each row of Ubuntu:size=8 adds 13px height
        self.height = 67 + (self.count * 13)

    def get_conkyrc(self, theme):
        """ Create the conkyrc template for the this widget. """
        rows = []
        for i in range(1, self.count+1):
            rows.append(utils.clean_spaces(f"""
                ${{goto 10}}{theme.label}${{{self.sortby} name {i}}}\\
                ${{goto 110}}{theme.value}${{{self.sortby} mem_res {i}}}\\
                ${{alignr 10}}${{{self.sortby} cpu {i}}}%
            """))
        return utils.clean_spaces(f"""
            ${{voffset 20}}${{goto 10}}{theme.header}Processes${{font}}
            ${{goto 10}}{theme.subheader}${{processes}} processes
            ${{voffset 17}}{NEWLINE.join(rows)}
            {theme.reset}\\
        """)  # noqa

    def get_lua_entries(self, theme):
        """ Create the draw.lua entries for this widget. """
        origin, width, height = self.origin, self.width, self.height
        return [
            self.draw('line', frm=(100,origin), to=(100,origin+40), thickness=width, color=theme.header_bg),  # header bg
            self.draw('line', frm=(100,origin+40), to=(100,origin+height), thickness=width, color=theme.bg),  # main bg
        ]
