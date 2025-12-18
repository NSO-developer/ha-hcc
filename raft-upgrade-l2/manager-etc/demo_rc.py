#!/usr/bin/env python3
"""A Python RESTCONF HA Raft failover example.

Demo script

See the README file for more information
"""
import json
from multiprocessing import Process
import os
import time
import paramiko
import requests

from paramiko.ssh_exception import SSHException
from paramiko.buffered_pipe import PipeTimeout as PipeTimeout
from socket import timeout as SocketTimeout
from socket import error as SocketError


def on_node(host, cmd):
    okblue = '\033[94m'
    endc = '\033[0m'
    print(f"{okblue}On " + host + f" CLI:{endc} " + cmd + "\n", flush=True)
    ssh = paramiko.SSHClient()
    # Paramiko cannot handle multiple host keys host
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(host, port=2024, username="admin", key_filename=os.path.join(os.path.expanduser('~'), ".ssh", "id_ed25519"))
    stdin, stdout, stderr = ssh.exec_command(cmd)
    output = stdout.read().decode('utf-8')
    err = stderr.read().decode('utf-8')
    ssh.close()
    print(f'{output} {err}', flush=True)
    return output


def on_node_sh(host, username, cmd):
    output = err = ""
    header = '\033[95m'
    okblue = '\033[94m'
    endc = '\033[0m'
    print(f"{okblue}On " + host + f":{endc} " + cmd + "\n", flush=True)
    ssh = paramiko.SSHClient()
    # Paramiko cannot handle multiple host keys host
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(host, username=username, key_filename=os.path.join(os.path.expanduser('~'), ".ssh", "id_ed25519"))
    try:
        _, stdout, stderr = ssh.exec_command(cmd, timeout=1)
        output = stdout.read().decode('utf-8')
        err = stderr.read().decode('utf-8')
    except (SSHException, PipeTimeout, SocketTimeout, SocketError) as e:
        print(f"{header}Exception executing \"{cmd}\" on {host} {e}{endc}", flush=True)
    ssh.close()
    print(f'{output} {err}', flush=True)
    return output


