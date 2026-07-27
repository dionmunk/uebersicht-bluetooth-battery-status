command: "(ioreg -r -k BatteryPercent | grep -E '\"(Product|BatteryPercent)\"' ; echo '---SEP---' ; system_profiler -json SPBluetoothDataType 2>/dev/null)"

# Enable or disable this widget.
widgetEnabled: true   # true | false

refreshFrequency: '30s'

style: """
  // grid: col 2 · row 2 · 1×1  (see LAYOUT.md)
  top 100px
  left 340px

  color var(--text, #fff)
  text-shadow: 0 1px 1px rgba(20, 1, 1, 0.2)   // inherits to all text elements
  font-family -apple-system, BlinkMacSystemFont, system-ui, sans-serif
  display: flex
  gap: 10px

  .panel
    background var(--panel-bg, rgba(#000, .15))
    -webkit-backdrop-filter: blur(var(--panel-blur, 48px))
    backdrop-filter: blur(var(--panel-blur, 48px))
    border-radius 10px
    box-sizing: border-box
    min-height: 80px       // base minimum widget height (see LAYOUT.md)

  .panel-stats
    padding 10px 10px 12px
    display: flex          // lets stats-inner fill the 80px panel height

  .stats-inner
    width: 300px
    text-align: left
    position: relative
    display: flex
    flex-direction: column   // title on top, devices pushed to the bottom

  .widget-title
    font-size 10px
    text-transform uppercase
    font-weight bold
    margin-bottom: 8px

  .devices
    display: flex
    flex-direction: column
    gap: 10px
    margin-top: auto       // push the device list to the panel bottom

  .device-row
    display: flex
    flex-direction: column
    gap: 5px
    font-size: 11px
    line-height: 1

  .device-header
    display: flex
    align-items: baseline
    gap: 8px

  .device-name
    flex: 1
    overflow: hidden
    text-overflow: ellipsis
    white-space: nowrap
    text-transform: capitalize
    line-height: 1.4   // row sets line-height:1; give descenders (g/y/p) room so overflow:hidden doesn't shave them

  .device-percent
    text-align: right
    font-weight: bold

  .device-bar-track
    width: 100%
    height: 6px
    border-radius: 6px
    background: var(--level-base, rgba(#fff, .2))
    overflow: hidden
    box-shadow: 0 1px 1px rgba(20, 1, 1, 0.10)   // base bar: matches text shadow

  .device-bar-fill
    height: 6px
    border-radius: 6px
    transition: width .3s ease, background .3s ease
    box-shadow: 1px 0 3px rgba(0, 0, 0, 0.04)   // faint separation under the cap
"""

render: -> """
  <div class="panel panel-stats">
    <div class="stats-inner">
      <div class="widget-title">Bluetooth Batteries</div>
      <div class="devices"></div>
    </div>
  </div>
"""

# Pick a bar color for a peripheral based on its remaining charge — inverse of
# Storage's fill scale (low = severe). Colors show only under a color scheme;
# monochrome falls through to --level-max (mode-driven ink, so it flips).
deviceBarColor: (pct) ->
  if pct <= 10 then 'var(--status-critical, var(--level-max, rgba(255, 255, 255, 1)))'
  else if pct <= 25 then 'var(--status-elevated, var(--level-max, rgba(255, 255, 255, 1)))'
  else if pct <= 40 then 'var(--status-warn, var(--level-max, rgba(255, 255, 255, 1)))'
  else 'var(--status-ok, var(--level-max, rgba(255, 255, 255, 1)))'

# Parse the ioreg block — alternating Product / BatteryPercent records.
# Catches devices that expose HID battery levels (e.g., Magic Mouse / Keyboard).
parseIoreg: (text) ->
  devices = []
  currentName = null
  for line in text.split('\n')
    if (m = line.match /"Product"\s*=\s*"([^"]+)"/)
      currentName = m[1].replace(/-/g, ' ')
    else if (m = line.match /"BatteryPercent"\s*=\s*(\d+)/) and currentName?
      devices.push name: currentName, percent: parseInt(m[1], 10)
      currentName = null
  devices

# Parse system_profiler JSON.
# Catches devices that don't expose ioreg battery (e.g., AirPods, which report
# Case / Left / Right separately).
parseSystemProfiler: (jsonText) ->
  devices = []
  return devices unless jsonText
  try
    data = JSON.parse(jsonText)
  catch e
    return devices
  for controller in (data?.SPBluetoothDataType or [])
    for entry in (controller?.device_connected or [])
      for rawName, info of entry
        name = rawName.replace(/-/g, ' ')
        toPct = (v) -> parseInt(v, 10) if v?
        # Combined single battery
        if info.device_batteryLevelMain?
          devices.push name: name, percent: toPct(info.device_batteryLevelMain)
        # AirPods-style split batteries
        if info.device_batteryLevelCase?
          devices.push name: "#{name} (Case)", percent: toPct(info.device_batteryLevelCase)
        if info.device_batteryLevelLeft?
          devices.push name: "#{name} (Left)", percent: toPct(info.device_batteryLevelLeft)
        if info.device_batteryLevelRight?
          devices.push name: "#{name} (Right)", percent: toPct(info.device_batteryLevelRight)
  devices

update: (output, domEl) ->
  # Hide entirely when disabled.
  if not @widgetEnabled
    $(domEl).css('display', 'none')
    return
  $(domEl).css('display', '')
  [ioregText, jsonText] = output.split('---SEP---')
  ioregDevices = @parseIoreg(ioregText or '')
  spDevices    = @parseSystemProfiler((jsonText or '').trim())

  # Merge, deduping by display name (ioreg wins if both report the same device).
  seen = {}
  devices = []
  for d in ioregDevices.concat(spDevices)
    unless seen[d.name]
      seen[d.name] = true
      devices.push d

  div = $(domEl)

  # Hide the widget when no peripherals are reporting a battery.
  if devices.length is 0
    div.animate({opacity: 0}, 1000, 'swing').hide(1)
    return

  $devices = div.find('.devices').empty()
  for d in devices
    color = @deviceBarColor(d.percent)
    $devices.append """
      <div class="device-row">
        <div class="device-header">
          <div class="device-name">#{d.name}</div>
          <div class="device-percent">#{d.percent}%</div>
        </div>
        <div class="device-bar-track"><div class="device-bar-fill" style="width: #{d.percent}%; background: #{color}"></div></div>
      </div>
    """

  div.show(1).animate({opacity: 1}, 250, 'swing')
