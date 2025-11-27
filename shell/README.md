
<img width="1842" height="522" alt="image" src="https://github.com/user-attachments/assets/d4ac059d-6b35-45bf-bedc-9937233cfbd1" />
<img width="1316" height="938" alt="image" src="https://github.com/user-attachments/assets/a3ea4a9d-4209-4f83-af11-2f3faee2c54c" />
<img width="2774" height="536" alt="image" src="https://github.com/user-attachments/assets/fe01a90a-73a4-4aa0-8adb-cbb10daaf96c" />


### perf_monitor
```shell
chmod +x perf_monitor.sh
```
```shell
# CentOS/RHEL
yum install -y ifstat bc iproute2

# Ubuntu/Debian
apt install -y ifstat bc iproute2

# MacOS（需先装brew）
brew install ifstat bc
```
基础使用
```shell
./perf_monitor.sh
```
指定时长 + 输出文件 + 自定义磁盘分区
```shell
./perf_monitor.sh --duration 60 --interval 3 --output /tmp/perf.log --disk /data
```
后台运行
```shell
./perf_monitor.sh --duration 300 --interval 5 --daemon --interface ens33
```
查看帮助信息
```shell
./perf_monitor.sh --help
```
