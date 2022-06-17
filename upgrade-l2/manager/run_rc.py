#!/usr/bin/env python3

"""A Two Node NSO Built-in High Availability Upgrade Example.

Demo script
(C) 2022 Tail-f Systems
Permission to use this code as a starting point hereby granted

See the README file for more information
"""
import json
import time
import os
from packaging import version
import paramiko
import requests

def on_node(host, cmd):
    okblue = '\033[94m'
    endc = '\033[0m'
    print(f"{okblue}On " + host + f":{endc} " + cmd + "\n")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(host, port=2024, username="admin",
      key_filename=os.path.join(os.path.expanduser('~'), ".ssh", "id_ed25519"))
    stdin, stdout, stderr = ssh.exec_command(cmd)
    output = stdout.read().decode('utf-8')
    ssh.close()
    print(output)
    return output

def on_node_sh(host, cmd):
    okblue = '\033[94m'
    endc = '\033[0m'
    print(f"{okblue}On " + host + f":{endc} " + cmd + "\n")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(host, username="admin",
      key_filename=os.path.join(os.path.expanduser('~'), ".ssh", "id_ed25519"))
    stdin, stdout, stderr = ssh.exec_command(cmd)
    output = stdout.read().decode('utf-8')
    ssh.close()
    print(output)
    return output


