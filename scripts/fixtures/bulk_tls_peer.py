"""Loopback-only peer for binary-transfer framing/integrity integration tests."""
import hashlib
import json
import socket
import ssl
import sys

context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(sys.argv[1], sys.argv[2])
listener = socket.socket()
listener.bind(('127.0.0.1', 0))
listener.listen(4)
listener.settimeout(30)
print(listener.getsockname()[1], flush=True)
body = bytes(range(256)) * (96 * 1024 + 3)  # More than the old 20 MiB ceiling.
for _ in range(3):
    connection, _ = listener.accept()
    with context.wrap_socket(connection, server_side=True) as stream:
        stream.settimeout(30)
        header = bytearray()
        while not header.endswith(b'\n'):
            header.extend(stream.recv(1))
        request = json.loads(header)
        direction = request['payload']['direction']
        ready = json.dumps({'version': 1, 'id': 'test', 'type': 'bulkReady', 'payload': {}}).encode() + b'\n'
        stream.sendall(ready[:7])
        if direction == 'download':
            stream.sendall(ready[7:] + body[:256])
            stream.sendall(body[256:])
        else:
            stream.sendall(ready[7:])
            digest = hashlib.sha256()
            received = 0
            while received < len(body):
                block = stream.recv(min(262144, len(body) - received))
                if not block:
                    raise RuntimeError('Truncated upload')
                received += len(block)
                digest.update(block)
            if digest.digest() != hashlib.sha256(body).digest():
                raise RuntimeError('Upload checksum mismatch')
            stream.sendall(json.dumps({'version': 1, 'id': 'test', 'type': 'bulkComplete', 'payload': {}}).encode() + b'\n')
listener.close()
