#!/bin/bash
NSO_ARCH="x86_64"
NSO_VERSION="5.8.3"
NEW_NSO_VERSION="6.0"
HCC_VERSION="5.0.3"
NEW_HCC_VERSION="5.0.4"
APP_NAME="app"
NET1_NAME="ParisLondonNet"
NODE1_NAME="paris"
NODE1_IP="192.168.23.99"
NODE2_NAME="london"
NODE2_IP="192.168.23.98"
NODE3_NAME="manager"
NODE3_IP="192.168.23.2"
NCS_CONFIG_DIR=/etc/ncs
NODE12_DOCKERFILE="Dockerfile.deb" # Alt. "Dockerfile.rhubi"

IMG1_NAME=$NODE1_NAME"-tailf-hcc"
IMG2_NAME=$NODE2_NAME"-tailf-hcc"
IMG3_NAME=$NODE3_NAME"-tailf-hcc"

SUBNET1=192.168.23.0/24
NSO_VIP=192.168.23.122

if [ -f nso-$NSO_VERSION.linux.$NSO_ARCH.installer.bin ] && [ -f nso-$NEW_NSO_VERSION.linux.$NSO_ARCH.installer.bin ]
then
    echo "Using:"
    echo "nso-$NSO_VERSION.linux.$NSO_ARCH.installer.bin and nso-$NEW_NSO_VERSION.linux.$NSO_ARCH.installer.bin"
else
    echo >&2 "This demo require that two NSO SDK installers has been placed in this folder. E.g.:"
    echo >&2 "nso-$NSO_VERSION.linux.$NSO_ARCH.installer.bin and nso-$NEW_NSO_VERSION.linux.$NSO_ARCH.installer.bin"
    echo >&2 "Aborting..."
    exit 1
fi

if [ -f ncs-$NSO_VERSION-tailf-hcc-$HCC_VERSION.tar.gz ] && [ -f ncs-$NEW_NSO_VERSION-tailf-hcc-$NEW_HCC_VERSION.tar.gz ]
then
    echo "Using:"
    echo "ncs-$NSO_VERSION-tailf-hcc-$HCC_VERSION.tar.gz and ncs-$NEW_NSO_VERSION-tailf-hcc-$NEW_HCC_VERSION.tar.gz"
else
    echo >&2 "This demo require that the Tail-f HCC packages has been placed in this folder. E.g.:"
    echo >&2 "ncs-$NSO_VERSION-tailf-hcc-$HCC_VERSION.tar.gz and ncs-$NEW_NSO_VERSION-tailf-hcc-$NEW_HCC_VERSION.tar.gz"
    echo >&2 "Aborting..."
    exit 1
fi

if [ -d $APP_NAME ]
then
    echo "Using this application folder:"
    printf "%s\n" "$APP_NAME"
    rm -f $APP_NAME.tar.gz
    tar cfz $APP_NAME.tar.gz $APP_NAME
else
    echo >&2 "This demo require that the NSO application folder exists"
    echo >&2 "E.g. this directory:"
    echo >&2 "./$APP_NAME"
    echo >&2 "Aborting..."
    exit 1
fi

if [ -d $NODE3_NAME ]
then
    echo "Using this $NODE3_NAME application folder:"
    printf "%s\n" "$NODE3_NAME"
    rm -f $NODE3_NAME.tar.gz
    tar cfz $NODE3_NAME.tar.gz $NODE3_NAME
else
    echo >&2 "This demo require that the $NODE3_NAME application folder exists"
    echo >&2 "E.g. this directory:"
    echo >&2 "./$NODE3_NAME"
    echo >&2 "Aborting..."
    exit 1
fi

DOCKERPS_N1=$(docker ps -q -n 1 -f name=$NODE1_NAME)
if [ -z "$DOCKERPS_N1" ] ;
then
    echo "Build & run $NODE1_NAME"
