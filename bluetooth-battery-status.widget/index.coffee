command: "bluetooth-battery-status.widget/lib/bluetooth.sh"

# Enable or disable this widget.
widgetEnabled: true   # true | false

refreshFrequency: '30s'

style: """
  // grid: col 1 · row 9 · 1×1, below the internal-battery widget (see LAYOUT.md)
  top 856px
  left 10px

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
    min-height: var(--grid-unit, 80px)       // base minimum widget height (see LAYOUT.md)

  .panel-stats
    padding 10px 10px 12px
    display: flex          // lets stats-inner fill the 80px panel height

  .stats-inner
    width: calc(var(--grid-col, 320px) - 20px)
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

  // Charging bolt in front of the percentage, shown only while the device
  // reports charging; green to match internal-battery-status. The SF Symbol
  // bolt.fill, rendered to a PNG on first run (lib/render-bolt.swift) and used
  // as a mask so it takes the theme colour.
  .charge-bolt
    display: inline-block
    width: 7px
    height: 10px
    margin-right: 3px
    vertical-align: -1px
    background: var(--status-ok, var(--green, #34C759))
    -webkit-mask-image: url(bluetooth-battery-status.widget/lib/icons/bolt.fill.ink.png)
    -webkit-mask-repeat: no-repeat
    -webkit-mask-position: center
    -webkit-mask-size: contain
    mask-image: url(bluetooth-battery-status.widget/lib/icons/bolt.fill.ink.png)
    mask-repeat: no-repeat
    mask-position: center
    mask-size: contain

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

# Reduce a Bluetooth address to bare lowercase hex, so ioreg's "10-94-bb-9d-d7-b1"
# and <1094bb9dd7b1> match system_profiler's "10:94:BB:9D:D7:B1".
normAddr: (a) ->
  return null unless a
  hex = String(a).toLowerCase().replace(/[^0-9a-f]/g, '')
  if hex.length is 12 then hex else null

# Device names come from outside the widget and are inserted as HTML.
esc: (s) ->
  String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;')

# Parse the ioreg block: one device per "+-o" node, fields in any order.
# Catches devices that expose HID battery levels (e.g., Magic Mouse / Keyboard).
# "Product" can be blank (seen on macOS 26 and 27), so each device keeps its
# address for a name lookup in system_profiler. BatteryStatusFlags reads 3 on
# the charging cable and 0 otherwise; the 2 bit is taken as "charging".
parseIoreg: (text) ->
  devices = []
  cur = null
  flush = ->
    devices.push cur if cur?.percent?
    cur = null
  for line in text.split('\n')
    if /\+-o/.test(line)
      flush()
      cur = {name: null, address: null, percent: null, charging: false}
    else if not cur?
      continue
    else if (m = line.match /"Product"\s*=\s*"([^"]+)"/)
      cur.name = m[1].replace(/-/g, ' ')
    else if (m = line.match /"(?:DeviceAddress|BD_ADDR)"\s*=\s*(\S+)/)
      cur.address ?= @normAddr(m[1])
    else if (m = line.match /"BatteryPercent"\s*=\s*(\d+)/)
      cur.percent = parseInt(m[1], 10)
    else if (m = line.match /"BatteryStatusFlags"\s*=\s*(\d+)/)
      cur.charging = (parseInt(m[1], 10) & 2) isnt 0
  flush()
  devices

# Parse system_profiler JSON. Returns {devices, names}:
#   devices: connected devices that report a battery, which catches those that
#            don't expose one in ioreg (e.g., AirPods, which report Case / Left /
#            Right separately)
#   names:   address -> name for every paired device, connected or not, to name
#            ioreg devices whose Product is blank
parseSystemProfiler: (jsonText) ->
  result = {devices: [], names: {}}
  return result unless jsonText
  try
    data = JSON.parse(jsonText)
  catch e
    return result
  toPct = (v) ->
    n = parseInt(v, 10)
    if isNaN(n) then null else n
  for controller in (data?.SPBluetoothDataType or [])
    for section in ['device_connected', 'device_not_connected']
      for entry in (controller?[section] or [])
        for rawName, info of entry
          name = rawName.replace(/-/g, ' ')
          address = @normAddr(info?.device_address)
          result.names[address] = name if address
          continue unless section is 'device_connected'
          for [suffix, key] in [['', 'Main'], [' (Case)', 'Case'], [' (Left)', 'Left'], [' (Right)', 'Right']]
            pct = toPct(info?["device_batteryLevel#{key}"])
            result.devices.push {name: "#{name}#{suffix}", address: address, percent: pct} if pct?
  result

update: (output, domEl) ->
  # Hide entirely when disabled.
  if not @widgetEnabled
    $(domEl).css('display', 'none')
    return
  $(domEl).css('display', '')
  [ioregText, jsonText] = output.split('---SEP---')
  ioregDevices = @parseIoreg(ioregText or '')
  sp           = @parseSystemProfiler((jsonText or '').trim())

  # Merge. ioreg wins when both report the same device, matched by address
  # (or by name when an address is missing). AirPods' Case / Left / Right
  # share one address but differ in name, so they all stay.
  devices  = []
  seenAddr = {}
  seenName = {}
  for d in ioregDevices
    d.name or= (d.address and sp.names[d.address]) or 'Bluetooth device'
    seenAddr[d.address] = true if d.address
    seenName[d.name] = true
    devices.push d
  for d in sp.devices
    continue if (d.address and seenAddr[d.address]) or seenName[d.name]
    seenName[d.name] = true
    devices.push d

  div = $(domEl)

  # Hide the widget when no peripherals are reporting a battery.
  if devices.length is 0
    div.animate({opacity: 0}, 1000, 'swing').hide(1)
    return

  $devices = div.find('.devices').empty()
  for d in devices
    color = @deviceBarColor(d.percent)
    bolt  = if d.charging then '<span class="charge-bolt"></span>' else ''
    $devices.append """
      <div class="device-row">
        <div class="device-header">
          <div class="device-name">#{@esc(d.name)}</div>
          <div class="device-percent">#{bolt}#{d.percent}%</div>
        </div>
        <div class="device-bar-track"><div class="device-bar-fill" style="width: #{d.percent}%; background: #{color}"></div></div>
      </div>
    """

  div.show(1).animate({opacity: 1}, 250, 'swing')
