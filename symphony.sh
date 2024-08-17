#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${CYAN}[INFO] Fetching and running ...${NC}"
sleep 5
curl -s https://raw.githubusercontent.com/bangpateng/symphony/main/logo.sh | bash
sleep 1

HOME=${HOME:-/home/$(whoami)}
echo -e "${GREEN}Using home directory: $HOME${NC}"

echo -e "${CYAN}Masukkan nama validator (MONIKER):${NC}"
read MONIKER
echo -e "${CYAN}Masukkan ID chain (misalnya, symphony-testnet-3):${NC}"
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
git checkout v0.3.0

go install -mod=readonly -tags "netgo ledger" -ldflags '-X github.com/cosmos/cosmos-sdk/version.Name=symphony -X github.com/cosmos/cosmos-sdk/version.AppName=symphonyd -X github.com/cosmos/cosmos-sdk/version.Version=0.2.1 -X github.com/cosmos/cosmos-sdk/version.Commit=a17ff13d6cd2605e3a536c529094d852b547664a -X "github.com/cosmos/cosmos-sdk/version.BuildTags=netgo,ledger" -w -s' -trimpath github.com/osmosis-labs/osmosis/v23/cmd/symphonyd

# Verifikasi apakah symphonyd tersedia
if ! command -v symphonyd &> /dev/null; then
    echo -e "${RED}Error: symphonyd command not found. Please check the installation.${NC}"
    exit 1
fi

symphonyd init $MONIKER --chain-id $CHAIN_ID
symphonyd config chain-id $CHAIN_ID
symphonyd config keyring-backend test

wget -O $HOME/.symphonyd/config/genesis.json https://raw.githubusercontent.com/Orchestra-Labs/symphony/main/networks/symphony-testnet-3/genesis.json

seeds="10838131d11f546751178df1e1045597aad6366d@34.41.169.77:26656"
sed -i.bak -e "s/^seeds =.*/seeds = \"$seeds\"/" $HOME/.symphonyd/config/config.toml
peers="eea2dc7e9abfd18787d4cc2c728689ad658cd3a2@34.66.161.223:26656,3b8cd0dc5e61e36630a760ec1d3b1e05223624c0@88.99.149.170:21656"
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
