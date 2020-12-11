#!/teoco/helix_web/tti3rd/python/bin/python
import socket
import sys
hostname = sys.argv[1]
ip = socket.gethostbyname(hostname)
print(ip)
