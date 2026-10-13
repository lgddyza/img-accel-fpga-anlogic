"""One serialized RPC stream over SSH or an existing root serial shell."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import sys
import time
import uuid
import zlib

import paramiko
import serial

DATA_DIR = Path(os.environ.get('LOCALAPPDATA', str(Path.home()))) / 'RKVisionHost'
REMOTE = '/root/jpeg_rk/pc_host_agent_v1.py'


def asset(name):
    return Path(getattr(sys, '_MEIPASS', Path(__file__).parent)) / name


def default_key():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    path = DATA_DIR / 'rk_host_rsa'
    if not path.exists():
        paramiko.RSAKey.generate(2048).write_private_key_file(str(path))
    return path


def no_fiq(value):
    # The RK UART debug handler interprets this substring even inside a payload.
    return re.sub('(?i)fiq', lambda m: m[0][0]+' '+m[0][1:], value)


def encoded_code(code):
    data = no_fiq(base64.b64encode(code.encode()).decode())
    return "python3 -c " + shlex.quote("import base64;exec(base64.b64decode("+repr(data)+"))")


class RpcError(RuntimeError):
    pass


class SerialTransport:
    def __init__(self, options):
        self.port = serial.Serial(options['port'], options['baud'], timeout=.1,
                                  write_timeout=3, dsrdtr=False, rtscts=False)
        self.port.write(b'\r')
        time.sleep(.25)
        self.port.reset_input_buffer()

    def execute(self, command, marker, timeout=8):
        self.port.reset_input_buffer()
        if len(command.encode()) > 3800:
            raise RpcError('Serial shell command exceeds canonical input limit')
        self.port.write(command.encode('ascii')+b'\r')
        data = bytearray()
        deadline = time.monotonic()+timeout
        pattern = re.compile(rb'(?:^|[\r\n])' + re.escape(marker.encode()) + rb'([^\r\n]*)[\r\n]')
        while time.monotonic() < deadline:
            data.extend(self.port.read(max(1, self.port.in_waiting)))
            match = pattern.search(data)
            if match:
                return match[1].decode('utf-8', errors='replace')
            if len(data) > 100000:
                del data[:-60000]
        raise RpcError('RK 串口响应超时，请确认 root shell 已登录、板卡供电及波特率')

    def install(self):
        raw = asset('board_agent.py').read_bytes()
        payload = zlib.compress(raw)
        staging = REMOTE + '.upload'
        for i in range(0, len(payload), 1800):
            token = uuid.uuid4().hex
            data = base64.b64encode(payload[i:i+1800]).decode()
            code = f"import base64;open({staging!r},{'wb' if i == 0 else 'ab'!r}).write(base64.b64decode({data!r}));print('UP_{token}:OK')"
            # Double encoding would exceed the shell limit; split the actual write chunk.
            if len(encoded_code(code)) > 3800:
                raise RpcError('Upload chunk exceeds input limit')
            self.execute(encoded_code(code), 'UP_'+token+':', 10)
        token = uuid.uuid4().hex
        sha = hashlib.sha256(raw).hexdigest()
        code = (f"import pathlib,zlib,hashlib,os;p=pathlib.Path({staging!r});d=zlib.decompress(p.read_bytes());"
                f"assert hashlib.sha256(d).hexdigest()=={sha!r};p.write_bytes(d);os.replace(p,{REMOTE!r});"
                f"print('UP_{token}:OK')")
        self.execute(encoded_code(code), 'UP_'+token+':', 10)

    def rpc(self, request):
        token = uuid.uuid4().hex
        data = no_fiq(base64.b64encode(json.dumps(request).encode()).decode())
        line = f"python3 -u {REMOTE} {token} {shlex.quote(data)}"
        return decode_response(self.execute(line, 'RKRPC_'+token+':', 25))

    def close(self):
        self.port.close()


class SSHTransport:
    def __init__(self, options):
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        self.client = paramiko.SSHClient()
        known = DATA_DIR / 'known_hosts'
        if known.exists():
            self.client.load_host_keys(str(known))
        self.client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        try:
            self.client.connect(options['host'], port=options.get('ssh_port', 22),
                                username=options.get('username', 'root'),
                                password=options.get('password') or None,
                                key_filename=options.get('key') or None,
                                look_for_keys=False, allow_agent=False, timeout=6,
                                auth_timeout=8, banner_timeout=8)
            self.client.save_host_keys(str(known))
            self.client.get_transport().set_keepalive(10)
        except Exception:
            self.client.close()
            raise

    def install(self):
        with self.client.open_sftp() as sftp:
            data = asset('board_agent.py').read_bytes()
            with sftp.open(REMOTE+'.upload', 'wb') as handle:
                handle.write(data)
            with sftp.open(REMOTE+'.upload', 'rb') as handle:
                if hashlib.sha256(handle.read()).digest() != hashlib.sha256(data).digest():
                    raise RpcError('RK agent upload hash mismatch')
            sftp.posix_rename(REMOTE+'.upload', REMOTE)

    def rpc(self, request):
        token = uuid.uuid4().hex
        data = base64.b64encode(json.dumps(request).encode()).decode()
        command = f'python3 -u {REMOTE} {token} {shlex.quote(data)}'
        _, stdout, stderr = self.client.exec_command(command, timeout=25)
        response = stdout.read(150000).decode('utf-8', errors='replace')
        marker = 'RKRPC_'+token+':'
        lines = [line[len(marker):] for line in response.splitlines() if line.startswith(marker)]
        if not lines:
            raise RpcError('RK 未返回状态：'+stderr.read(3000).decode(errors='replace'))
        return decode_response(lines[-1])

    def close(self):
        self.client.close()


def decode_response(line):
    response = json.loads(line)
    if not response.get('ok'):
        raise RpcError(response.get('error', 'Unknown RK error'))
    return response['data']


def provision_key(port='COM12', baud=1500000):
    key = paramiko.RSAKey.from_private_key_file(str(default_key()))
    public = key.get_name()+' '+key.get_base64()+' rk-vision-host'
    code = ("from pathlib import Path;import os;p=Path('/root/.ssh');p.mkdir(mode=448,exist_ok=True);"
            "os.chmod(p,448);f=p/'authorized_keys';t=f.read_text() if f.exists() else '';"
            f"k={public!r};f.write_text(t if k in t.splitlines() else t.rstrip()+'\\n'+k+'\\n');"
            "os.chmod(f,384);print('KEY_READY:OK')")
    connection = SerialTransport({'port': port, 'baud': baud})
    try:
        return connection.execute(encoded_code(code), 'KEY_READY:', 10)
    finally:
        connection.close()
