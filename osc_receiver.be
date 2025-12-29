# ------------------------------------------------------------
# osc_receiver.be
# Listens for OSC /powerstat/SetValue (int32 0/1) via UDP
# and toggles POWER accordingly (0=OFF, 1=ON)
# Compatible with Tasmota 15.2.0
# xelarep 29-DEC-2025
# ------------------------------------------------------------

# ========= Global listen configuration =========
var OSC_LISTEN_PORT = 57896
var OSC_LISTEN_ADDR = "/tasmota/power"

# ========= Global reload guard =========
var _osc_rx_module_loaded = false
if _osc_rx_module_loaded
  print("OSC RX module already loaded")
  return
end
_osc_rx_module_loaded = true

print("OSC RX module starting")

# ========= Driver =========

class OscReceiverDriver
  var sock
  var listening

  def init()
    self.sock = udp()
    self.listening = false
    tasmota.add_driver(self)
    print("OSC RX driver registered")
  end

  def ensure_listen()
    if self.listening return true end
    if !network_up() return false end

    # Bind to all interfaces on OSC_LISTEN_PORT
    self.listening = self.sock.begin("", OSC_LISTEN_PORT)
    if self.listening
      print("OSC RX listening on UDP port " + str(OSC_LISTEN_PORT))
    end
    return self.listening
  end

  # ---------- helpers ----------
  # Network is up if WiFi or Ethernet has an IP address
  def network_up()
    return (tasmota.wifi("ip") != nil) || (tasmota.eth("ip") != nil)
  end

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

  def every_50ms()
    # Try to (re)start listening when network becomes available
    if !self.ensure_listen()
      return
    end

    # Non-blocking receive
    var pkt = self.sock.read()
    if pkt == nil
      return
    end

    var msg = self.parse_osc_1arg(pkt)
    if msg == nil return end

    if msg["addr"] == OSC_LISTEN_ADDR && msg["type"] == "i"
      var v = int(msg["arg"])
      if v > 0
        tasmota.cmd("Power ON")
      else
        tasmota.cmd("Power OFF")
      end
    end    
    
  end
end

# ========= Start driver =========
OscReceiverDriver()
