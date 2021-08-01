#!/bin/bash
apt-get install wget unzip -y
mkdir /opt/kcptun
cd /opt/kcptun
wget https://github.com/xtaci/kcptun/releases/download/v20210624/kcptun-linux-amd64-20210624.tar.gz
tar -xzf kcptun-linux-amd64-20210624.tar.gz