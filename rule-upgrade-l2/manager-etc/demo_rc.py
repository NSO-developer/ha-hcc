#!/usr/bin/env python3
"""A Python RESTCONF HA Raft failover example.

Demo script
(C) 2024 Tail-f Systems
Permission to use this code as a starting point hereby granted

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
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(host, port=2024, username="admin",
    key_filename = os.path.join(os.path.expanduser('~'), ".ssh", "id_ed25519"))
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
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(host, username=username,
    key_filename=os.path.join(os.path.expanduser('~'), ".ssh", "id_ed25519"))
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
    """Run the rule-based HA demo"""
    node1 = os.getenv('NODE1')
    node2 = os.getenv('NODE2')
    nso_vip = os.getenv('NSO_VIP')
    vip_url = 'https://{}:8888/restconf'.format(nso_vip)
    node1_url = 'https://{}:8888/restconf'.format(node1)
    node2_url = 'https://{}:8888/restconf'.format(node2)
    node_urls = [node1_url,node2_url]

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

    print(f"{okblue}##### Get the current primary name\n{endc}", flush=True)
    current_primary = "none"
    while True:
        path = '/data/tailf-ncs:high-availability/status/current-id?content=nonconfig'
        print(f"{bold}GET " + vip_url + path + f"{endc}", flush=True)
        try:
            r = requests.get(vip_url + path, headers=headers, verify=False)
        except (SSHException, PipeTimeout, SocketTimeout, SocketError) as e:
            print(f"{header}Exception getting the current primary: {e}\n{endc}", flush=True)
        else:
            if "current-id" in r.text:
                current_primary = r.json()["tailf-ncs:current-id"]
                break
        print(f"{header}##### Waiting for the VIP address {nso_vip} to point to the primary...\n{endc}", flush=True)
        time.sleep(1)

    print(f"\n{okgreen}##### Current primary node: {okblue}{current_primary}\n{endc}", flush=True)

    print(f"{okblue}##### Built-in HA status\n{endc}", flush=True)
    path = '/data/tailf-ncs:high-availability?content=nonconfig'
    print(f"{bold}GET " + vip_url + path + f"{endc}", flush=True)
    r = requests.get(vip_url + path, headers=headers, verify=False)
    print(r.text, flush=True)

    print(f"{okblue}##### tailf-hcc config\n{endc}", flush=True)
    path = '/data/tailf-hcc:hcc?content=config&with-defaults=report-all'
    print(f"{bold}GET " + vip_url + path + f"{endc}", flush=True)
    r = requests.get(vip_url + path, headers=headers, verify=False)
    print(r.text, flush=True)

    print(f"{okgreen}##### Test failover\n{endc}", flush=True)

    print(f"{okblue}##### Add some dummy config to the primary\n{endc}", flush=True)
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

    print(f"{okblue}##### Get the reconnect settings\n{endc}", flush=True)
    path = '/data/tailf-ncs:high-availability/settings/reconnect-interval?content=config'
    print(f"{bold}GET " + vip_url + path + f"{endc}", flush=True)
    r = requests.get(vip_url + path, headers=headers, verify=False)
    print(r.text, flush=True)
    if "reconnect-interval" in r.text:
        ri = r.json()["tailf-ncs:reconnect-interval"]

    path = '/data/tailf-ncs:high-availability/settings/reconnect-attempts?content=config'
    print(f"{bold}GET " + vip_url + path + f"{endc}", flush=True)
    r = requests.get(vip_url + path, headers=headers, verify=False)
    print(r.text, flush=True)
    if "reconnect-attempts" in r.text:
        ra = r.json()["tailf-ncs:reconnect-attempts"]

    reconnect_timeout = int(ra) * int(ri)

    print(f"{okblue}##### Observe a failover by bringing down current primary and have it wait to come up until the secondary assume primary role\n{endc}", flush=True)
    on_node_sh(nso_vip, "admin", "touch $NCS_RUN_DIR/upgrade")

    process = Process(target=on_node_sh, args=(nso_vip, "admin", '$NCS_DIR/bin/ncs --stop'))
    process.start()
    print(f"{okblue}##### Exception expected as the NSO container restarts\n{endc}", flush=True)

    print(f"{okblue}##### ##### The secondary will attempt to reconnect to the primary $RA times every $RI s (timeout after $TIMEOUT s)\n{endc}", flush=True)
    counter = reconnect_timeout
    while counter >= 0:
        print(f"{header}#####  Waiting for the secondary to timeout and become primary {counter}.\n{endc}", flush=True)
        counter -= 1
        time.sleep(1)
    prev_primary = current_primary

    print(f"{okblue}##### Get the new primary name\n{endc}", flush=True)
    while True:
        path = '/data/tailf-ncs:high-availability/status/current-id?content=nonconfig'
        print(f"{bold}GET " + vip_url + path + f"{endc}", flush=True)
        try:
            r = requests.get(vip_url + path, headers=headers, verify=False)
        except (SSHException, PipeTimeout, SocketTimeout, SocketError) as e:
            print(f"{header}Exception getting the new primary {e}\n{endc}", flush=True)
        else:
            print(r.text, flush=True)
            if "current-id" in r.text:
                primary = r.json()["tailf-ncs:current-id"]
                break
        print(f"{header}##### Waiting for the VIP address {nso_vip} to point to the new primary...\n{endc}", flush=True)
        time.sleep(1)

    current_primary = primary
    print(f"{okgreen}##### Current primary: {okblue}{current_primary} {okgreen}Previous primary: {okblue}{prev_primary}\n{endc}", flush=True)

    print(f"{okblue}##### Try add additional config on the primary {current_primary} while in read-only mode waiting for the secondary {prev_primary}\n{endc}", flush=True)
    dummy_data["name"] = "d24-new"
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

    print(f"{okblue}##### Stert the previous primary {prev_primary}\n{endc}", flush=True)
    on_node_sh(prev_primary, "admin", "rm $NCS_RUN_DIR/upgrade")

    print(f"{okblue}##### Wait for {prev_primary} to come back and be secondary to the new primary {current_primary}\n{endc}", flush=True)
    prev_primary_url = f'https://{prev_primary}:8888/restconf'
    while True:
        path = '/data/tailf-ncs:high-availability/status/primary-id?content=nonconfig'
        print(f"{bold}GET " + prev_primary_url + path + f"{endc}", flush=True)
        try:
            r = requests.get(prev_primary_url + path, headers=headers, verify=False)
        except (SSHException, PipeTimeout, SocketTimeout, SocketError) as e:
            print(f"{header}Exception getting the new from the previous primary {e}\n{endc}", flush=True)
        else:
            if "primary-id" in r.text:
                primary = r.json()["tailf-ncs:primary-id"]
                if primary == current_primary:
                    break
        print(f"{header}##### Waiting for {prev_primary} to come back and be secondary to {current_primary}...\n{endc}", flush=True)
        time.sleep(1)

    print(f"{okblue}##### Add additional config on the primary {current_primary}\n{endc}", flush=True)
    dummy_data["name"] = "d23-new"
    dummy_data["dummy"] = "23.23.23.23"
    dummies_data = {}
    dummies_data["dummy"] = [dummy_data]
    input_data = {"dummy:dummies": dummies_data}
    path = '/data'
    print(f"{bold}PATCH " + vip_url + path + f"{endc}", flush=True)
    print(f"{header}" + json.dumps(input_data, indent=2) + f"{endc}", flush=True)
    r = requests.patch(vip_url + path, json=input_data, headers=headers,
                      verify=False)
    print("Status code: {}\n".format(r.status_code), flush=True)


    print(f"\n{okblue}##### Observe that the new data is replicated to {prev_primary} as well\n{endc}", flush=True)
    path = '/data/dummy:dummies'
    print(f"{bold}GET " + prev_primary_url + path + f"{endc}", flush=True)
    r = requests.get(prev_primary_url + path, headers=headers, verify=False)
    print(r.text, flush=True)

    print(f"{okgreen}##### Done!\n{endc}", flush=True)


if __name__ == "__main__":
    ha_demo()