else
    echo "Stop any existing $NODE1_NAME container, then build & run"
    docker stop $NODE1_NAME
fi

DOCKERPS_N2=$(docker ps -q -n 1 -f name=$NODE2_NAME)
if [ -z "$DOCKERPS_N2" ] ;
then
    echo "Build & run $NODE2_NAME"
else
    echo "Stop any existing $NODE2_NAME container, then build & run"
    docker stop $NODE2_NAME
fi

DOCKERPS_N3=$(docker ps -q -n 1 -f name=$NODE3_NAME)
if [ -z "$DOCKERPS_N3" ] ;
then
    echo "Build & run $NODE3_NAME"
else
    echo "Stop any existing $NODE3_NAME container, then build & run"
    docker stop $NODE3_NAME
fi

DOCKERNETLS=$(docker network ls -q -f name=$NET1_NAME)
if [ -z "$DOCKERNETLS" ] ;
then
    echo "Create $NET1_NAME"
else
    echo "Remove and recreate any existing $NET1_NAME network"
    docker network rm $NET1_NAME
fi

docker build -t $IMG1_NAME --build-arg NSO_ARCH=$NSO_ARCH --build-arg NSO_VERSION=$NSO_VERSION --build-arg HCC_VERSION=$HCC_VERSION --build-arg APP_NAME=$APP_NAME --build-arg NODE3_NAME=$NODE3_NAME --build-arg NCS_CONFIG_DIR=$NCS_CONFIG_DIR -f $NODE12_DOCKERFILE .
docker build -t $IMG2_NAME --build-arg NSO_ARCH=$NSO_ARCH --build-arg NSO_VERSION=$NSO_VERSION --build-arg HCC_VERSION=$HCC_VERSION --build-arg APP_NAME=$APP_NAME --build-arg NODE3_NAME=$NODE3_NAME --build-arg NCS_CONFIG_DIR=$NCS_CONFIG_DIR -f $NODE12_DOCKERFILE .
docker build -t $IMG3_NAME --build-arg NSO_ARCH=$NSO_ARCH --build-arg NEW_NSO_VERSION=$NEW_NSO_VERSION --build-arg NEW_HCC_VERSION=$NEW_HCC_VERSION --build-arg APP_NAME=$APP_NAME --build-arg NODE3_NAME=$NODE3_NAME -f Dockerfile.$NODE3_NAME .

docker network create --subnet=$SUBNET1 $NET1_NAME

echo "Run the $NODE3_NAME container"
N3_CID="$(docker run --hostname $NODE3_NAME --cap-add NET_ADMIN --net $NET1_NAME --ip $NODE3_IP --name $NODE3_NAME -d --rm -p 18888:18888 -e NSO_VIP=$NSO_VIP -e NODE1_NAME=$NODE1_NAME -e NODE2_NAME=$NODE2_NAME -e NSO_VERSION=$NSO_VERSION -e HCC_VERSION=$HCC_VERSION $IMG3_NAME | cut -c1-12)"

while [[ $(docker ps -l -a -q -f status=running | grep $N3_CID) != $N3_CID ]]; do
    echo "waiting..."
    sleep .5
done

echo "Run the $NODE2_NAME container"
N2_CID="$(docker run --hostname $NODE2_NAME --cap-add NET_ADMIN --net $NET1_NAME --ip $NODE2_IP --name $NODE2_NAME -d --rm -e NSO_VIP=$NSO_VIP -e NODE1_NAME=$NODE1_NAME -e NODE2_NAME=$NODE2_NAME -e NODE_IP=$NODE2_IP -e NODE1_IP=$NODE1_IP -e NODE2_IP=$NODE2_IP -e NEW_NSO_VERSION=$NEW_NSO_VERSION -e NEW_HCC_VERSION=$NEW_HCC_VERSION $IMG2_NAME | cut -c1-12)"

while [[ $(docker ps -l -a -q -f status=running | grep $N2_CID) != $N2_CID ]]; do
    echo "waiting..."
    sleep .5