def ha_upgrade_demo():
    """Run the HA upgrade demo"""

    node1_name = os.getenv('NODE1_NAME')
    node2_name = os.getenv('NODE2_NAME')
    nso_vip = os.getenv('NSO_VIP')
    nso_version = os.getenv('NSO_VERSION')
    new_nso_version = os.getenv('NEW_NSO_VERSION')
    vip_url = 'https://{}:8888/restconf'.format(nso_vip)
    node1_url = 'https://{}:8888/restconf'.format(node1_name)
    node2_url = 'https://{}:8888/restconf'.format(node2_name)
    header = '\033[95m'
    okblue = '\033[94m'
    okgreen = '\033[92m'
    endc = '\033[0m'
    bold = '\033[1m'

    print(f"\n{okgreen}##### A two node HA setup with one primary " +
          node1_name + " and one secondary " + node2_name + f" node\n{endc}")
    print(f"\n{okblue}##### VIP address: " + nso_vip + f"\n{endc}")

    print(f"\n{okblue}##### Initialize the two nodes\n{endc}")
    on_node_sh(node1_name, 'source $NCS_DIR/ncsrc; cd $APP_NAME;'
               'make stop clean NSOVER=$NSO_VERSION HCCVER=$HCC_VERSION all;'
               'cp package-store/dummy-1.0.tar.gz $NCS_RUN_DIR/packages;'
               'cp package-store/token-1.0.tar.gz $NCS_RUN_DIR/packages;'
               'cp package-store/ncs-$NSO_VERSION-tailf-hcc-$HCC_VERSION.tar.gz'
               ' $NCS_RUN_DIR/packages; make start')
    on_node_sh(node2_name, 'source $NCS_DIR/ncsrc; cd $APP_NAME;'
               'make stop clean NSOVER=$NSO_VERSION HCCVER=$HCC_VERSION all;'
               'cp package-store/dummy-1.0.tar.gz $NCS_RUN_DIR/packages;'
               'cp package-store/token-1.0.tar.gz $NCS_RUN_DIR/packages;'
               'cp package-store/ncs-$NSO_VERSION-tailf-hcc-$HCC_VERSION.tar.gz'
               ' $NCS_RUN_DIR/packages; make start')

    print(f"\n{okblue}##### Get a token for RESTCONF authentication\n{endc}")
    node1_key = on_node(node1_name, "generate_token")
    node1_key = node1_key.split(" ")[1].rstrip('\r\n')

    print(f"{okblue}##### The secondary " + node2_name + " node token is"
          " only used until overwriten by the primary " + node1_name +
          f" node token\n{endc}")
    node2_key = on_node(node2_name, "generate_token")
    node2_key = node2_key.split(" ")[1].rstrip('\r\n')

    requests.packages.urllib3.disable_warnings(
        requests.packages.urllib3.exceptions.InsecureRequestWarning)
    headers = {'Content-Type': 'application/yang-data+json',
                     'X-Auth-Token': node1_key }
    headers_node2 = {'Content-Type': 'application/yang-data+json',
                     'X-Auth-Token': node2_key }

    print(f"{okblue}##### Enable HA\n{endc}")
    path = '/operations/high-availability/enable'
    print(f"{bold}POST " + node1_url + path + f"{endc}")
    r = requests.post(node1_url + path, headers=headers, verify=False)
    print("Status code: {}\n".format(r.status_code))

    path = '/operations/high-availability/enable'
    print(f"{bold}POST " + node2_url + path + f"{endc}")
    r = requests.post(node2_url + path, headers=headers_node2, verify=False)
    print("Status code: {}\n".format(r.status_code))

    while True:
        path = '/data/tailf-ncs:high-availability/status/current-id'
        print(f"{bold}GET " + vip_url + path + f"{endc}")
        try:
            r = requests.get(vip_url + path, headers=headers, verify=False)
            if node1_name in r.text:
                break
        except requests.exceptions.ConnectionError as errc:
            print ("Error connecting:",errc)
        except requests.exceptions.ChunkedEncodingError as errh:
            print ("Read failed:",errh)
        print(f"{header}#### Waiting for the VIP " + nso_vip + " to point to "
              + node1_name + f"...\n{endc}")
        time.sleep(1)

    while True:
        path = '/data/tailf-ncs:high-availability/status/connected-slave'
        print(f"{bold}GET " + vip_url + path + f"{endc}")
        r = requests.get(vip_url + path, headers=headers, verify=False)
        if node2_name in r.text:
            break
        print(f"{header}#### Waiting for the secondary node " + node2_name +
              f" to connect...\n{endc}")
        time.sleep(1)

    print(f"\n{okblue}##### Initial high-availability config for both"
          f" nodes\n{endc}")
    path = '/data/tailf-ncs:high-availability?content=config&' \
           'with-defaults=report-all'
    print(f"{bold}GET " + vip_url + path + f"{endc}")
    r = requests.get(vip_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/data/tailf-ncs:high-availability/status/current-id'
    print(f"{bold}GET " + vip_url + path + f"{endc}")
    r = requests.get(vip_url + path, headers=headers, verify=False)
    print(f"\n{okgreen}##### Current VIP node:\n" + r.text + f"\n{endc}")

    print(f"\n{okgreen}##### Test failover\n{endc}")
    print(f"\n{okblue}##### Add some dummy config to " + node1_name +
          ", replicated to secondary " + node2_name + f"\n{endc}")

    dummy_data = {}
    dummy_data["name"] = "d1"
    dummy_data["dummy"] = "1.2.3.4"
    dummies_data = {}
    dummies_data["dummy"] = [dummy_data]
    input_data = {"dummy:dummies": dummies_data}

    path = '/data'
    print(f"{bold}PATCH " + vip_url + path + f"{endc}")
    print(f"{header}" + json.dumps(input_data, indent=2) + f"{endc}")
    r = requests.patch(vip_url + path, json=input_data, headers=headers,
                      verify=False)
    print("Status code: {}\n".format(r.status_code))

    path = '/data/tailf-ncs:high-availability?content=nonconfig'
    print(f"{bold}GET " + vip_url + path + f"{endc}")
    r = requests.get(vip_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/data/dummy:dummies'
    print(f"{bold}GET " + vip_url + path + f"{endc}")
    r = requests.get(vip_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/data/tailf-ncs:high-availability?content=nonconfig'
    print(f"{bold}GET " + node2_url + path + f"{endc}")
    r = requests.get(node2_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/data/dummy:dummies'
    print(f"{bold}GET " + node2_url + path + f"{endc}")
    r = requests.get(node2_url + path, headers=headers, verify=False)
    print(r.text)

    print(f"\n{okblue}##### Disable HA on the secondary node " + node2_name +
          " to simulate secondary node failure, primary " + node1_name +
          " will assume role none as all secondary nodes disconnected"
          " (see alarm), set " + node1_name + " back"
          " to primary and enable the secondary again to reconnect to the"
          f" primary node\n{endc}")
    path = '/operations/high-availability/disable'
    print(f"{bold}POST " + node2_url + path + f"{endc}")
    r = requests.post(node2_url + path, headers=headers, verify=False)
    print("Status code: {}\n".format(r.status_code))

    while True:
        path = '/data/tailf-ncs:high-availability/status/mode'
        print(f"{bold}GET " + node1_url + path + f"{endc}")
        r = requests.get(node1_url + path, headers=headers, verify=False)
        print(r.text)
        if "none" in r.text:
            break
        print(f"{header}#### Waiting for the primary node " + node1_name +
              f" to assume none role...\n{endc}")
        time.sleep(1)

    path = '/data/tailf-ncs:high-availability/status?content=nonconfig'
    print(f"{bold}GET " + node1_url + path + f"{endc}")
    r = requests.get(node1_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/data/tailf-ncs-alarms:alarms?content=nonconfig'
    print(f"{bold}GET " + node1_url + path + f"{endc}")
    r = requests.get(node1_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/operations/high-availability/be-master'
    print(f"{bold}POST " + node1_url + path + f"{endc}")
    r = requests.post(node1_url + path, headers=headers, verify=False)
    print("Status code: {}\n".format(r.status_code))

    path = '/operations/high-availability/enable'
    print(f"{bold}POST " + node2_url + path + f"{endc}")
    r = requests.post(node2_url + path, headers=headers, verify=False)
    print("Status code: {}\n".format(r.status_code))

    while True:
        path = '/data/tailf-ncs:high-availability/status/connected-slave'
        print(f"{bold}GET " + vip_url + path + f"{endc}")
        r = requests.get(vip_url + path, headers=headers, verify=False)
        if node2_name in r.text:
            break
        print(f"{header}#### Waiting for the secondary node" + node2_name +
              f" to re-connect...{endc}")
        time.sleep(1)

    print(f"\n{okblue}##### Disable HA on the primary " + node1_name +
          "to make " + node2_name + f"failover to primary role\n{endc}")
    path = '/operations/high-availability/disable'
    print(f"{bold}POST " + vip_url + path + f"{endc}")
    r = requests.post(vip_url + path, headers=headers, verify=False)
    print("Status code: {}\n".format(r.status_code))

    while True:
        path = '/data/tailf-ncs:high-availability/status/mode'
        print(f"{bold}GET " + node2_url + path + f"{endc}")
        r = requests.get(node2_url + path, headers=headers, verify=False)
        if "master" in r.text:
            break
        print(f"{header}#### Waiting for " + node2_name + " to fail reconnect"
              " to " + node1_name + f" and assume primary role...\n{endc}")
        time.sleep(1)

    print(f"\n{okblue}##### Check that the current VIP node have switched to "
          + node2_name + f"\n{endc}")
    while True:
        path = '/data/tailf-ncs:high-availability/status/current-id'
        print(f"{bold}GET " + vip_url + path + f"{endc}")
        try:
            r = requests.get(vip_url + path, headers=headers, verify=False)
            if node2_name in r.text:
                break
        except requests.exceptions.ConnectionError as errc:
            print ("Error Connecting:",errc)
        except requests.exceptions.ChunkedEncodingError as errh:
            print ("Read failed:",errh)
        print(f"{header}#### Waiting for the VIP " + nso_vip + " to point to "
              + node2_name + f"...\n{endc}")
        time.sleep(1)

    print(f"\n{okgreen}##### Current VIP node:\n" + r.text + f"\n{endc}")

    path = '/data/tailf-ncs:high-availability/status?content=nonconfig'
    print(f"{bold}GET " + vip_url + path + f"{endc}")
    r = requests.get(vip_url + path, headers=headers, verify=False)
    print(r.text)

    print(f"\n{okblue}##### Enable HA on " + node1_name +
          f" that will now assume secondary role\n{endc}")
    path = '/operations/high-availability/enable'
    print(f"{bold}POST " + node1_url + path + f"{endc}")
    r = requests.post(node1_url + path, headers=headers, verify=False)
    print("Status code: {}\n".format(r.status_code))

    while True:
        path = '/data/tailf-ncs:high-availability/status/mode'
        print(f"{bold}GET " + node1_url + path + f"{endc}")
        r = requests.get(node1_url + path, headers=headers, verify=False)
        if "slave" in r.text:
            break
        print(f"{header}#### Waiting for " + node1_name + " to become"
              " secondary to " + node2_name + f"...{endc}")
        time.sleep(1)

    path = '/data/tailf-ncs:high-availability/status?content=nonconfig'
    print(f"{bold}GET " + vip_url + path + f"{endc}")
    r = requests.get(vip_url + path, headers=headers, verify=False)
    print(r.text)

    print(f"{bold}GET " + node1_url + path + f"{endc}")
    r = requests.get(node1_url + path, headers=headers, verify=False)
    print(r.text)

    print(f"\n{okblue}##### Role revert nodes back to start-up settings"
          f"\n{endc}")
    path = '/operations/high-availability/disable'
    print(f"{bold}POST " + node1_url + path + f"{endc}")
    r = requests.post(node1_url + path, headers=headers, verify=False)
    print("Status code: {}\n".format(r.status_code))

    print(f"{bold}POST " + vip_url + path + f"{endc}")
    r = requests.post(vip_url + path, headers=headers, verify=False)
    print("Status code: {}\n".format(r.status_code))

    path = '/operations/high-availability/enable'
    print(f"{bold}POST " + node1_url + path + f"{endc}")
    r = requests.post(node1_url + path, headers=headers, verify=False)
    print("Status code: {}\n".format(r.status_code))

    while True:
        path = '/data/tailf-ncs:high-availability/status/mode'
        print(f"{bold}GET " + node1_url + path + f"{endc}")
        r = requests.get(node1_url + path, headers=headers, verify=False)
        if "master" in r.text:
            break
        print(f"{header}#### Waiting for " + node1_name + " to revert to"
              f" primary role...{endc}")
        time.sleep(1)

    path = '/operations/high-availability/enable'
    print(f"{bold}POST " + node2_url + path + f"{endc}")
    r = requests.post(node2_url + path, headers=headers, verify=False)
    print("Status code: {}\n".format(r.status_code))

    while True:
        path = '/data/tailf-ncs:high-availability/status/mode'
        print(f"{bold}GET " + node2_url + path + f"{endc}")
        r = requests.get(node2_url + path, headers=headers, verify=False)
        if "slave" in r.text:
            break
        print(f"{header}#### Waiting for " + node2_name + " to revert to"
              " secondary role for primary " + node1_name + f"...\n{endc}")
        time.sleep(1)

    while True:
        path = '/data/tailf-ncs:high-availability/status/current-id'
        print(f"{bold}GET " + vip_url + path + f"{endc}")
        try:
            r = requests.get(vip_url + path, headers=headers, verify=False)
            if node1_name in r.text:
                break
        except requests.exceptions.ConnectionError as errc:
            print ("Error connecting:",errc)
        except requests.exceptions.ChunkedEncodingError as errh:
            print ("Read failed:",errh)
        print(f"{header}#### Waiting for the VIP " + nso_vip + " to point to "
              + node1_name + f"...\n{endc}")
        time.sleep(1)

    path = '/data/tailf-ncs:high-availability/status/current-id'
    print(f"{bold}GET " + vip_url + path + f"{endc}")
    r = requests.get(vip_url + path, headers=headers, verify=False)
    print(f"\n{okgreen}##### Current VIP node:\n" + r.text + f"\n{endc}")

    path = '/data/tailf-ncs:high-availability/status?content=nonconfig'
    print(f"{bold}GET " + vip_url + path + f"{endc}")
    r = requests.get(vip_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/data/tailf-ncs:high-availability?content=nonconfig'
    print(f"{bold}GET " + vip_url + path + f"{endc}")
    r = requests.get(vip_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/data/dummy:dummies'
    print(f"{bold}GET " + vip_url + path + f"{endc}")
    r = requests.get(vip_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/data/tailf-ncs:high-availability?content=nonconfig'
    print(f"{bold}GET " + node2_url + path + f"{endc}")
    r = requests.get(node2_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/data/dummy:dummies'
    print(f"{bold}GET " + node2_url + path + f"{endc}")
    r = requests.get(node2_url + path, headers=headers, verify=False)
    print(r.text)

    print(f"\n{okgreen}##### Upgrade from NSO " + nso_version + " to " +
          new_nso_version + f"\n{endc}")
    print(f"\n{okblue}##### Backup before upgrading NSO\n{endc}")
    on_node_sh(nso_vip, '$NCS_DIR/bin/ncs-backup')
    on_node_sh(node2_name, '$NCS_DIR/bin/ncs-backup')

    print(f"\n{okblue}##### Install NSO " + new_nso_version +
          f" on both nodes\n{endc}")
    on_node_sh(nso_vip, 'rm $NCS_DIR;'
                  'ln -s $NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION $NCS_DIR')
    on_node_sh(node2_name, 'rm $NCS_DIR;'
                           ' ln -s $NCS_ROOT_DIR/ncs-$NEW_NSO_VERSION $NCS_DIR')

    # NSO 5.5 removed the show-log-directory parameter.
    if version.parse(nso_version) < version.parse("5.5") and \
       version.parse(new_nso_version) >= version.parse("5.5"):
        on_node_sh(nso_vip, 'sed -i.bak "s%<show-log-directory>./logs'
                      '</show-log-directory>%%" $NCS_CONFIG_DIR/ncs.conf')
        on_node_sh(node2_name, 'sed -i.bak "s%<show-log-directory>./logs'
                               '</show-log-directory>%%"'
                               ' $NCS_CONFIG_DIR/ncs.conf')

    # NSO 5.6 removed the large-scale parameters
    if version.parse(nso_version) < version.parse("5.6") and \
       version.parse(new_nso_version) >= version.parse("5.6"):
       on_node_sh(nso_vip, 'sed -i.bak "/<large-scale>/I,+7 d"'
                     ' $NCS_CONFIG_DIR/ncs.conf')
       on_node_sh(node2_name, 'sed -i.bak "/<large-scale>/I,+7 d"'
                                ' $NCS_CONFIG_DIR/ncs.conf')

    print(f"\n{okblue}##### Rebuild the primary " + node1_name +
          " node packages in its package store for NSO " + new_nso_version +
          f"\n{endc}")
    on_node_sh(nso_vip, 'source $NCS_DIR/ncsrc; cd $APP_NAME; make'
                       ' rebuild-packages')

    print(f"\n{okblue}##### Replace the currently installed packages on the " +
          node1_name + " node with the ones built for NSO"  + new_nso_version +
          f"{endc}\n")
    on_node_sh(nso_vip, 'rm $NCS_RUN_DIR/packages/*;'
       'cp $APP_NAME/package-store/dummy-1.0.tar.gz $NCS_RUN_DIR/packages;'
       'cp $APP_NAME/package-store/token-1.0.tar.gz $NCS_RUN_DIR/packages;'
       'cp $APP_NAME/package-store/ncs-$NEW_NSO_VERSION-tailf-hcc-'
       '$NEW_HCC_VERSION.tar.gz $NCS_RUN_DIR/packages')

    print(f"\n{okblue}##### Disable primary node " + node1_name +
          " high availability for secondary node " + node2_name +
          " to automatically failover and assume primary role"
          f" in read-only mode{endc}\n")
    path = '/operations/high-availability/disable'
    print(f"{bold}POST " + vip_url + path + f"{endc}")
    r = requests.post(vip_url + path, headers=headers, verify=False)
    print("Status code: {}\n".format(r.status_code))

    print(f"\n{okblue}##### Upgrade the " + node1_name + " node to " +
          new_nso_version + f"\n{endc}")
    on_node_sh(node1_name, '$NCS_DIR/bin/ncs --stop; $NCS_DIR/bin/ncs -c'
                           ' $NCS_CONFIG_DIR/ncs.conf'
                           ' --with-package-reload-force')

    print(f"\n{okblue}##### Disable high availability for the " + node2_name +
           f" node\n{endc}")
    path = '/operations/high-availability/disable'
    print(f"{bold}POST " + node2_url + path + f"{endc}")
    r = requests.post(node2_url + path, headers=headers, verify=False)
    print("Status code: {}\n".format(r.status_code))

    print(f"\n{okblue}##### Enable high availability for the " + node1_name +
          f" node that will assume primary role\n{endc}")

    while True:
        path = '/operations/high-availability/enable'
        print(f"{bold}POST " + node1_url + path + f"{endc}")
        r = requests.post(node1_url + path, headers=headers, verify=False)
        print("Status code: {}\n".format(r.status_code))
        if r.status_code == 200:
            break
        print(f"{header}#### Waiting for " + node1_name + " to complete the"
              f" upgrade...{endc}")
        time.sleep(1)

    print(f"\n{okblue}##### Rebuild the secondary " + node2_name +
          " node packages in its package store for NSO " + new_nso_version +
          f"\n{endc}")
    on_node_sh(node2_name,
               'source $NCS_DIR/ncsrc; cd $APP_NAME; make rebuild-packages')

    print(f"\n{okblue}##### Replace the currently installed packages on the " +
          node2_name + " node with the ones built for NSO " + new_nso_version +
          f"{endc}\n")
    on_node_sh(node2_name, 'rm $NCS_RUN_DIR/packages/*;'
           'cp $APP_NAME/package-store/dummy-1.0.tar.gz $NCS_RUN_DIR/packages;'
           'cp $APP_NAME/package-store/token-1.0.tar.gz $NCS_RUN_DIR/packages;'
           'cp $APP_NAME/package-store/ncs-$NEW_NSO_VERSION-tailf-hcc-'
           '$NEW_HCC_VERSION.tar.gz $NCS_RUN_DIR/packages')

    print(f"\n{okblue}##### Upgrade the " + node2_name + " node to " +
          new_nso_version + f"\n{endc}")
    on_node_sh(node2_name, '$NCS_DIR/bin/ncs --stop; $NCS_DIR/bin/ncs -c'
                           ' $NCS_CONFIG_DIR/ncs.conf'
                           ' --with-package-reload-force')

    while True:
        path = '/data/tailf-ncs:high-availability/status/mode'
        print(f"{bold}GET " + node1_url + path + f"{endc}")
        r = requests.get(node1_url + path, headers=headers, verify=False)
        if "master" in r.text:
            break
        print(f"{header}#### Waiting for " + node1_name + " to assume"
              f" primary role...{endc}")
        time.sleep(1)

    print(f"\n{okblue}##### Enable high availability for the " + node2_name +
          f" node that will assume secondary role\n{endc}")
    path = '/operations/high-availability/enable'
    print(f"{bold}POST " + node2_url + path + f"{endc}")
    r = requests.post(node2_url + path, headers=headers, verify=False)
    print("Status code: {}\n".format(r.status_code))

    while True:
        path = '/data/tailf-ncs:high-availability/status/mode'
        print(f"{bold}GET " + node2_url + path + f"{endc}")
        r = requests.get(node2_url + path, headers=headers, verify=False)
        if "slave" in r.text:
            break
        print(f"{header}#### Waiting for " + node2_name + " to assume"
              f" secondary role...\n{endc}")
        time.sleep(1)

    path = '/data/tailf-ncs:high-availability/status?content=nonconfig'
    print(f"{bold}GET " + vip_url + path + f"{endc}")
    r = requests.get(vip_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/data/dummy:dummies'
    print(f"{bold}GET " + vip_url + path + f"{endc}")
    r = requests.get(vip_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/data/tailf-ncs:high-availability/status?content=nonconfig'
    print(f"{bold}GET " + node2_url + path + f"{endc}")
    r = requests.get(node2_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/data/dummy:dummies'
    print(f"{bold}GET " + node2_url + path + f"{endc}")
    r = requests.get(node2_url + path, headers=headers, verify=False)
    print(r.text)

    print(f"\n{okblue}##### Upgrade primary " + node1_name + " node"
          " packages and sync the packages to the secondary " + node2_name +
          f" node\n{endc}")
    path = '/operations/software/packages/list'
    print(f"{bold}POST " + vip_url + path + f"{endc}")
    r = requests.post(vip_url + path, headers=headers, verify=False)
    print(r.text)

    input_data = {"input": {"package-from-file": os.getcwd() +
                            "/package-store/inert-1.0.tar.gz"}}
    path = '/operations/software/packages/fetch'
    print(f"{bold}POST " + vip_url + path + f"{endc}")
    print(f"{header}" + json.dumps(input_data, indent=2) + f"{endc}")
    r = requests.post(vip_url + path, json=input_data, headers=headers,
                     verify=False)
    print("Status code: {}\n".format(r.status_code))

    input_data = {"input": {"package-from-file": os.getcwd() +
                            "/package-store/dummy-1.1.tar.gz"}}
    path = '/operations/software/packages/fetch'
    print(f"{bold}POST " + vip_url + path + f"{endc}")
    print(f"{header}" + json.dumps(input_data, indent=2) + f"{endc}")
    r = requests.post(vip_url + path, json=input_data, headers=headers,
                     verify=False)
    print("Status code: {}\n".format(r.status_code))

    path = '/operations/software/packages/list'
    print(f"{bold}POST " + vip_url + path + f"{endc}")
    r = requests.post(vip_url + path, headers=headers,
                     verify=False)
    print(r.text)

    input_data = {"input": {"package": "inert-1.0"}}
    path = '/operations/software/packages/install'
    print(f"{bold}POST " + vip_url + path + f"{endc}")
    print(f"{header}" + json.dumps(input_data, indent=2) + f"{endc}")
    r = requests.post(vip_url + path, json=input_data, headers=headers,
                     verify=False)
    print("Status code: {}\n".format(r.status_code))

    input_data = {"input": {"package": "dummy-1.1", "replace-existing": ""}}
    path = '/operations/software/packages/install'
    print(f"{bold}POST " + vip_url + path + f"{endc}")
    print(f"{header}" + json.dumps(input_data, indent=2) + f"{endc}")
    r = requests.post(vip_url + path, json=input_data, headers=headers,
                     verify=False)
    print("Status code: {}\n".format(r.status_code))

    path = '/operations/software/packages/list'
    print(f"{bold}POST " + vip_url + path + f"{endc}")
    r = requests.post(vip_url + path, headers=headers, verify=False)
    print(r.text)

    input_data = {"input": {"sync": ""}}
    path = '/operations/devices/commit-queue/add-lock'
    print(f"{bold}POST " + node1_url + path + f"{endc}")
    print(f"{header}" + json.dumps(input_data, indent=2) + f"{endc}")
    r = requests.post(node1_url + path, json=input_data, headers=headers,
                     verify=False)
    print(r.text)
    cq_id = r.json()["tailf-ncs:output"]["commit-queue-id"]

    input_data = {"input": {"and-reload": ""}}
    path = '/operations/packages/ha/sync'
    print(f"{bold}POST " + node1_url + path + f"{endc}")
    print(f"{header}" + json.dumps(input_data, indent=2) + f"{endc}")
    r = requests.post(node1_url + path, json=input_data, headers=headers,
                     verify=False)
    print(r.text)

    path = '/operations/devices/commit-queue/queue-item={}/unlock'.format(cq_id)
    print(f"{bold}POST " + node1_url + path + f"{endc}")
    r = requests.post(node1_url + path, headers=headers, verify=False)
    print("Status code: {}\n".format(r.status_code))

    print(f"\n{okblue}##### Add some new config through the primary " +
          node1_name + f" node\n{endc}")
    dummy_data = {}
    dummy_data["name"] = "d1"
    dummy_data["description"] = "hello world"
    dummies_data = {}
    dummies_data["dummy"] = [dummy_data]
    input_data = {"dummy:dummies": dummies_data}

    path = '/data'
    print(f"{bold}PATCH " + node1_url + path + f"{endc}")
    print(f"{header}" + json.dumps(input_data, indent=2) + f"{endc}")
    r = requests.patch(node1_url + path, json=input_data, headers=headers,
                      verify=False)
    print("Status code: {}\n".format(r.status_code))

    inert_data = {}
    inert_data["name"] = "i1"
    inert_data["dummy"] = "4.3.2.1"
    inerts_data = {}
    inerts_data["inert"] = [inert_data]
    input_data = {"inert:inerts": inerts_data}

    path = '/data'
    print(f"{bold}PATCH " + node1_url + path + f"{endc}")
    print(f"{header}" + json.dumps(input_data, indent=2) + f"{endc}")
    r = requests.patch(node1_url + path, json=input_data, headers=headers,
                      verify=False)
    print("Status code: {}\n".format(r.status_code))

    path = '/data/tailf-ncs:high-availability?content=nonconfig'
    print(f"{bold}GET " + node1_url + path + f"{endc}")
    r = requests.get(node1_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/data/dummy:dummies'
    print(f"{bold}GET " + node1_url + path + f"{endc}")
    r = requests.get(node1_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/data/inert:inerts'
    print(f"{bold}GET " + node1_url + path + f"{endc}")
    r = requests.get(node1_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/data?fields=tailf-ncs:packages/package(name;package-version)'
    print(f"{bold}GET " + node1_url + path + f"{endc}")
    r = requests.get(node1_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/data/tailf-ncs:high-availability?content=nonconfig'
    print(f"{bold}GET " + node2_url + path + f"{endc}")
    r = requests.get(node2_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/data/dummy:dummies'
    print(f"{bold}GET " + node2_url + path + f"{endc}")
    r = requests.get(node2_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/data/inert:inerts'
    print(f"{bold}GET " + node2_url + path + f"{endc}")
    r = requests.get(node2_url + path, headers=headers, verify=False)
    print(r.text)

    path = '/data?fields=tailf-ncs:packages/package(name;package-version)'
    print(f"{bold}GET " + node2_url + path + f"{endc}")
    r = requests.get(node2_url + path, headers=headers, verify=False)
    print(r.text)

    print(f"\n{okgreen}##### Done!\n{endc}")


if __name__ == "__main__":
    ha_upgrade_demo()
