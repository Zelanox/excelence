import socket

s = socket.socket()
s.settimeout(5)

try:
    s.connect(("192.168.10.232", 5000))
    print("SUCCESS")
except Exception as e:
    print(e)