# ------------------------------------------------------------
# osc_transmitter.be
# Sends OSC message OSC_TARGET_ADDR via UDP
# on POWER state changes when network is available
# Compatible with Tasmota 15.2.0
# ------------------------------------------------------------

# ========= Global target configuration =========
var OSC_TARGET_IP   = "192.168.71.24"
var OSC_TARGET_PORT = 22221

var OSC_TARGET_ADDR = "/powerstat/SetValue"


# ========= Guard to avoid double loading =========
var _osc_tx_module_loaded = false

if _osc_tx_module_loaded
  print("OSC TX module already loaded")
  return
end

_osc_tx_module_loaded = true

print("OSC TX module starting")

# ========= Helper functions =========

# Network is up if WiFi or Ethernet has an IP address
def network_up()
  return (tasmota.wifi("ip") != nil) || (tasmota.eth("ip") != nil)
end

# Build OSC string (null-terminated, padded to 4 bytes)
def osc_string(s)
  var b = bytes()
  b.fromstring(s)
  b.add(0, 1)
  while (b.size() % 4) != 0
    b.add(0, 1)
  end
  return b
end

# Build OSC int32 (big-endian)
def osc_int32(v)
  var b = bytes()
  b.add(v, -4)
  return b
end

# Build OSC message for power state
def osc_power_message(value)
  var msg = osc_string(OSC_TARGET_ADDR)
  msg .. osc_string(",i")
  msg .. osc_int32(value)
  return msg
end

# ========= Driver =========

class OscPowerDriver
  var udp_sock
  var udp_ready

  def init()
    self.udp_sock = udp()
    self.udp_ready = false
    tasmota.add_driver(self)
    print("OSC power driver registered")
  end

  # Initialize UDP socket lazily
  def ensure_udp()
    if self.udp_ready return true end
    self.udp_ready = self.udp_sock.begin("", 0)
    return self.udp_ready
  end

  # Send OSC power message
  def send_power(value)
    if !network_up()
      return
    end
    if !self.ensure_udp()
      return
    end

    var payload = osc_power_message(value)
    self.udp_sock.send(OSC_TARGET_IP, OSC_TARGET_PORT, payload)
  end

  # Called by Tasmota on POWER state change
  # idx is a bitmask (bit 0 = POWER1)
  def set_power_handler(cmd, idx)
    var power1_on = (idx & 1) != 0
    self.send_power(power1_on ? 1 : 0)
  end
end

# ========= Start driver =========
OscPowerDriver()
