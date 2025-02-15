from pkm.widgets.base import BaseWidget
from pkm import utils

NEWLINE = '${voffset 10}\n'


class FileSystemsWidget(BaseWidget):
    """ Displays the NVIDIA gpu metrics. """

    def __init__(self, wsettings, origin=0):
        super().__init__(wsettings, origin)
        # Header and footer are 67px
        # Each filesystem row adds 36px
        # Subtract 10px no voffset on last device
        self.height = 57 + (len(self.filesystems) * 36)

    def get_conkyrc(self, theme):
        """ Create the conkyrc template for the this widget. """
        rows = []
        for fs in self.filesystems:
            rows.append(utils.clean_spaces(f"""
                ${{goto 10}}{theme.value}{fs['name']}${{alignr 55}}${{fs_free {fs['path']}}} free
                ${{goto 10}}{theme.value}${{fs_used_perc {fs['path']}}}%{theme.value}${{alignr 55}}${{fs_size {fs['path']}}} total
            """))
        graphfs = self.graph_fs or self.filesystems[0]['path']
        return utils.clean_spaces(f"""
            ${{voffset 17}}${{goto 100}}{theme.accent1}${{diskiograph {graphfs} 24,90}}
            ${{voffset -36}}${{goto 10}}{theme.header}File Systems
            ${{goto 10}}{theme.subheader}IO: ${{diskio {graphfs}}}/s
            ${{voffset 17}}{NEWLINE.join(rows)}
        """)  # noqa

    def get_lua_entries(self, theme):
        """ Create the draw.lua entries for this widget. """
        origin, width, height = self.origin, self.width, self.height
        return [
            self.draw('line', frm=(100,origin), to=(100,origin+40), thickness=width, color=theme.header_bg),  # header bg
            self.draw('line', frm=(100,origin+40), to=(100,origin+height), thickness=width, color=theme.bg),  # main bg
            self.draw('line', frm=(100,origin+20), to=(190, origin+20), thickness=24, color=theme.graph_bg),  # fs graph
        ] + list(self._fs_entries(theme, origin))

    def _fs_entries(self, theme, origin):
        y = origin+65
        for fs in self.filesystems:
            yield self.draw('ring_graph', conky_value=f"fs_used_perc {fs['path']}", center=(172,y),
                radius=8, bar_color=theme.accent1, bar_thickness=4, background_color=theme.graph_bg)
            y += 36
