"""Development SSH helper; commands are passed as data, never through a local shell."""
import argparse
import base64
import json
from pathlib import Path
import shlex
import sys

import paramiko


def connect():
    data = Path.home() / 'AppData/Local/RKVisionHost'
    client = paramiko.SSHClient()
    client.load_host_keys(str(data / 'known_hosts'))
    client.connect('169.254.53.76', username='root',
                   key_filename=str(data / 'rk_host_rsa'), look_for_keys=False,
                   allow_agent=False, timeout=8)
    return client


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('exec', 'python', 'rpc', 'pull', 'push', 'get'))
    parser.add_argument('value')
    parser.add_argument('target', nargs='?')
    args = parser.parse_args()
    client = connect()
    try:
        if args.action in ('pull', 'push', 'get'):
            with client.open_sftp() as sftp:
                if args.action == 'pull':
                    target = Path(args.target)
                    target.mkdir(parents=True, exist_ok=True)
                    for item in sftp.listdir_attr(args.value):
                        if item.filename.endswith(('.py', '.sh', '.c', '.h')):
                            sftp.get(args.value + '/' + item.filename, str(target / item.filename))
                elif args.action == 'get':
                    target = Path(args.target)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    sftp.get(args.value, str(target))
                else:
                    sftp.put(args.value, args.target)
            return
        if args.action == 'python':
            code = Path(args.value).read_text(encoding='utf-8')
            encoded = base64.b64encode(code.encode()).decode()
            command = 'python3 -u -c ' + shlex.quote(
                'import base64;exec(base64.b64decode(' + repr(encoded) + '))')
        elif args.action == 'rpc':
            encoded = base64.b64encode(args.value.encode()).decode()
            command = 'python3 /root/jpeg_rk/pc_host_agent_v1.py work ' + shlex.quote(encoded)
        else:
            command = args.value
        _, out, err = client.exec_command(command, timeout=180)
        for line in out:
            print(line, end='', flush=True)
        sys.stderr.write(err.read().decode('utf-8', errors='replace'))
        code = out.channel.recv_exit_status()
        if code:
            raise SystemExit(code)
    finally:
        client.close()


if __name__ == '__main__':
    main()
