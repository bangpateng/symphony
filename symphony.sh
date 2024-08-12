#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # Tidak ada warna

./logo.sh

HOME=${HOME:-/home/$(whoami)}
echo -e "${GREEN}Using home directory: $HOME${NC}"

echo -e "${CYAN}Masukkan nama validator (MONIKER):${NC}"
read MONIKER
echo -e "${CYAN}Masukkan ID chain (misalnya, symphony-testnet-2):${NC}"
read CHAIN_ID
echo -e "${CYAN}Masukkan port Symphony (misalnya, 15):${NC}"
read SYMPHONY_PORT

echo -e "${GREEN}Menyimpan variabel lingkungan di .bashrc...${NC}"
echo "export MONIKER=$MONIKER" >> $HOME/.bashrc
echo "export CHAIN_ID=$CHAIN_ID" >> $HOME/.bashrc
echo "export SYMPHONY_PORT=$SYMPHONY_PORT" >> $HOME/.bashrc
source $HOME/.bashrc

echo -e "${GREEN}Melanjutkan dengan instalasi dan konfigurasi...${NC}"

sudo apt update && sudo apt upgrade -y
sudo apt install curl tar wget clang pkg-config libssl-dev jq build-essential bsdmainutils git make ncdu gcc jq chrony liblz4-tool -y

wget https://go.dev/dl/go1.22.6.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.22.6.linux-amd64.tar.gz
echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> ~/.bash_profile
source ~/.bash_profile
go version

rm -rf symphony

cd $HOME
git clone https://github.com/Orchestra-Labs/symphony
cd symphony
git checkout v0.2.1

go install -mod=readonly -tags "netgo ledger" -ldflags '-X github.com/cosmos/cosmos-sdk/version.Name=symphony -X github.com/cosmos/cosmos-sdk/version.AppName=symphonyd -X github.com/cosmos/cosmos-sdk/version.Version=0.2.1 -X github.com/cosmos/cosmos-sdk/version.Commit=a17ff13d6cd2605e3a536c529094d852b547664a -X "github.com/cosmos/cosmos-sdk/version.BuildTags=netgo,ledger" -w -s' -trimpath github.com/osmosis-labs/osmosis/v23/cmd/symphonyd

# Verifikasi apakah symphonyd tersedia
if ! command -v symphonyd &> /dev/null; then
    echo -e "${RED}Error: symphonyd command not found. Please check the installation.${NC}"
    exit 1
fi

symphonyd init $MONIKER --chain-id $CHAIN_ID
symphonyd config chain-id $CHAIN_ID
symphonyd config keyring-backend test

wget -O $HOME/.symphonyd/config/genesis.json http://filex.bangpateng.xyz/snapshot/symphony/genesis.json
wget -O $HOME/.symphonyd/config/addrbook.json http://filex.bangpateng.xyz/snapshot/symphony/addrbook.json

seeds=""
sed -i.bak -e "s/^seeds =.*/seeds = \"$seeds\"/" $HOME/.symphonyd/config/config.toml
peers="016eb93b77457cbc8793ba1ee01f7e2fa2e63a3b@136.243.13.36:29156,8df964c61393d33d11f7c821aba1a72f428c0d24@34.41.129.120:26656,298743e0b4813ada523e26922d335a3fb37ec58a@37.27.195.219:26656,785f5e73e26623214269909c0be2df3f767fbe50@35.225.73.240:26656,22e9b542b7f690922e846f479878ab391e69c4c3@57.129.35.242:26656,9d4ee7dea344cc5ca83215cf7bf69ba4001a6c55@5.9.73.170:29156,77ce4b0a96b3c3d6eb2beb755f9f6f573c1b4912@178.18.251.146:22656,27c6b80a1235d41196aa56459689c28f285efd15@136.243.104.103:24856,adc09b9238bc582916abda954b081220d6f9cbc2@34.172.132.224:26656"
sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$peers\"/" $HOME/.symphonyd/config/config.toml
sed -i.bak -e "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0note\"/" $HOME/.symphonyd/config/app.toml

sed -i \
-e 's|^pruning *=.*|pruning = "custom"|' \
-e 's|^pruning-keep-recent *=.*|pruning-keep-recent = "100"|' \
-e 's|^pruning-keep-every *=.*|pruning-keep-every = ""|' \
-e 's|^pruning-interval *=.*|pruning-interval = "10"|' \
$HOME/.symphonyd/config/app.toml

sed -i 's|^indexer *=.*|indexer = "null"|' $HOME/.symphonyd/config/config.toml

echo -e "${GREEN}Mengatur layanan systemd...${NC}"
sudo tee /etc/systemd/system/symphonyd.service > /dev/null <<EOF
[Unit]
Description=symphony
After=network-online.target

[Service]
User=$USER
ExecStart=$(which symphonyd) start
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable symphonyd
sudo systemctl restart symphonyd
sudo journalctl -u symphonyd -f -o cat

echo -e "${CYAN}Displaying current port configurations:${NC}"
rpc_port=$(grep -Po '^\s*laddr = "tcp://0.0.0.0:\K[0-9]+' $HOME/.symphonyd/config/config.toml)
grpc_port=$(grep -Po '^\s*grpc-laddr = "tcp://0.0.0.0:\K[0-9]+' $HOME/.symphonyd/config/config.toml)
api_port=$(grep -Po '^\s*address = "
