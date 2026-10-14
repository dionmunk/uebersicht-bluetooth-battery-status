command: "(ioreg -r -l -k BatteryPercent | grep -E '[+]-o|\"(Product|BatteryPercent|DeviceAddress)\"' ; echo '---SEP---' ; system_profiler -json SPBluetoothDataType 2>/dev/null)"

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

# Normalise a Bluetooth address so ioreg's "1c-f6-4c-03-7d-b0" and
# system_profiler's "1C:F6:4C:03:7D:B0" compare equal.
normAddr: (a) ->
  if a then String(a).toLowerCase().replace(/[^0-9a-f]/g, '') else null

# Parse the ioreg block. Each device starts at a "+-o" node line and carries
# Product / DeviceAddress / BatteryPercent, read per node in any order.
# Product can be blank on recent macOS (Magic Mouse, macOS 26), so the address
# is kept and the name is looked up from system_profiler instead.
parseIoreg: (text) ->
  devices = []
  cur = null
  start = -> {name: null, address: null, percent: null}
  flush = ->
    devices.push cur if cur? and cur.percent?
    cur = null
  for line in text.split('\n')
    if /\+-o/.test(line)
      flush()
      cur = start()
    else if (m = line.match /"Product"\s*=\s*"([^"]+)"/)
      cur ?= start()
      cur.name = m[1].replace(/-/g, ' ')
    else if (m = line.match /"DeviceAddress"\s*=\s*"([^"]+)"/)
      cur ?= start()
      cur.address = @normAddr(m[1])
    else if (m = line.match /"BatteryPercent"\s*=\s*(\d+)/)
      cur ?= start()
      cur.percent = parseInt(m[1], 10)
  flush()
  devices

# Parse system_profiler JSON. Returns {devices, names}:
#   devices - connected devices that report a battery (e.g. keyboard, AirPods,
#             which report Case / Left / Right separately)
#   names   - address -> display name for EVERY connected device, so ioreg
#             batteries with a blank Product can be named.
parseSystemProfiler: (jsonText) ->
  result = {devices: [], names: {}}
  return result unless jsonText
  try
    data = JSON.parse(jsonText)
  catch e
    return result
  toPct = (v) ->
    return null unless v?
    n = parseInt(v, 10)
    if isNaN(n) then null else n
  for controller in (data?.SPBluetoothDataType or [])
    for entry in (controller?.device_connected or [])
      for rawName, info of entry
        name    = rawName.replace(/-/g, ' ')
        address = @normAddr(info?.device_address)
        result.names[address] = name if address
        add = (label, v) ->
          p = toPct(v)
          result.devices.push({name: label, address: address, percent: p}) if p?
        add name, info?.device_batteryLevelMain
        add "#{name} (Case)",  info?.device_batteryLevelCase
        add "#{name} (Left)",  info?.device_batteryLevelLeft
        add "#{name} (Right)", info?.device_batteryLevelRight
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

  # Merge. ioreg wins when both report the same device (matched by Bluetooth
  # address). An ioreg battery with a blank Product borrows its name from
  # system_profiler via that address. Split batteries (AirPods case/left/right)
  # share one address, so system_profiler entries are otherwise deduped by name.
  devices  = []
  seenAddr = {}
  seenName = {}
  for d in ioregDevices
    name = d.name or (d.address and sp.names[d.address]) or 'Bluetooth device'
    devices.push {name: name, percent: d.percent}
    seenAddr[d.address] = true if d.address
    seenName[name] = true
  for d in sp.devices
    continue if d.address and seenAddr[d.address]
    continue if seenName[d.name]
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