def ha_demo():
    """Run the HA Raft demo"""
    node1 = os.getenv('NODE1')
    node2 = os.getenv('NODE2')
    node3 = os.getenv('NODE3')
    nso_vip = os.getenv('NSO_VIP')
    vip_url = 'https://{}:8888/restconf'.format(nso_vip)
    node1_url = 'https://{}:8888/restconf'.format(node1)
    node2_url = 'https://{}:8888/restconf'.format(node2)
    node3_url = 'https://{}:8888/restconf'.format(node3)
    node_urls = [node1_url,node2_url,node3_url]

    header = '\033[95m'
    okblue = '\033[94m'
    okgreen = '\033[92m'
    endc = '\033[0m'
    bold = '\033[1m'

    print(f"\n{okgreen}##### VIP address: " + nso_vip + f"\n{endc}", flush=True)

    print(f"{okblue}##### Get a token for RESTCONF authentication\n{endc}", flush=True)
    vip_key = on_node(nso_vip, "generate-token")
    vip_key = vip_key.split(" ")[1].rstrip('\r\n')

    vip_key

    requests.packages.urllib3.disable_warnings(
        requests.packages.urllib3.exceptions.InsecureRequestWarning)
    headers = {'Content-Type': 'application/yang-data+json',
                     'X-Auth-Token': vip_key, 'Host': nso_vip}

    print(f"{okblue}##### Get the current leader name\n{endc}", flush=True)
    current_leader = "none"
    while True:
        path = '/data/tailf-ncs-high-availability-raft:ha-raft/status/local-node?content=nonconfig'
        print(f"{bold}GET " + vip_url + path + f"{endc}", flush=True)
        try:
            r = requests.get(vip_url + path, headers=headers, verify=False)
        except (SSHException, PipeTimeout, SocketTimeout, SocketError) as e:
            print(f"{header}Exception getting the current leader: {e}\n{endc}", flush=True)
        else:
            if "local-node" in r.text:
                current_leader = r.json()["tailf-ncs-high-availability-raft:local-node"]
                break
        print(f"{header}##### Waiting for the VIP address {nso_vip} to point to the leader...\n{endc}", flush=True)
        time.sleep(1)

    print(f"\n{okgreen}##### Current leader node: {okblue}{current_leader}\n{endc}", flush=True)

    print(f"{okblue}##### HA Raft status\n{endc}", flush=True)
    path = '/data/tailf-ncs-high-availability-raft:ha-raft?content=nonconfig'
    print(f"{bold}GET " + vip_url + path + f"{endc}", flush=True)
    r = requests.get(vip_url + path, headers=headers, verify=False)
    print(r.text, flush=True)

    print(f"{okblue}##### tailf-hcc config\n{endc}", flush=True)
    path = '/data/tailf-hcc:hcc?content=config&with-defaults=report-all'
    print(f"{bold}GET " + vip_url + path + f"{endc}", flush=True)
    r = requests.get(vip_url + path, headers=headers, verify=False)
    print(r.text, flush=True)

    print(f"{okgreen}##### Test failover\n{endc}", flush=True)

    print(f"{okblue}##### Add some dummy config to the leader\n{endc}", flush=True)
    dummy_data = {}
    dummy_data["name"] = "d42"
    dummy_data["dummy"] = "42.42.42.42"
    dummies_data = {}
    dummies_data["dummy"] = [dummy_data]
    input_data = {"dummy:dummies": dummies_data}

    path = '/data'
    print(f"{bold}PATCH " + vip_url + path + f"{endc}", flush=True)
    print(f"{header}" + json.dumps(input_data, indent=2) + f"{endc}", flush=True)
    r = requests.patch(vip_url + path, json=input_data, headers=headers,
                      verify=False)
    print("Status code: {}\n".format(r.status_code), flush=True)

    print(f"{okblue}##### Replicated to all nodes\n{endc}", flush=True)
    for node_url in node_urls:
        path = '/data/dummy:dummies'
        print(f"{bold}GET " + node_url + path + f"{endc}", flush=True)
        r = requests.get(node_url + path, headers=headers, verify=False)
        print(r.text, flush=True)

    print(f"{okblue}##### Observe a failover by bringing down current leader\n{endc}", flush=True)
    process = Process(target=on_node_sh, args=(nso_vip, "admin", '$NCS_DIR/bin/ncs --stop'))
    process.start()
    print(f"{okblue}##### Exception expected as the NSO container restarts\n{endc}", flush=True)

    print(f"{okblue}##### Get the new leader name\n{endc}", flush=True)
    while True:
        path = '/data/tailf-ncs-high-availability-raft:ha-raft/status/local-node?content=nonconfig'
        print(f"{bold}GET " + vip_url + path + f"{endc}", flush=True)
        try:
            r = requests.get(vip_url + path, headers=headers, verify=False)
        except (SSHException, PipeTimeout, SocketTimeout, SocketError) as e:
            print(f"{header}Exception getting the new leader {e}\n{endc}", flush=True)
        else:
            if "local-node" in r.text:
                leader = r.json()["tailf-ncs-high-availability-raft:local-node"]
                if leader != current_leader:
                    break
        print(f"{header}##### Waiting for the VIP address {nso_vip} to point to the new leader...\n{endc}", flush=True)
        time.sleep(1)
    prev_leader = current_leader
    current_leader = leader
    print(f"{okgreen}##### Current leader: {okblue}{current_leader} {okgreen}Previous leader: {okblue}{prev_leader}\n{endc}", flush=True)

    print(f"{okblue}##### Add additional config on the leader {current_leader}\n{endc}", flush=True)
    dummy_data = {}
    dummy_data["name"] = "d42-new"
    dummy_data["dummy"] = "24.24.24.24"
    dummies_data = {}
    dummies_data["dummy"] = [dummy_data]
    input_data = {"dummy:dummies": dummies_data}

    path = '/data'
    print(f"{bold}PATCH " + vip_url + path + f"{endc}", flush=True)
    print(f"{header}" + json.dumps(input_data, indent=2) + f"{endc}", flush=True)
    r = requests.patch(vip_url + path, json=input_data, headers=headers,
                      verify=False)
    print("Status code: {}\n".format(r.status_code), flush=True)

    print(f"{okblue}##### Show that the new config is replicated to all remaining nodes\n{endc}", flush=True)
    prev_leader_url = f'https://{prev_leader}:8888/restconf'
    curr_leader_url = f'https://{current_leader}:8888/restconf'
    for node_url in node_urls:
        if node_url != curr_leader_url and node_url != prev_leader_url:
            path = '/data/dummy:dummies'
            print(f"{bold}GET " + node_url + path + f"{endc}", flush=True)
            r = requests.get(node_url + path, headers=headers, verify=False)
            print(r.text, flush=True)

    print(f"{okblue}##### Wait for {prev_leader} to come back and follow the new leader {current_leader}\n{endc}", flush=True)
    while True:
        path = '/data/tailf-ncs-high-availability-raft:ha-raft/status/leader?content=nonconfig'
        print(f"{bold}GET " + prev_leader_url + path + f"{endc}", flush=True)
        try:
            r = requests.get(prev_leader_url + path, headers=headers, verify=False)
        except (SSHException, PipeTimeout, SocketTimeout, SocketError) as e:
            print(f"{header}Exception getting the new from the previous leader {e}\n{endc}", flush=True)
        else:
            if "leader" in r.text:
                leader = r.json()["tailf-ncs-high-availability-raft:leader"]
                if leader == current_leader:
                    break
        print(f"{header}##### Waiting for {prev_leader} to come back and follow {current_leader}...\n{endc}", flush=True)
        time.sleep(1)

    print(f"\n{okblue}##### Observe that the new data is replicated to {prev_leader} as well\n{endc}", flush=True)
    path = '/data/dummy:dummies'
    print(f"{bold}GET " + prev_leader_url + path + f"{endc}", flush=True)
    r = requests.get(prev_leader_url + path, headers=headers, verify=False)
    print(r.text, flush=True)

    print(f"{okgreen}##### Done!\n{endc}", flush=True)


if __name__ == "__main__":
    ha_demo()