done

echo "Run the $NODE1_NAME container"
N1_CID="$(docker run --hostname $NODE1_NAME --cap-add NET_ADMIN --net $NET1_NAME --ip $NODE1_IP --name $NODE1_NAME -d --rm -e NSO_VIP=$NSO_VIP -e NODE1_NAME=$NODE1_NAME -e NODE2_NAME=$NODE2_NAME -e NODE_IP=$NODE1_IP -e NODE1_IP=$NODE1_IP -e NODE2_IP=$NODE2_IP -e NEW_NSO_VERSION=$NEW_NSO_VERSION -e NEW_HCC_VERSION=$NEW_HCC_VERSION $IMG1_NAME | cut -c1-12)"

while [[ $(docker ps -l -a -q -f status=running | grep $N1_CID) != $N1_CID ]]; do
    echo "waiting..."
    sleep .5
done

echo "Configure the $NODE1_NAME and $NODE2_NAME containers HA token, host and authorized SSH keys"
# Wait for the HA token to be generated by the HA group nodes
while [[ $(docker exec $NODE1_NAME  sh -c "if [ -f /home/admin/ha_token ]; then echo 'exists'; fi") != "exists" ]] || \
      [[ $(docker exec $NODE2_NAME  sh -c "if [ -f /home/admin/ha_token ]; then echo 'exists'; fi") != "exists" ]]
do
    echo "waiting..."
    sleep .5
done

# Copy the HA token from node 1 to node 2 overwriting the token on node 2 so the token match when the built-in HA is setup
docker exec -u admin $NODE2_NAME sh -c "echo \"$(docker exec -u admin $NODE1_NAME cat /home/admin/ha_token)\" > /home/admin/ha_token;"

# Wait for the host keys to be generated by the HA group nodes
while [[ $(docker exec $NODE1_NAME  sh -c "if [ -f /etc/ssh/ssh_host_ed25519_key.pub ]; then echo 'exists'; fi") != "exists" ]] || \
      [[ $(docker exec $NODE1_NAME  sh -c "if [ -f $NCS_CONFIG_DIR/ssh/ssh_host_ed25519_key.pub ]; then echo 'exists'; fi") != "exists" ]] || \
      [[ $(docker exec $NODE2_NAME  sh -c "if [ -f /etc/ssh/ssh_host_ed25519_key.pub ]; then echo 'exists'; fi") != "exists" ]] || \
      [[ $(docker exec $NODE2_NAME  sh -c "if [ -f $NCS_CONFIG_DIR/ssh/ssh_host_ed25519_key.pub ]; then echo 'exists'; fi") != "exists" ]]
do
    echo "waiting..."
    sleep .5
done

# Copy the Linux and NSO host keys from node 1 to node 2 overwriting the keys on node 2 so the host keys are shared between the nodes for VIP purposes
docker exec $NODE2_NAME sh -c "echo \"$(docker exec $NODE1_NAME cat /etc/ssh/ssh_host_ed25519_key)\" > /etc/ssh/ssh_host_ed25519_key"
docker exec $NODE2_NAME sh -c "echo \"$(docker exec $NODE1_NAME cat /etc/ssh/ssh_host_ed25519_key.pub)\" > /etc/ssh/ssh_host_ed25519_key.pub"
docker exec $NODE2_NAME sh -c "echo \"$(docker exec $NODE1_NAME cat $NCS_CONFIG_DIR/ssh/ssh_host_ed25519_key)\" > $NCS_CONFIG_DIR/ssh/ssh_host_ed25519_key"
docker exec $NODE2_NAME sh -c "echo \"$(docker exec $NODE1_NAME cat $NCS_CONFIG_DIR/ssh/ssh_host_ed25519_key.pub)\" > $NCS_CONFIG_DIR/ssh/ssh_host_ed25519_key.pub"

