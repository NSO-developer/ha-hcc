#!/bin/bash
NSO_VERSION="6.1.6"
TAILF_HCC_VERSION="6.0.1"
APP_NAME="app"
NET_NAME="ParisLondonNet"
NODE1_NAME="paris"
NODE1_IP="192.168.23.99"
NODE2_NAME="london"
NODE2_IP="192.168.23.98"
NODE3_NAME="gateway"
NODE3_IP="192.168.23.2"

IMG1_NAME=$NODE1_NAME"-tailf-hcc"
IMG2_NAME=$NODE2_NAME"-tailf-hcc"
IMG3_NAME=$NODE3_NAME"-tailf-hcc"

SUBNET=192.168.23.0/24
NSO_VIP=192.168.23.122
NSO_VIP_NAME="my-node.com"

if [ -f nso-$NSO_VERSION.linux.x86_64.installer.bin ]
then
    echo "Using:"
    echo "nso-$NSO_VERSION.linux.x86_64.installer.bin"
else
    echo >&2 "This demo require that the NSO SDK installer has been placed in this folder. E.g.:"
    echo >&2 "nso-$NSO_VERSION.linux.x86_64.installer.bin"
    echo >&2 "Aborting..."
    exit 1
fi

if [ -f ncs-$NSO_VERSION-tailf-hcc-$TAILF_HCC_VERSION.tar.gz ]
then
    echo "Using:"
    echo "ncs-$NSO_VERSION-tailf-hcc-$TAILF_HCC_VERSION.tar.gz"
else
    echo >&2 "This demo require that the Tail-f HCC package has been placed in this folder. E.g.:"
    echo >&2 "ncs-$NSO_VERSION-tailf-hcc-$TAILF_HCC_VERSION.tar.gz"
    echo >&2 "Aborting..."
    exit 1
fi

if [ -d $APP_NAME ]
then
    echo "Using this application folder:"
    printf "%s\n" "$APP_NAME"
    rm -f $APP_NAME.tar.gz
    tar cvfz $APP_NAME.tar.gz $APP_NAME
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
    tar cvfz $NODE3_NAME.tar.gz $NODE3_NAME
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

DOCKERNETLS=$(docker network ls -q -f name=$NET_NAME)
if [ -z "$DOCKERNETLS" ] ;
then
    echo "Create $NET_NAME"
else
    echo "Remove and recreate any existing $NET_NAME network"
    docker network rm $NET_NAME
fi

docker build -t $IMG1_NAME --build-arg NSO_VERSION=$NSO_VERSION --build-arg TAILF_HCC_VERSION=$TAILF_HCC_VERSION --build-arg APP_NAME=$APP_NAME -f Dockerfile .
docker build -t $IMG2_NAME --build-arg NSO_VERSION=$NSO_VERSION --build-arg TAILF_HCC_VERSION=$TAILF_HCC_VERSION --build-arg APP_NAME=$APP_NAME -f Dockerfile .
docker build -t $IMG3_NAME --build-arg NODE3_NAME=$NODE3_NAME -f Dockerfile.$NODE3_NAME .

docker network create --subnet=$SUBNET $NET_NAME

echo "Run the $NODE3_NAME container"
N3_CID="$(docker run --hostname $NODE3_NAME --cap-add NET_ADMIN --net $NET_NAME --ip $NODE3_IP --name $NODE3_NAME -d --rm -p 12024:12024 -e NSO_VIP=$NSO_VIP -e NSO_VIP_NAME=$NSO_VIP_NAME $IMG3_NAME | cut -c1-12)"

while [[ $(docker ps -l -a -q -f status=running | grep $N3_CID) != $N3_CID ]]; do
    echo "waiting..."
    sleep .5
done

echo "Run the $NODE2_NAME container"
N2_CID="$(docker run --hostname $NODE2_NAME --cap-add NET_ADMIN --net $NET_NAME --ip $NODE2_IP --name $NODE2_NAME -d --rm -e NSO_VIP=$NSO_VIP -e NSO_VIP_NAME=$NSO_VIP_NAME -e NODE1_NAME=$NODE1_NAME -e NODE2_NAME=$NODE2_NAME -e NODE1_IP=$NODE1_IP -e NODE2_IP=$NODE2_IP -e NSO_VERSION=$NSO_VERSION $IMG2_NAME | cut -c1-12)"

while [[ $(docker ps -l -a -q -f status=running | grep $N2_CID) != $N2_CID ]]; do
    echo "waiting..."
    sleep .5
done

ecode=1;
while [ $ecode -ne 0 ]; do
    sleep .5
    docker exec -it $NODE2_NAME ncs --wait-started
    ecode=$?
done

echo "Run the $NODE1_NAME container"
N1_CID="$(docker run --hostname $NODE1_NAME --cap-add NET_ADMIN --net $NET_NAME --ip $NODE1_IP --name $NODE1_NAME -d --rm -e NSO_VIP=$NSO_VIP -e NSO_VIP_NAME=$NSO_VIP_NAME -e NODE1_NAME=$NODE1_NAME -e NODE2_NAME=$NODE2_NAME -e NODE1_IP=$NODE1_IP -e NODE2_IP=$NODE2_IP -e NSO_VERSION=$NSO_VERSION $IMG1_NAME | cut -c1-12)"

while [[ $(docker ps -l -a -q -f status=running | grep $N1_CID) != $N1_CID ]]; do
    echo "waiting..."
    sleep .5
done

docker logs $NODE1_NAME --follow
