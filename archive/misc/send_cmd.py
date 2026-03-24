import zmq, time, json, sys
ctx = zmq.Context()

# Also subscribe to ACK channel (5559) to confirm command receipt
ack = ctx.socket(zmq.SUB)
ack.setsockopt_string(zmq.SUBSCRIBE, "")
ack.connect("tcp://127.0.0.1:5559")

s = ctx.socket(zmq.PUB)
s.connect("tcp://127.0.0.1:5557")
time.sleep(0.5)

cmd = json.dumps({"cmd": "load_state", "path": "/mnt/d/fractal-brain/beast-build/ckpt_20260319_133430_c7521391.bin"})
s.send_string(cmd)
print(f"Sent: {cmd}")

# Wait for ACK
poller = zmq.Poller()
poller.register(ack, zmq.POLLIN)
events = dict(poller.poll(5000))
if ack in events:
    reply = ack.recv_string()
    print(f"ACK: {reply}")
else:
    print("No ACK received within 5s (check v4 logs)")

s.close()
ack.close()
ctx.term()
print("Done")
