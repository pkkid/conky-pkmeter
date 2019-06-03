-- Define your visual elements here
-- For examples, and a complete list on the possible elements and their 
-- properties, go to https://github.com/fisadev/conky-draw/
-- (and be sure to use the lastest version)

elements = {
  -- Background Images
  {kind='line', from={x=100,y=0}, to={x=100,y=1040}, color='0xFFEEEE', alpha=0.02, thickness=200}, -- Main Background
  {kind='line', from={x=0,y=106}, to={x=200,y=106}, color='0xFFEEEE', alpha=0.05, thickness=50}, -- Weather
  {kind='line', from={x=0,y=221}, to={x=200,y=221}, color='0xFFEEEE', alpha=0.05, thickness=40}, -- System
  {kind='line', from={x=100,y=222}, to={x=190,y=222}, color='0x000000', alpha=0.2, thickness=24}, -- System Chart
  {kind='line', from={x=0,y=333}, to={x=200,y=333}, color='0xFFEEEE', alpha=0.05, thickness=40}, -- NVIDIA
  {kind='line', from={x=0,y=432}, to={x=200,y=432}, color='0xFFEEEE', alpha=0.05, thickness=40}, -- Processes
  {kind='line', from={x=0,y=567}, to={x=200,y=567}, color='0xFFEEEE', alpha=0.05, thickness=40}, -- Network
  {kind='line', from={x=100,y=568}, to={x=190,y=568}, color='0x000000', alpha=0.2, thickness=24}, -- Network Chart
  {kind='line', from={x=0,y=668}, to={x=200,y=668}, color='0xFFEEEE', alpha=0.05, thickness=40}, -- FileSystems
  {kind='line', from={x=100,y=669}, to={x=190,y=669}, color='0x000000', alpha=0.2, thickness=24}, -- FileSystems Chart
  {kind='line', from={x=0,y=785}, to={x=200,y=785}, color='0xFFEEEE', alpha=0.05, thickness=40}, -- TVShows
  {kind='line', from={x=0,y=910}, to={x=200,y=910}, color='0xFFEEEE', alpha=0.05, thickness=40}, -- PlexServer

  -- Veritcal CPU Bars
  {kind='bar_graph',from={x=160,y=271},to={x=160,y=253},conky_value='cpu cpu1',background_color=0xFFFFFF,background_alpha=0.1,background_thickness=3,bar_color=0xD79921,bar_thickness=3},
  {kind='bar_graph',from={x=164,y=271},to={x=164,y=253},conky_value='cpu cpu2',background_color=0xFFFFFF,background_alpha=0.1,background_thickness=3,bar_color=0xD79921,bar_thickness=3},
  {kind='bar_graph',from={x=168,y=271},to={x=168,y=253},conky_value='cpu cpu3',background_color=0xFFFFFF,background_alpha=0.1,background_thickness=3,bar_color=0xD79921,bar_thickness=3},
  {kind='bar_graph',from={x=172,y=271},to={x=172,y=253},conky_value='cpu cpu4',background_color=0xFFFFFF,background_alpha=0.1,background_thickness=3,bar_color=0xD79921,bar_thickness=3},
  {kind='bar_graph',from={x=176,y=271},to={x=176,y=253},conky_value='cpu cpu5',background_color=0xFFFFFF,background_alpha=0.1,background_thickness=3,bar_color=0xD79921,bar_thickness=3},
  {kind='bar_graph',from={x=180,y=271},to={x=180,y=253},conky_value='cpu cpu6',background_color=0xFFFFFF,background_alpha=0.1,background_thickness=3,bar_color=0xD79921,bar_thickness=3},
  {kind='bar_graph',from={x=184,y=271},to={x=184,y=253},conky_value='cpu cpu7',background_color=0xFFFFFF,background_alpha=0.1,background_thickness=3,bar_color=0xD79921,bar_thickness=3},
  {kind='bar_graph',from={x=188,y=271},to={x=188,y=253},conky_value='cpu cpu8',background_color=0xFFFFFF,background_alpha=0.1,background_thickness=3,bar_color=0xD79921,bar_thickness=3},

  -- Memory & GPU Memory Usage
  {kind='ring_graph', conky_value='memperc', center={x=175, y=289}, radius=7, background_color=0xFFFFFF, background_alpha=0.1, background_thickness=5, bar_color=0xD79921, bar_thickness=4},
  {kind='ring_graph', conky_value='execi 5 ~/.pkmeter/pkmeter.py nvidia.percentuseddedicatedgpumemory', center={x=175, y=379}, radius=10, background_color=0xFFFFFF, background_alpha=0.1, background_thickness=5, bar_color=0x98971a, bar_thickness=4},

  -- Disk Usage
  {kind='ring_graph', conky_value='fs_used_perc /', center={x=175, y=703}, radius=7, background_color=0xFFFFFF, background_alpha=0.1, background_thickness=5, bar_color=0xD79921, bar_thickness=4},
  {kind='ring_graph', conky_value='fs_used_perc /media/Synology', center={x=175, y=734}, radius=7, background_color=0xFFFFFF, background_alpha=0.1, background_thickness=5, bar_color=0xD79921, bar_thickness=4},
}
