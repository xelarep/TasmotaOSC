# autoexec.be
# load an run external modules
# xelarep, 29-DEC-2025

print("'autoexec.be' started.")

# load and run external files

if load("/osc_transmitter.be")
  print("'/osc_transmitter.be' loaded succesfully.")
else
  print("ERROR: unable to load '/osc_transmitter.be'?!")
end

if load("/osc_receiver.be")
  print("'/osc_receiver.be' loaded succesfully.")
else
  print("ERROR: unable to load '/osc_receiver.be'?!")
end
