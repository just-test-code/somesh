apt-get install wget unzip -y
cd /home
wget https://cloud.meegar.club/one/share/%E6%9C%8D%E5%8A%A1%E5%99%A8/sudis.zip 
unzip sudis.zip
cd sudis
cp -f diyrun.service /etc/systemd/system/sudis.service
mkdir /opt/sudis
cp -f ./sudis /opt/sudis/sudis
cp -f ./sudis.yaml /opt/sudis/sudis.yaml
cp -rf webui /opt/sudis/webui
chmod +x /opt/sudis/sudis
systemctl enable sudis
systemctl start sudis.service