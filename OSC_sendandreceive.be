# =========================================================
# OSC Monitor + Listener (Tasmota Berry) 
# =========================================================
# 3rd Advent edition ***
# created after an initial discussion at https://github.com/arendst/Tasmota/discussions/24202 the help @Staars
# reduced, modified, adapted and successfully tested with the Tasmota32 Berry requirements of an out-of-the-box NOUS A8T WiFi socket 
#
# Start/Stop per CONFIG switches below.
# - Listener: receives OSC /power ,i (0/1) and switches power OFF/ON
# - Monitor: reads power status and sends OSC /power ,i (0/1) when it changes
#

# ================================
# CONFIG (STARTS HERE)
# ================================
var ENABLE_LISTENER = true
var ENABLE_MONITOR  = true

# ---- OSC Receive (Listener) ----
var LISTEN_PORT    = 57896
var LISTEN_ADDRESS = "/tasmota/power"

# ---- OSC Send (Monitor) ----
var TARGET_IP      = "192.168.71.24"
var TARGET_PORT    = 22221
var TARGET_ADDRESS = "/powerstat/SetValue"

# ================================
# OSC POWER MONITOR (Sender)
# ================================
class OSC_Power_Monitor : Driver
  var u
  var last_power

  def init()
    self.u = udp()
    self.u.begin("", 0)            # send-only, random source port
    self.last_power = nil
    tasmota.add_driver(self)
    print("OSC Power Monitor started for", TARGET_IP, ":", TARGET_PORT)
  end

  # ---- OSC helpers ----

  # Append OSC string: raw bytes of s + NUL + pad to 4
  def add_osc_string(b, s)
    var tmp = bytes(0)
    tmp.fromstring(s)
    b .. tmp

    b.add(0, 1)                    # NUL terminator
    while (size(b) & 3) != 0
      b.add(0, 1)                  # pad to 4-byte boundary
    end
  end

  # Append OSC int32 big-endian
  def add_osc_int32(b, v)
    b.add(int(v), -4)              # 4 bytes, big-endian
  end

  # ---- read relay state via Status 0 ----
  # returns 1 (ON), 0 (OFF) or nil
  def get_power01()
    var s = tasmota.cmd("Status 0")
    if s == nil return nil end
    var sts = s["StatusSTS"]
    if sts == nil return nil end
    var p = sts["POWER"]           # "ON"/"OFF"
    if p == nil return nil end
    return (p == "ON") ? 1 : 0
  end

  def send_osc_power(x)
    var b = bytes(0)
    self.add_osc_string(b, TARGET_ADDRESS)
    self.add_osc_string(b, ",i")
    self.add_osc_int32(b, x)
    self.u.send(TARGET_IP, TARGET_PORT, b)
  end

  def every_second()
    var cur = self.get_power01()
    if cur == nil return end

    if self.last_power == nil
      self.last_power = cur
      return
    end

    if cur != self.last_power
      self.last_power = cur
      self.send_osc_power(cur)
    end
  end
end


# ================================
# OSC RECEIVER (Listener)
# ================================
class OSC_Receiver : Driver
  var udp_server

  def init(port)
    self.udp_server = udp()
    self.udp_server.begin("", port)
    tasmota.add_driver(self)
    print("OSC Listener started on port:", port)
  end

  def every_50ms()
    var packet = self.udp_server.read()
    if packet == nil return end

    var msg = self.parse_osc_1arg(packet)
    if msg == nil return end

    if msg["addr"] == LISTEN_ADDRESS && msg["type"] == "i"
      var v = int(msg["arg"])
      if v > 0
        tasmota.cmd("Power ON")
      else
        tasmota.cmd("Power OFF")
      end
    end
  end

  # ---------- helpers ----------
  def _align4(ofs)
    return (ofs + 3) & ~3
  end

  # read C-string, return [string, aligned_ofs]
  def _read_cstring(buf, ofs)
    var start = ofs
    while ofs < size(buf) && buf[ofs] != 0
      ofs += 1
    end
    if ofs >= size(buf) return nil end

    var s = ""
    if ofs > start
      s = (buf[start..ofs-1]).asstring()
    end

    ofs += 1
    ofs = self._align4(ofs)
    return [s, ofs]
  end

  # ---------- OSC parser (ONE ARG ONLY) ----------
  # returns: { addr: string, type: string, arg: value }
  def parse_osc_1arg(buf)
    var ofs = 0

    # address
    var r = self._read_cstring(buf, ofs)
    if r == nil return nil end
    var addr = r[0]
    ofs = r[1]

    # typetag string (must be ",x")
    if ofs >= size(buf) || buf[ofs] != 0x2C   # ','
      return nil
    end
    if ofs + 1 >= size(buf)
      return nil
    end

    var t = format("%c", buf[ofs + 1])  # single typetag

    # skip ",x\0" and align
    ofs += 2
    if ofs >= size(buf) return nil end
    if buf[ofs] != 0 return nil end
    ofs += 1
    ofs = self._align4(ofs)

    # parse ONE argument
    var arg
    if t == "i"
      if ofs + 4 > size(buf) return nil end
      arg = buf.geti(ofs, -4)
    elif t == "f"
      if ofs + 4 > size(buf) return nil end
      arg = buf.getfloat(ofs, true)
    elif t == "s"
      r = self._read_cstring(buf, ofs)
      if r == nil return nil end
      arg = r[0]
    elif t == "T"
      arg = true
    elif t == "F"
      arg = false
    else
      return nil
    end

    return { "addr": addr, "type": t, "arg": arg }
  end
end


# ================================
# STARTUP (BASED ON CONFIG)
# ================================
var osc_listener = nil
var osc_monitor  = nil

if ENABLE_LISTENER
  osc_listener = OSC_Receiver(LISTEN_PORT)
end

if ENABLE_MONITOR
  osc_monitor = OSC_Power_Monitor()
end