# Copy the host keys to the manager node known_hosts file
HOST_KEY=$(docker exec $NODE2_NAME cat /etc/ssh/ssh_host_ed25519_key.pub | cut -d ' ' -f1-2)
NSO_HOST_KEY=$(docker exec $NODE2_NAME cat $NCS_CONFIG_DIR/ssh/ssh_host_ed25519_key.pub | cut -d ' ' -f1-2)
docker exec $NODE3_NAME sh -c "printf \"$NSO_VIP $HOST_KEY\n[$NSO_VIP]:2024 $NSO_HOST_KEY\n$NODE2_NAME $HOST_KEY\n[$NODE2_NAME]:2024 $NSO_HOST_KEY\n$NODE1_NAME $HOST_KEY\n[$NODE1_NAME]:2024 $NSO_HOST_KEY\n\" >> /root/.ssh/known_hosts; ssh-keygen -Hf /root/.ssh/known_hosts; rm /root/.ssh/known_hosts.old"

# Wait for the keys to be generated by the manager (node 3) and node 2
while [[ $(docker exec $NODE3_NAME  sh -c "if [ -f /root/.ssh/id_ed25519.pub ]; then echo 'exists'; fi") != "exists" ]] || \
      [[ $(docker exec $NODE2_NAME  sh -c "if [ -f /home/admin/.ssh/id_ed25519.pub ]; then echo 'exists'; fi") != "exists" ]] || \
      [[ $(docker exec $NODE2_NAME  sh -c "if [ -f /home/oper/.ssh/id_ed25519.pub ]; then echo 'exists'; fi") != "exists" ]] || \
      [[ $(docker exec $NODE2_NAME  sh -c "if [ -f /root/.ssh/id_ed25519.pub ]; then echo 'exists'; fi") != "exists" ]]
do
    echo "waiting..."
    sleep .5
done

# Copy the manager authorized keys to node 2
docker exec $NODE2_NAME sh -c "echo $(docker exec $NODE3_NAME cat /root/.ssh/id_ed25519.pub) >> /home/oper/.ssh/authorized_keys"
docker exec $NODE2_NAME sh -c "echo $(docker exec $NODE3_NAME cat /root/.ssh/id_ed25519.pub) >> /root/.ssh/authorized_keys"
docker exec $NODE2_NAME sh -c "echo $(docker exec $NODE3_NAME cat /root/.ssh/id_ed25519.pub) >> /home/admin/.ssh/authorized_keys"

# Wait for NSO to be started
ecode=1;
while [ $ecode -ne 0 ]; do
    sleep .5
    docker exec $NODE2_NAME ncs --wait-started
    ecode=$?
done

# Wait for the keys to be generated by node 1
while [[ $(docker exec $NODE1_NAME  sh -c "if [ -f /root/.ssh/id_ed25519.pub ]; then echo 'exists'; fi") != "exists" ]] || \
      [[ $(docker exec $NODE1_NAME  sh -c "if [ -f /home/admin/.ssh/id_ed25519.pub ]; then echo 'exists'; fi") != "exists" ]] || \
      [[ $(docker exec $NODE1_NAME  sh -c "if [ -f /home/oper/.ssh/id_ed25519.pub ]; then echo 'exists'; fi") != "exists" ]]
do
    echo "waiting..."
    sleep .5
done

# Copy the manager authorized keys to node 1
docker exec $NODE1_NAME sh -c "echo $(docker exec $NODE3_NAME cat /root/.ssh/id_ed25519.pub) >> /home/oper/.ssh/authorized_keys"
docker exec $NODE1_NAME sh -c "echo $(docker exec $NODE3_NAME cat /root/.ssh/id_ed25519.pub) >> /root/.ssh/authorized_keys"
docker exec $NODE1_NAME sh -c "echo $(docker exec $NODE3_NAME cat /root/.ssh/id_ed25519.pub) >> /home/admin/.ssh/authorized_keys"

docker logs $NODE3_NAME --follow
