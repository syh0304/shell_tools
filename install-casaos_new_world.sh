#!/usr/bin/bash
#
#           CasaOS Installer Script v0.4.15#
#   GitHub: https://github.com/IceWhaleTech/CasaOS
#   Issues: https://github.com/IceWhaleTech/CasaOS/issues
#   Requires: bash, mv, rm, tr, grep, sed, curl/wget, tar, smartmontools, parted, ntfs-3g, net-tools
#
#   This script installs CasaOS to your system.
#   Usage:
#
#   	$ wget -qO- https://get.casaos.io/ | bash
#   	  or
#   	$ curl -fsSL https://get.casaos.io/ | bash
#
#   In automated environments, you may want to run as root.
#   If using curl, we recommend using the -fsSL flags.
#
#   This only work on  Linux systems. Please
#   open an issue if you notice any bugs.
#
clear
echo -e "\e[0m\c"

# shellcheck disable=SC2016
echo '
   _____                 ____   _____ 
  / ____|               / __ \ / ____|
 | |     __ _ ___  __ _| |  | | (___  
 | |    / _` / __|/ _` | |  | |\___ \ 
 | |___| (_| \__ \ (_| | |__| |____) |
  \_____\__,_|___/\__,_|\____/|_____/ 
                                      
   --- Made by IceWhale with YOU ---
'
export PATH=/usr/sbin:$PATH
export DEBIAN_FRONTEND=noninteractive

set -e

###############################################################################
# GOLBALS                                                                     #
###############################################################################

((EUID)) && sudo_cmd="sudo"

# shellcheck source=/dev/null
source /etc/os-release

# SYSTEM REQUIREMENTS
readonly MINIMUM_DISK_SIZE_GB="5"
readonly MINIMUM_MEMORY="400"
readonly MINIMUM_DOCKER_VERSION="20"
readonly CASA_DEPANDS_PACKAGE=('wget' 'curl' 'smartmontools' 'parted' 'ntfs-3g' 'net-tools' 'udevil' 'samba' 'cifs-utils' 'mergerfs' 'unzip')
readonly CASA_DEPANDS_COMMAND=('wget' 'curl' 'smartctl' 'parted' 'ntfs-3g' 'netstat' 'udevil' 'smbd' 'mount.cifs' 'mount.mergerfs' 'unzip')

# SYSTEM INFO
PHYSICAL_MEMORY=$(LC_ALL=C free -m | awk '/Mem:/ { print $2 }')
readonly PHYSICAL_MEMORY

FREE_DISK_BYTES=$(LC_ALL=C df -P / | tail -n 1 | awk '{print $4}')
readonly FREE_DISK_BYTES

readonly FREE_DISK_GB=$((FREE_DISK_BYTES / 1024 / 1024))

LSB_DIST=$( ([ -n "${ID_LIKE}" ] && echo "${ID_LIKE}") || ([ -n "${ID}" ] && echo "${ID}"))
readonly LSB_DIST

DIST=$(echo "${ID}")
readonly DIST

UNAME_M="$(uname -m)"
readonly UNAME_M

UNAME_U="$(uname -s)"
readonly UNAME_U

readonly CASA_CONF_PATH=/etc/casaos/gateway.ini
readonly CASA_UNINSTALL_URL="https://get.casaos.io/uninstall/v0.4.15"
readonly CASA_UNINSTALL_PATH=/usr/bin/casaos-uninstall

# REQUIREMENTS CONF PATH
# Udevil
readonly UDEVIL_CONF_PATH=/etc/udevil/udevil.conf
readonly DEVMON_CONF_PATH=/etc/conf.d/devmon

# COLORS
readonly COLOUR_RESET='\e[0m'
readonly aCOLOUR=(
    '\e[38;5;154m' # green  	| Lines, bullets and separators
    '\e[1m'        # Bold white	| Main descriptions
    '\e[90m'       # Grey		| Credits
    '\e[91m'       # Red		| Update notifications Alert
    '\e[33m'       # Yellow		| Emphasis
)

readonly GREEN_LINE=" ${aCOLOUR[0]}─────────────────────────────────────────────────────$COLOUR_RESET"
readonly GREEN_BULLET=" ${aCOLOUR[0]}-$COLOUR_RESET"
readonly GREEN_SEPARATOR="${aCOLOUR[0]}:$COLOUR_RESET"

# CASAOS VARIABLES
TARGET_ARCH=""
TMP_ROOT=/tmp/casaos-installer
REGION="UNKNOWN"
# Store the final download domain name
CASA_DOWNLOAD_DOMAIN="https://github.com/"

trap 'onCtrlC' INT
onCtrlC() {
    echo -e "${COLOUR_RESET}"
    exit 1
}

###############################################################################
# Helpers                                                                     #
###############################################################################

#######################################
# Custom printing function
# Globals:
#   None
# Arguments:
#   $1 0:OK   1:FAILED  2:INFO  3:NOTICE
#   message
# Returns:
#   None
#######################################

Show() {
    # OK
    if (($1 == 0)); then
        echo -e "${aCOLOUR[2]}[$COLOUR_RESET${aCOLOUR[0]}  OK  $COLOUR_RESET${aCOLOUR[2]}]$COLOUR_RESET $2"
    # FAILED
    elif (($1 == 1)); then
        echo -e "${aCOLOUR[2]}[$COLOUR_RESET${aCOLOUR[3]}FAILED$COLOUR_RESET${aCOLOUR[2]}]$COLOUR_RESET $2"
        exit 1
    # INFO
    elif (($1 == 2)); then
        echo -e "${aCOLOUR[2]}[$COLOUR_RESET${aCOLOUR[0]} INFO $COLOUR_RESET${aCOLOUR[2]}]$COLOUR_RESET $2"
    # NOTICE
    elif (($1 == 3)); then
        echo -e "${aCOLOUR[2]}[$COLOUR_RESET${aCOLOUR[4]}NOTICE$COLOUR_RESET${aCOLOUR[2]}]$COLOUR_RESET $2"
    fi
}

Warn() {
    echo -e "${aCOLOUR[3]}$1$COLOUR_RESET"
}

GreyStart() {
    echo -e "${aCOLOUR[2]}\c"
}

ColorReset() {
    echo -e "$COLOUR_RESET\c"
}

# Clear Terminal
Clear_Term() {

    # Without an input terminal, there is no point in doing this.
    [[ -t 0 ]] || return

    # Printing terminal height - 1 newlines seems to be the fastest method that is compatible with all terminal types.
    lines=$(tput lines) i newlines
    local lines

    for ((i = 1; i < ${lines% *}; i++)); do newlines+='\n'; done
    echo -ne "\e[0m$newlines\e[H"

}

# Check file exists
exist_file() {
    if [ -e "$1" ]; then
        return 1
    else
        return 2
    fi
}

###############################################################################
# FUNCTIONS                                                                   #
###############################################################################

# ========================================
# Function: Check basic internet connectivity via Bing
# - Tries cn.bing.com (may redirect to bing.com, which is normal)
# - Follows redirects, checks final HTTP 200
# - Handles SSL errors (e.g., corporate proxy)
# - Exits script if unreachable
# ========================================
Get_Bing_Access() {
    local PRIMARY_URL="https://cn.bing.com"
    local FALLBACK_URL="https://www.bing.com"
    local TIMEOUT=15
    local MAX_TIME=30

    echo "🌐 Checking internet connectivity: $PRIMARY_URL (may redirect)"

    # Use curl with:
    #   -L : follow redirects
    #   -k : skip SSL verification (for proxies with MITM certs)
    #   -f : fail on 4xx/5xx (so 000 or 404 fail)
    local HTTP_CODE
    HTTP_CODE=$(curl -s -L -f -k \
                -o /dev/null \
                -w "%{http_code}" \
                --connect-timeout "$TIMEOUT" \
                --max-time "$MAX_TIME" \
                "$PRIMARY_URL" 2>/dev/null || echo "000")

    # ✅ 如果成功（200），说明网络通
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✅ Internet OK: Successfully reached Bing (HTTP 200)"
        return 0
    fi

    # 🔄 如果主站超时或被阻止，尝试备用地址
    if [[ "$HTTP_CODE" =~ ^(000|403|404|500)$ ]]; then
        echo "⚠️  $PRIMARY_URL failed (HTTP $HTTP_CODE), trying fallback: $FALLBACK_URL"

        HTTP_CODE=$(curl -s -L -f -k \
                    -o /dev/null \
                    -w "%{http_code}" \
                    --connect-timeout "$TIMEOUT" \
                    --max-time "$MAX_TIME" \
                    "$FALLBACK_URL" 2>/dev/null || echo "000")

        if [ "$HTTP_CODE" = "200" ]; then
            echo "✅ Internet OK: Reached fallback Bing (HTTP 200)"
            return 0
        fi
    fi

    # ❌ 所有尝试失败
    echo "❌ Failed to reach Bing (Primary: $HTTP_CODE, Fallback: ?)"
    echo "❌ No reliable internet connectivity detected."
    echo "🛑 Exiting script due to network failure."
    exit 1
}

# ========================================
# Function: Check if homepage is accessible and returns valid content
# Input: $1 = URL (e.g., https://github.com)
# Output: Returns 0 if HTTP 2xx/3xx + non-empty body; else 1
# Notes:
#   - Uses HEAD first to check reachability
#   - Then fetches body to verify content length > 100 bytes
#   - Timeout: 10 seconds total
#   - Handles redirects and common HTTP success codes
# ========================================

_curl_with_retry() {
    local url="$1"
    local connect_timeout="$2"
    local max_time="$3"
    local ua="$4"
    local retries="$5"
    local mode="$6"

    local http_code="000"
    local error_msg=""

    for ((i=0; i<=retries; i++)); do
        # 使用 -v 捕获详细错误，通过 2>&1 | grep 精确提取关键信息
        local output
        output=$(curl -sSLk -w "\n%{http_code}" \
                    --connect-timeout "$connect_timeout" \
                    --max-time "$max_time" \
                    -H "User-Agent: $ua" \
                    $mode \
                    -v "$url" 2>&1)

        http_code=$(echo "$output" | tail -n1)

        # 规范化三位码
        if ! echo "$http_code" | grep -qE '^[0-9]{3}$'; then
            http_code="000"
        fi

        if [[ "$http_code" != "000" ]]; then
            # 成功获取状态码，跳出重试
            echo "$http_code"
            return 0
        fi

        # 分析错误原因
        if echo "$output" | grep -q 'Could not resolve host'; then
            error_msg="DNS resolution failed"
        elif echo "$output" | grep -q 'Connection timed out'; then
            error_msg="Connection timed out"
        elif echo "$output" | grep -q 'SSL certificate problem'; then
            error_msg="SSL certificate issue"
        else
            error_msg="Unknown curl error"
        fi

        echo "000 $error_msg" # 返回000和错误信息
        sleep 1 # 重试前稍作等待
    done

    return 1
}

Check_Homepage_Access() {
    local URL="$1"
    local CONNECT_TIMEOUT=10
    local MAX_TIME=20
    local UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome Safari"
    local RETRIES=1
    local GLOBAL_TIMEOUT=30
    local START_TIME
    START_TIME=$(date +%s)

    if [[ -z "$URL" ]]; then
        echo "❌ No URL provided"
        return 1
    fi

    # 统一补全尾部斜杠
    if ! echo "$URL" | grep -qE '/$|\.\w+$'; then
        URL="${URL%/}/"
    fi

    # 特殊处理 ghproxy.com，获取最终重定向的 URL
    if [[ "$URL" == *"ghproxy.com"* ]]; then
        echo "🔍 Detected ghproxy.com, checking final redirect URL..."
        local final_url
        final_url=$(curl -sIL -o /dev/null -w '%{url_effective}' "$URL" 2>/dev/null)
        
        if [ -n "$final_url" ] && [ "$final_url" != "$URL" ]; then
            echo "   → Redirected to: $final_url"
            URL="$final_url"
            # 更新 CASA_DOWNLOAD_DOMAIN 环境变量
            export CASA_DOWNLOAD_DOMAIN="$URL"
        fi
    fi

    echo "🌐 Testing homepage access: $URL"

    local HOST
    HOST=$(printf "%s" "$URL" | sed -e 's|^https\?://||' -e 's|/.*$||')

    local -a CANDIDATE_PATHS=(
        "$URL"
        "${URL%/}/index.html"
        "${URL%/}/healthz"
        "${URL%/}/favicon.ico"
        "${URL%/}/robots.txt"
    )

    case "$HOST" in
        github.com)
            CANDIDATE_PATHS+=("https://github.com/status")
            ;;
        ghproxy.com|ghproxy.link|*.ghproxy.link)
            CANDIDATE_PATHS+=("$URL")
            CANDIDATE_PATHS+=("${URL%/}/status.html")
            ;;
    esac

    local last_code="000"
    local last_error=""

    for candidate in "${CANDIDATE_PATHS[@]}"; do
        local current_time
        current_time=$(date +%s)
        if (( current_time - START_TIME > GLOBAL_TIMEOUT )); then
            echo "❌ Global timeout of ${GLOBAL_TIMEOUT}s reached. Aborting..."
            return 1
        fi
        echo "🔎 Probing: $candidate"

        local modes=(
            "--http1.1 --tlsv1.2"
            "--ipv4"
            ""
        )

        for mode in "${modes[@]}"; do
            local result
            result=$(_curl_with_retry "$candidate" "$CONNECT_TIMEOUT" "$MAX_TIME" "$UA" "$RETRIES" "$mode")
            read -r HTTP_CODE error_msg <<< "$result"

            last_code="$HTTP_CODE"
            last_error="$error_msg"

            case "$HTTP_CODE" in
                2[0-9][0-9])
                    local content
                    content=$(curl -sSLk --compressed \
                                --connect-timeout "$CONNECT_TIMEOUT" \
                                --max-time "$MAX_TIME" \
                                -H "User-Agent: $UA" \
                                $mode \
                                "$candidate" | head -c 4096 || true)
                    local body_size=${#content}

                    if [[ "$body_size" -gt 100 ]] && (echo "$content" | grep -qiE '<html|<body|\{"status":"ok"\}'); then
                        echo "✅ HTTP $HTTP_CODE, content ~${body_size} bytes, validation passed."
                        return 0
                    else
                        echo "⚠️  HTTP $HTTP_CODE but body validation failed (size: ${body_size}B), trying next."
                    fi
                    ;;
                3[0-9][0-9]|401|403|405)
                    echo "✅ Reachable with HTTP $HTTP_CODE (Redirect/Auth)"
                    return 0
                    ;;
                404)
                    echo "ℹ️  Got 404 on $candidate, trying next path..."
                    break # 当前路径404，没必要再试其他模式
                    ;;
                000)
                    echo "⚠️  Network/SSL issue (000) with mode: [$mode]. Details: $last_error. Retrying..."
                    ;;
                *)
                    echo "ℹ️  HTTP $HTTP_CODE with mode: [$mode], retrying..."
                    ;;
            esac
        done
    done

    echo "❌ Unable to verify accessibility. Last HTTP code: $last_code. Last error: $last_error"
    return 1
}

# ========================================
# Function: Test network status (5 pings, loss < 20%, avg latency < 500ms)
# Input: $1 = host (e.g., github.com)
# Output: Global variables LOSS_RATE (integer %), PING_AVG (integer ms)
# Changes:
#   - Increased timeout to 30s to avoid premature kill
#   - Fixed packet loss calculation (now accurate)
#   - Supports English/Chinese output
#   - Robust parsing of ping stats
# ========================================

Get_Network_Status() {
    local HOST="$1"
    local COUNT=5
    local PING_OUTPUT=""
    local LOSS_RATE=100
    local PING_AVG=9999

    # 确保 ping 命令以 C 语言环境运行，保证输出格式一致性
    # 实时显示 ping 输出
    echo "📡 Pinging $HOST ($COUNT packets, 2s timeout)..."
    PING_OUTPUT=$(LC_ALL=C ping -c "$COUNT" -W 2 "$HOST" 2>&1 | tee /dev/tty)

    # 使用更健壮的 awk 解析丢包率
    LOSS_RATE=$(echo "$PING_OUTPUT" | awk '/packet loss/ {gsub(/%/, ""); print $(NF-4)}' | head -n1)
    LOSS_RATE=${LOSS_RATE:-100}

    # 使用更健壮的 awk 解析平均延迟，并正确处理浮点数到整数的转换
    PING_AVG=$(echo "$PING_OUTPUT" | awk -F'=' '/rtt/ {gsub(/ /, "", $2); split($2, a, "/"); print a[2]}' | head -n1 | cut -d. -f1)
    PING_AVG=${PING_AVG:-9999}

    # 通过 echo 返回两个值，而不是 export
    echo "$LOSS_RATE $PING_AVG"
}


# ========================================
# Function: Test download speed with a small file (timeout 10s)
# Input: $1 = Download URL (optional)
# Output: Global variable DOWNLOAD_SPEED_MB_S (MB/s, float)
# Notes:
#   - Uses wget to download within 10 seconds
#   - Falls back to a small GitHub tarball if no URL provided
#   - Calculates speed as MB/s with 2 decimal places
#   - Sets DOWNLOAD_SPEED_MB_S = 0 on failure
# ========================================
Get_Network_Speed() {
    local TEST_URL="${1}"  # 使用传入的URL
    local TEMP_FILE="/tmp/speedtest_$$.bin"
    local MAX_TEST_TIME=120
    local TIMEOUT_CMD="timeout $MAX_TEST_TIME"
    local START_TIME
    local END_TIME
    local DURATION
    local FILE_SIZE
    local SIZE_KB
    local AVG_SPEED
    local FORMATTED_SIZE
    local FORMATTED_DURATION
    local FORMATTED_AVG
    local CURRENT_TIME
    local CURRENT_SIZE
    local ELAPSED
    local DIFF_SIZE
    local SPEED_KB_S

    # 定义颜色代码
    local GREEN='\033[0;32m'
    local NC='\033[0m' # No Color

    # 清理临时文件
    trap 'rm -f "$TEMP_FILE"' EXIT

    echo "⏬ Starting network speed test (max $MAX_TEST_TIME s) from URL: $TEST_URL"
    echo "📊 Real-time download speed will be shown below:"
    echo "🔗 Downloading from: $TEST_URL"

    START_TIME=$(date +%s.%N)

    # 启动下载，忽略错误
    set +e
    $TIMEOUT_CMD wget -q --show-progress=no -O "$TEMP_FILE" "$TEST_URL" >/dev/null 2>&1 &
    local WGET_PID=$!
    
    # 实时显示下载速度
    local PREV_SIZE=0
    local PREV_TIME=$START_TIME
    local SPEED_UPDATE_INTERVAL=1  # 更新间隔（秒）
    
    while kill -0 "$WGET_PID" 2>/dev/null; do
        sleep $SPEED_UPDATE_INTERVAL
        
        CURRENT_TIME=$(date +%s.%N)
        CURRENT_SIZE=$(wc -c < "$TEMP_FILE" 2>/dev/null || echo 0)
        ELAPSED=$(echo "$CURRENT_TIME - $PREV_TIME" | bc -l)
        
        if [ "$(echo "$ELAPSED >= $SPEED_UPDATE_INTERVAL" | bc -l)" -eq 1 ] && [ "$(echo "$ELAPSED > 0" | bc -l)" -eq 1 ]; then
            DIFF_SIZE=$((CURRENT_SIZE - PREV_SIZE))
            
            if [ "$DIFF_SIZE" -gt 0 ]; then
                SIZE_KB=$(echo "scale=2; $DIFF_SIZE / 1024" | bc -l)
                SPEED_KB_S=$(echo "scale=2; $SIZE_KB / $ELAPSED" | bc -l)
                printf "\r${GREEN}⏬ Downloading: %.2f KB/s${NC}" "$SPEED_KB_S"
            fi
            
            PREV_SIZE=$CURRENT_SIZE
            PREV_TIME=$CURRENT_TIME
        fi
    done
    
    wait "$WGET_PID" 2>/dev/null || true
    set -e

    END_TIME=$(date +%s.%N)
    DURATION=$(echo "$END_TIME - $START_TIME" | bc -l)

    # 如果下载失败或超时
    if [ ! -f "$TEMP_FILE" ] || [ "$(wc -c < "$TEMP_FILE" 2>/dev/null || echo 0)" -eq 0 ]; then
        echo -e "\n⚠️  Download failed or timed out, will try next source..."
        DOWNLOAD_SPEED_KB_S=0
        export DOWNLOAD_SPEED_KB_S
        return 0
    fi

    # 防止除零
    if [ "$(echo "$DURATION <= 0.01" | bc -l)" -eq 1 ]; then
        DURATION=0.1
    fi

    FILE_SIZE=$(wc -c < "$TEMP_FILE" 2>/dev/null || echo 0)
    if [ "$FILE_SIZE" -eq 0 ]; then
        echo -e "\n⚠️  No data downloaded, will try next source..."
        DOWNLOAD_SPEED_KB_S=0
        export DOWNLOAD_SPEED_KB_S
        return 0
    else
        SIZE_KB=$(echo "scale=2; $FILE_SIZE / 1024" | bc -l)
        AVG_SPEED=$(echo "scale=2; $SIZE_KB / $DURATION" | bc -l)

        # 最终结果也用 awk 格式化
        FORMATTED_SIZE=$(echo "$SIZE_KB" | awk '{printf "%.2f", $1}')
        FORMATTED_DURATION=$(echo "$DURATION" | awk '{printf "%.2f", $1}')
        FORMATTED_AVG=$(echo "$AVG_SPEED" | awk '{printf "%.2f", $1}')

        echo -e "\n✅ Downloaded ${FORMATTED_SIZE} KB in ${FORMATTED_DURATION} s → Avg Speed: ${FORMATTED_AVG} KB/s"
        DOWNLOAD_SPEED_KB_S="$FORMATTED_AVG"
        export DOWNLOAD_SPEED_KB_S
    fi

    return 0
}

# ========================================
# Function: Automatically select the fastest download source by testing speed on actual CasaOS packages
# Input: None (uses global variables)
# Output: Sets global CASA_DOWNLOAD_DOMAIN to the best performing domain
# Process:
#   - Tests accessibility and download speed of each candidate using a real CasaOS package
#   - Prioritizes GitHub if its speed >= 1 MB/s, otherwise uses the fastest mirror
# ========================================
Get_Download_Url_Domain() {
    # 定义颜色代码
    local ORANGE='\033[0;33m'  # 橘红色
    local GREEN='\033[0;32m'
    local CYAN='\033[0;36m'  # 天蓝色
    local NC='\033[0m' # No Color
    
    # source ./check_homepage_access.sh # Notes here that the function Check_Homepage_Access() has been defined in this script
    
    # 速度阈值选择
    echo "📶 Select minimum download speed threshold (unit: KB/s):"
    echo "1) 20 KB/s"
    echo "2) 50 KB/s"
    echo "3) 100 KB/s"
    echo "4) 200 KB/s"
    echo "5) 500 KB/s (default)"
    echo "6) 1000 KB/s"
    read -p "Enter your choice [1-6] (default 5): " speed_choice
    
    case $speed_choice in
        1) threshold_speed=20 ;;
        2) threshold_speed=50 ;;
        3) threshold_speed=100 ;;
        4) threshold_speed=200 ;;
        5|"") threshold_speed=500 ;;
        6) threshold_speed=1000 ;;
        *) 
            echo "⚠️  Invalid choice, using default 500 KB/s"
            threshold_speed=500 
            ;;
    esac
    
    echo "ℹ️  Using speed threshold: ${threshold_speed} KB/s"
    
    # 定义基础域名和下载路径
    local download_link_tail="IceWhaleTech/CasaOS-CLI/releases/download/v0.4.4-3-alpha1/linux-amd64-casaos-cli-v0.4.4-3-alpha1.tar.gz"
    local base_domains=(
        "https://github.com"
        "https://casaos.oss-cn-shanghai.aliyuncs.com"
        "https://ghproxy.link/https://github.com"
    )

    # 构建候选源数组
    local CANDIDATES=()
    for domain in "${base_domains[@]}"; do
        # 处理 ghproxy 的特殊情况
        if [[ "$domain" == *"ghproxy.link"* ]]; then
            CANDIDATES+=("$domain,$domain/$download_link_tail")
        else
            CANDIDATES+=("$domain/,$domain/$download_link_tail")
        fi
    done

    echo "🔍 Starting automatic source selection using real CasaOS packages..."
    echo "==============================================================="

    # 确保基本网络连接
    Get_Bing_Access

    local best_domain=""
    local best_speed=0
    local available_domains=()

    # 第一轮：检查可访问性
    for candidate in "${CANDIDATES[@]}"; do
        local DOMAIN
        DOMAIN=$(echo "$candidate" | cut -d',' -f1)
        local HOST
        HOST=$(echo "$DOMAIN" | sed -e 's|https\?://||' -e 's|/.*$||')

        echo -e "\n🌐 Testing source: $DOMAIN"

        # 检查可访问性
        if ! Check_Homepage_Access "$DOMAIN"; then
            echo "❌ $DOMAIN is unreachable or returned invalid content"
            continue
        fi

        echo "✅ $DOMAIN is accessible"
        available_domains+=("$candidate")

        # 测试主机连接
        echo "🌐 Testing HOST: $HOST"
        Get_Network_Status "$HOST"
        echo "---------------------------------------------------------------"
    done

    # 如果没有可用的域名，直接返回
    if [ ${#available_domains[@]} -eq 0 ]; then
        CASA_DOWNLOAD_DOMAIN="https://github.com/"
        echo -e "${GREEN}⚠️  No available download source found, using default: $CASA_DOWNLOAD_DOMAIN${NC}"
        echo -e "${GREEN}✅ Final download domain: $CASA_DOWNLOAD_DOMAIN${NC}"
        echo "==============================================================="
        return 1
    fi

    # 第二轮：速度测试
    local github_speed=0
    
    for candidate in "${CANDIDATES[@]}"; do
        local DOMAIN
        DOMAIN=$(echo "$candidate" | cut -d',' -f1)
        local TEST_URL
        TEST_URL=$(echo "$candidate" | cut -d',' -f2 | xargs)  # Use xargs to remove possible whitespace characters.
        
        echo -e "\n⏳ Testing download speed for: $DOMAIN"
        
        
        Get_Network_Speed "$TEST_URL"
        local current_speed
        current_speed=${DOWNLOAD_SPEED_KB_S:-0}
        
        # 如果是GitHub且速度超过阈值，直接选择
        if [ "$DOMAIN" = "https://github.com/" ]; then
            github_speed=$current_speed
            if (( $(echo "$github_speed >= $threshold_speed" | bc -l) )); then
                best_domain="$DOMAIN"
                best_speed=$github_speed
                echo -e "${CYAN}🔗 Download link: $TEST_URL${NC}"
                echo -e "${GREEN}🏆 GitHub speed (${github_speed} KB/s) meets threshold (${threshold_speed} KB/s), selected!${NC}"
                break
            fi
        fi

        # 更新最快速度
        if (( $(echo "$current_speed > $best_speed" | bc -l) )); then
            best_speed=$current_speed
            best_domain="$DOMAIN"
        fi

        echo -e "${CYAN}🔗 Download link: $TEST_URL${NC}"
        echo -e "${GREEN}⏬ Current speed: ${current_speed} KB/s${NC}, Best so far: ${best_speed} KB/s"
        echo "---------------------------------------------------------------"
    done

    # 如果没有找到满足阈值的GitHub，选择最快的
    if [ -z "$best_domain" ] || [ "$best_domain" != "https://github.com/" ]; then
        if (( $(echo "$best_speed > 0" | bc -l) )); then
            echo -e "${GREEN}🏆 Selected fastest available source: $best_domain (${best_speed} KB/s)${NC}"
        else
            # 如果所有源速度测试都失败，选择第一个可用的
            best_candidate="${available_domains[0]}"
            best_domain=$(echo "$best_candidate" | cut -d',' -f1)
            echo -e "${GREEN}⚠️  All speed tests failed, using first available source: $best_domain${NC}"
        fi
    fi

    # 设置最终下载域名
    CASA_DOWNLOAD_DOMAIN="$best_domain"
    echo -e "${CYAN}ℹ️ Using speed threshold: ${threshold_speed} KB/s"
    echo -e "${ORANGE}✅ Final download domain: $CASA_DOWNLOAD_DOMAIN (Speed: ${best_speed} KB/s)${NC}"
    echo "========================================"

}

# 1 Check Arch
Check_Arch() {
    case $UNAME_M in
    *aarch64*)
        TARGET_ARCH="arm64"
        ;;
    *64*)
        TARGET_ARCH="amd64"
        ;;
    *armv7*)
        TARGET_ARCH="arm-7"
        ;;
    *)
        Show 1 "Aborted, unsupported or unknown architecture: $UNAME_M"
        exit 1
        ;;
    esac
    Show 0 "Your hardware architecture is : $UNAME_M"
    CASA_PACKAGES=(
        "${CASA_DOWNLOAD_DOMAIN}IceWhaleTech/CasaOS-Gateway/releases/download/v0.4.9-alpha4/linux-${TARGET_ARCH}-casaos-gateway-v0.4.9-alpha4.tar.gz"
"${CASA_DOWNLOAD_DOMAIN}IceWhaleTech/CasaOS-MessageBus/releases/download/v0.4.4-3-alpha2/linux-${TARGET_ARCH}-casaos-message-bus-v0.4.4-3-alpha2.tar.gz"
"${CASA_DOWNLOAD_DOMAIN}IceWhaleTech/CasaOS-UserService/releases/download/v0.4.8/linux-${TARGET_ARCH}-casaos-user-service-v0.4.8.tar.gz"
"${CASA_DOWNLOAD_DOMAIN}IceWhaleTech/CasaOS-LocalStorage/releases/download/v0.4.4/linux-${TARGET_ARCH}-casaos-local-storage-v0.4.4.tar.gz"
"${CASA_DOWNLOAD_DOMAIN}IceWhaleTech/CasaOS-AppManagement/releases/download/v0.4.10-alpha2/linux-${TARGET_ARCH}-casaos-app-management-v0.4.10-alpha2.tar.gz"
"${CASA_DOWNLOAD_DOMAIN}IceWhaleTech/CasaOS/releases/download/v0.4.15/linux-${TARGET_ARCH}-casaos-v0.4.15.tar.gz"
"${CASA_DOWNLOAD_DOMAIN}IceWhaleTech/CasaOS-CLI/releases/download/v0.4.4-3-alpha1/linux-${TARGET_ARCH}-casaos-cli-v0.4.4-3-alpha1.tar.gz"
"${CASA_DOWNLOAD_DOMAIN}IceWhaleTech/CasaOS-UI/releases/download/v0.4.20/linux-all-casaos-v0.4.20.tar.gz"
"${CASA_DOWNLOAD_DOMAIN}IceWhaleTech/CasaOS-AppStore/releases/download/v0.4.5/linux-all-appstore-v0.4.5.tar.gz" 
    )
}

# PACKAGE LIST OF CASAOS (make sure the services are in the right order)
CASA_SERVICES=(
    "casaos-gateway.service"
"casaos-message-bus.service"
"casaos-user-service.service"
"casaos-local-storage.service"
"casaos-app-management.service"
"rclone.service"
"casaos.service"  # must be the last one so update from UI can work 
)

# 2 Check Distribution
Check_Distribution() {
    sType=0
    notice=""
    case $LSB_DIST in
    *debian*) ;;

    *ubuntu*) ;;

    *raspbian*) ;;

    *openwrt*)
        Show 1 "Aborted, OpenWrt cannot be installed using this script."
        exit 1
        ;;
    *alpine*)
        Show 1 "Aborted, Alpine installation is not yet supported."
        exit 1
        ;;
    *trisquel*) ;;

    *)
        sType=3
        notice="We have not tested it on this system and it may fail to install."
        ;;
    esac
    Show ${sType} "Your Linux Distribution is : ${DIST} ${notice}"

    if [[ ${sType} == 1 ]]; then
        select yn in "Yes" "No"; do
            case $yn in
            [yY][eE][sS] | [yY])
                Show 0 "Distribution check has been ignored."
                break
                ;;
            [nN][oO] | [nN])
                Show 1 "Already exited the installation."
                exit 1
                ;;
            esac
        done < /dev/tty # < /dev/tty is used to read the input from the terminal
    fi
}

# 3 Check OS
Check_OS() {
    if [[ $UNAME_U == *Linux* ]]; then
        Show 0 "Your System is : $UNAME_U"
    else
        Show 1 "This script is only for Linux."
        exit 1
    fi
}

# 4 Check Memory
Check_Memory() {
    if [[ "${PHYSICAL_MEMORY}" -lt "${MINIMUM_MEMORY}" ]]; then
        Show 1 "requires atleast 400MB physical memory."
        exit 1
    fi
    Show 0 "Memory capacity check passed."
}

# 5 Check Disk
Check_Disk() {
    if [[ "${FREE_DISK_GB}" -lt "${MINIMUM_DISK_SIZE_GB}" ]]; then
        echo -e "${aCOLOUR[4]}Recommended free disk space is greater than ${MINIMUM_DISK_SIZE_GB}GB, Current free disk space is ${aCOLOUR[3]}${FREE_DISK_GB}GB${COLOUR_RESET}${aCOLOUR[4]}.\nContinue installation?${COLOUR_RESET}"
        select yn in "Yes" "No"; do
            case $yn in
            [yY][eE][sS] | [yY])
                Show 0 "Disk capacity check has been ignored."
                break
                ;;
            [nN][oO] | [nN])
                Show 1 "Already exited the installation."
                exit 1
                ;;
            esac
        done < /dev/tty  # < /dev/tty is used to read the input from the terminal
    else
        Show 0 "Disk capacity check passed."
    fi
}

# Check Port Use
Check_Port() {
    TCPListeningnum=$(${sudo_cmd} netstat -an | grep ":$1 " | awk '$1 == "tcp" && $NF == "LISTEN" {print $0}' | wc -l)
    UDPListeningnum=$(${sudo_cmd} netstat -an | grep ":$1 " | awk '$1 == "udp" && $NF == "0.0.0.0:*" {print $0}' | wc -l)
    ((Listeningnum = TCPListeningnum + UDPListeningnum))
    if [[ $Listeningnum == 0 ]]; then
        echo "0"
    else
        echo "1"
    fi
}

# Get an available port
Get_Port() {
    CurrentPort=$(${sudo_cmd} cat ${CASA_CONF_PATH} | grep HttpPort | awk '{print $3}')
    if [[ $CurrentPort == "$Port" ]]; then
        for PORT in {80..65536}; do
            if [[ $(Check_Port "$PORT") == 0 ]]; then
                Port=$PORT
                break
            fi
        done
    else
        Port=$CurrentPort
    fi
}

# Update package

Update_Package_Resource() {
    Show 2 "Updating package manager..."
    GreyStart
    if [ -x "$(command -v apk)" ]; then
        ${sudo_cmd} apk update
    elif [ -x "$(command -v apt-get)" ]; then
        ${sudo_cmd} apt-get update -qq
    elif [ -x "$(command -v dnf)" ]; then
        ${sudo_cmd} dnf check-update
    elif [ -x "$(command -v zypper)" ]; then
        ${sudo_cmd} zypper update
    elif [ -x "$(command -v yum)" ]; then
        ${sudo_cmd} yum update
    fi
    ColorReset
    Show 0 "Update package manager complete."
}

# Install depends package
Install_Depends() {
    for ((i = 0; i < ${#CASA_DEPANDS_COMMAND[@]}; i++)); do
        cmd=${CASA_DEPANDS_COMMAND[i]}
        if [[ ! -x $(${sudo_cmd} which "$cmd") ]]; then
            packagesNeeded=${CASA_DEPANDS_PACKAGE[i]}
            Show 2 "Install the necessary dependencies: \e[33m$packagesNeeded \e[0m"
            GreyStart
            if [ -x "$(command -v apk)" ]; then
                ${sudo_cmd} apk add --no-cache "$packagesNeeded"
            elif [ -x "$(command -v apt-get)" ]; then
                ${sudo_cmd} apt-get -y -qq install "$packagesNeeded" --no-upgrade
            elif [ -x "$(command -v dnf)" ]; then
                ${sudo_cmd} dnf install "$packagesNeeded"
            elif [ -x "$(command -v zypper)" ]; then
                ${sudo_cmd} zypper install "$packagesNeeded"
            elif [ -x "$(command -v yum)" ]; then
                ${sudo_cmd} yum install -y "$packagesNeeded"
            elif [ -x "$(command -v pacman)" ]; then
                ${sudo_cmd} pacman -S "$packagesNeeded"
            elif [ -x "$(command -v paru)" ]; then
                ${sudo_cmd} paru -S "$packagesNeeded"
            else
                Show 1 "Package manager not found. You must manually install: \e[33m$packagesNeeded \e[0m"
            fi
            ColorReset
        fi
    done
}

Check_Dependency_Installation() {
    for ((i = 0; i < ${#CASA_DEPANDS_COMMAND[@]}; i++)); do
        cmd=${CASA_DEPANDS_COMMAND[i]}
        if [[ ! -x $(${sudo_cmd} which "$cmd") ]]; then
            packagesNeeded=${CASA_DEPANDS_PACKAGE[i]}
            Show 1 "Dependency \e[33m$packagesNeeded \e[0m installation failed, please try again manually!"
            exit 1
        fi
    done
}

# Check Docker running
Check_Docker_Running() {
    for ((i = 1; i <= 3; i++)); do
        sleep 3
        if [[ ! $(${sudo_cmd} systemctl is-active docker) == "active" ]]; then
            Show 1 "Docker is not running, try to start"
            ${sudo_cmd} systemctl start docker
        else
            break
        fi
    done
}

#Check Docker Installed and version
Check_Docker_Install() {
    if [[ -x "$(command -v docker)" ]]; then
        Docker_Version=$(${sudo_cmd} docker version --format '{{.Server.Version}}')
        if [[ $? -ne 0 ]]; then
            Install_Docker
        elif [[ ${Docker_Version:0:2} -lt "${MINIMUM_DOCKER_VERSION}" ]]; then
            Show 1 "Recommended minimum Docker version is \e[33m${MINIMUM_DOCKER_VERSION}.xx.xx\e[0m,\Current Docker version is \e[33m${Docker_Version}\e[0m,\nPlease uninstall current Docker and rerun the CasaOS installation script."
            exit 1
        else
            Show 0 "Current Docker version is ${Docker_Version}."
        fi
    else
        Install_Docker
    fi
}

# Check Docker installed
Check_Docker_Install_Final() {
    if [[ -x "$(command -v docker)" ]]; then
        Docker_Version=$(${sudo_cmd} docker version --format '{{.Server.Version}}')
        if [[ $? -ne 0 ]]; then
            Install_Docker
        elif [[ ${Docker_Version:0:2} -lt "${MINIMUM_DOCKER_VERSION}" ]]; then
            Show 1 "Recommended minimum Docker version is \e[33m${MINIMUM_DOCKER_VERSION}.xx.xx\e[0m,\Current Docker version is \e[33m${Docker_Version}\e[0m,\nPlease uninstall current Docker and rerun the CasaOS installation script."
            exit 1
        else
            Show 0 "Current Docker version is ${Docker_Version}."
            Check_Docker_Running
        fi
    else
        Show 1 "Installation failed, please run 'curl -fsSL https://get.docker.com | bash' and rerun the CasaOS installation script."
        exit 1
    fi
}

#Install Docker
Install_Docker() {
    Show 2 "Install the necessary dependencies: \e[33mDocker \e[0m"
    if [[ ! -d "${PREFIX}/etc/apt/sources.list.d" ]]; then
        ${sudo_cmd} mkdir -p "${PREFIX}/etc/apt/sources.list.d"
    fi
    GreyStart
    if [[ "${REGION}" = "China" ]] || [[ "${REGION}" = "CN" ]]; then
        ${sudo_cmd} curl -fsSL https://play.cuse.eu.org/get_docker.sh | bash -s docker --mirror Aliyun
    else
        ${sudo_cmd} curl -fsSL https://get.docker.com | bash
    fi
    ColorReset
    if [[ $? -ne 0 ]]; then
        Show 1 "Installation failed, please try again."
        exit 1
    else
        Check_Docker_Install_Final
    fi
}

#Install Rclone
Install_rclone_from_source() {
  ${sudo_cmd} wget -qO ./install.sh https://rclone.org/install.sh
  if [[ "${REGION}" = "China" ]] || [[ "${REGION}" = "CN" ]]; then
    sed -i 's/downloads.rclone.org/casaos.oss-cn-shanghai.aliyuncs.com/g' ./install.sh
  else
    sed -i 's/downloads.rclone.org/get.casaos.io/g' ./install.sh
  fi
  ${sudo_cmd} chmod +x ./install.sh
  ${sudo_cmd} ./install.sh || {
    Show 1 "Installation failed, please try again."
    ${sudo_cmd} rm -rf install.sh
    exit 1
  }
  ${sudo_cmd} rm -rf install.sh
  Show 0 "Rclone v1.61.1 installed successfully."
}

Install_Rclone() {
  Show 2 "Install the necessary dependencies: Rclone"
  if [[ -x "$(command -v rclone)" ]]; then
    version=$(rclone --version 2>>errors | head -n 1)
    target_version="rclone v1.61.1"
    rclone1="${PREFIX}/usr/share/man/man1/rclone.1.gz"
    if [ "$version" != "$target_version" ]; then
      Show 3 "Will change rclone from $version to $target_version."
      rclone_path=$(command -v rclone)
      ${sudo_cmd} rm -rf "${rclone_path}"
      if [[ -f "$rclone1" ]]; then
        ${sudo_cmd} rm -rf "$rclone1"
      fi
      Install_rclone_from_source
    else
      Show 2 "Target version already installed."
    fi
  else
    Install_rclone_from_source
  fi
  ${sudo_cmd} systemctl enable rclone || Show 3 "Service rclone does not exist."
}

#Configuration Addons
Configuration_Addons() {
    Show 2 "Configuration CasaOS Addons"
    #Remove old udev rules
    if [[ -f "${PREFIX}/etc/udev/rules.d/11-usb-mount.rules" ]]; then
        ${sudo_cmd} rm -rf "${PREFIX}/etc/udev/rules.d/11-usb-mount.rules"
    fi

    if [[ -f "${PREFIX}/etc/systemd/system/usb-mount@.service" ]]; then
        ${sudo_cmd} rm -rf "${PREFIX}/etc/systemd/system/usb-mount@.service"
    fi

    #Udevil
    if [[ -f $PREFIX${UDEVIL_CONF_PATH} ]]; then

        # GreyStart
        # Add a devmon user
        USERNAME=devmon
        id ${USERNAME} &>/dev/null || {
            ${sudo_cmd} useradd -M -u 300 ${USERNAME}
            ${sudo_cmd} usermod -L ${USERNAME}
        }

        ${sudo_cmd} sed -i '/exfat/s/, nonempty//g' "$PREFIX"${UDEVIL_CONF_PATH}
        ${sudo_cmd} sed -i '/default_options/s/, noexec//g' "$PREFIX"${UDEVIL_CONF_PATH}
        ${sudo_cmd} sed -i '/^ARGS/cARGS="--mount-options nosuid,nodev,noatime --ignore-label EFI"' "$PREFIX"${DEVMON_CONF_PATH}

        # Add and start Devmon service
        GreyStart
        ${sudo_cmd} systemctl enable devmon@devmon
        ${sudo_cmd} systemctl start devmon@devmon
        ColorReset
        # ColorReset
    fi
}

# Download And Install CasaOS
DownloadAndInstallCasaOS() {
    # 确保必要的环境变量已设置
    : ${TMP_ROOT:="/tmp/casaos-install"}
    : ${PREFIX:=""}
    : ${CASA_DOWNLOAD_DOMAIN:="https://github.com/"}
    : ${CASA_UNINSTALL_URL:="https://raw.githubusercontent.com/IceWhaleTech/get/main/uninstall.sh"}
    : ${CASA_UNINSTALL_PATH:="/usr/bin/casaos-uninstall"}

    # 清理并创建临时目录
    if [ -z "${BUILD_DIR}" ]; then
        ${sudo_cmd} rm -rf "${TMP_ROOT}" || Show 2 "Warning: Failed to clean temp directory"
        mkdir -p "${TMP_ROOT}" || Show 1 "Failed to create temporary directory"
        TMP_DIR=$(${sudo_cmd} mktemp -d -p "${TMP_ROOT}") || Show 1 "Failed to create temporary directory"

        pushd "${TMP_DIR}" || Show 1 "Failed to change to temp directory"

        # 下载安装包
        for PACKAGE in "${CASA_PACKAGES[@]}"; do
            Show 2 "Downloading ${PACKAGE}..."
            if ! GreyStart; then
                Show 2 "Warning: Failed to start progress indicator"
            fi
            if ! ${sudo_cmd} wget -t 3 -q --show-progress -c "${PACKAGE}"; then
                Show 1 "Failed to download package: ${PACKAGE}"
                return 1
            fi
            if ! ColorReset; then
                Show 2 "Warning: Failed to reset color"
            fi
        done

        # 解压安装包
        for PACKAGE_FILE in linux-*.tar.gz; do
            [ -f "${PACKAGE_FILE}" ] || continue
            Show 2 "Extracting ${PACKAGE_FILE}..."
            if ! GreyStart; then
                Show 2 "Warning: Failed to start progress indicator"
            fi
            if ! ${sudo_cmd} tar zxf "${PACKAGE_FILE}"; then
                Show 1 "Failed to extract package: ${PACKAGE_FILE}"
                return 1
            fi
            if ! ColorReset; then
                Show 2 "Warning: Failed to reset color"
            fi
        done

        BUILD_DIR=$(${sudo_cmd} realpath -e "${TMP_DIR}"/build 2>/dev/null)
        if [ -z "${BUILD_DIR}" ]; then
            Show 1 "Failed to find build directory"
            return 1
        fi

        popd || Show 1 "Failed to return from temp directory"
    fi

    # 停止服务
    for SERVICE in "${CASA_SERVICES[@]}"; do
        if ${sudo_cmd} systemctl --quiet is-active "${SERVICE}"; then
            Show 2 "Stopping ${SERVICE}..."
            if ! ${sudo_cmd} systemctl stop "${SERVICE}"; then
                Show 3 "Warning: Failed to stop service ${SERVICE}"
            fi
        fi
    done

    # 运行迁移脚本
    MIGRATION_SCRIPT_DIR=$(realpath -e "${BUILD_DIR}"/scripts/migration/script.d 2>/dev/null)
    if [ -z "${MIGRATION_SCRIPT_DIR}" ]; then
        Show 1 "Failed to find migration script directory"
        return 1
    fi

    for MIGRATION_SCRIPT in "${MIGRATION_SCRIPT_DIR}"/*.sh; do
        [ -f "${MIGRATION_SCRIPT}" ] || continue
        Show 2 "Running ${MIGRATION_SCRIPT}..."
        if ! ${sudo_cmd} bash "${MIGRATION_SCRIPT}"; then
            Show 3 "Warning: Failed to run migration script: ${MIGRATION_SCRIPT}"
        fi
    done

    # 安装 CasaOS
    Show 2 "Installing CasaOS..."
    SYSROOT_DIR=$(realpath -e "${BUILD_DIR}"/sysroot 2>/dev/null)
    if [ -z "${SYSROOT_DIR}" ]; then
        Show 1 "Failed to find sysroot directory"
        return 1
    fi

    # 创建清单文件
    MANIFEST_DIR="${SYSROOT_DIR}/var/lib/casaos"
    ${sudo_cmd} mkdir -p "${MANIFEST_DIR}" || Show 3 "Warning: Failed to create manifest directory"
    MANIFEST_FILE="${MANIFEST_DIR}/manifest"
    
    ${sudo_cmd} touch "${MANIFEST_FILE}" || Show 3 "Warning: Failed to create manifest file"
    find "${SYSROOT_DIR}" -type f 2>/dev/null | ${sudo_cmd} cut -c $(( ${#SYSROOT_DIR} + 1 ))- | ${sudo_cmd} tee "${MANIFEST_FILE}" >/dev/null || 
        Show 3 "Warning: Failed to create manifest"

    # 复制文件
    if ! ${sudo_cmd} cp -rf "${SYSROOT_DIR}"/* / 2>/dev/null; then
        Show 1 "Failed to install CasaOS"
        return 1
    fi

    # 运行设置脚本
    SETUP_SCRIPT_DIR=$(realpath -e "${BUILD_DIR}"/scripts/setup/script.d 2>/dev/null)
    if [ -n "${SETUP_SCRIPT_DIR}" ]; then
        for SETUP_SCRIPT in "${SETUP_SCRIPT_DIR}"/*.sh; do
            [ -f "${SETUP_SCRIPT}" ] || continue
            Show 2 "Running ${SETUP_SCRIPT}..."
            if ! ${sudo_cmd} bash "${SETUP_SCRIPT}"; then
                Show 3 "Warning: Failed to run setup script: ${SETUP_SCRIPT}"
            fi
        done
    fi

    # 更新应用商店配置
    APP_CONF_FILE="${PREFIX}/etc/casaos/app-management.conf"
    if [ -f "${APP_CONF_FILE}" ]; then
        # # 确保 CASA_DOWNLOAD_DOMAIN 格式正确
        # CASA_DOWNLOAD_DOMAIN="${CASA_DOWNLOAD_DOMAIN%/}"
        # ${sudo_cmd} sed -i.bak "s#https://github.com/IceWhaleTech/_appstore/#${CASA_DOWNLOAD_DOMAIN}/IceWhaleTech/_appstore/#g" "${APP_CONF_FILE}" ||
        #     Show 3 "Warning: Failed to update app store configuration"

        # 确保 CASA_DOWNLOAD_DOMAIN 格式正确
        CASA_DOWNLOAD_DOMAIN="${CASA_DOWNLOAD_DOMAIN%/}"  # 移除末尾的斜杠
        ESCAPED_DOMAIN=$(printf '%s\n' "${CASA_DOWNLOAD_DOMAIN}" | sed 's/[\/&]/\\&/g')

        # 先尝试替换 GitHub 的 URL
        ${sudo_cmd} sed -i.bak "s#https\?://[^/]\+/IceWhaleTech/_appstore/#${ESCAPED_DOMAIN}/IceWhaleTech/_appstore/#g" "${APP_CONF_FILE}" || 
            Show 3 "Warning: Failed to update app store configuration"

        # 再确保路径格式正确（处理可能缺少斜杠的情况）
        ${sudo_cmd} sed -i "s#${ESCAPED_DOMAIN}/\+IceWhaleTech/_appstore/#${ESCAPED_DOMAIN}/IceWhaleTech/_appstore/#g" "${APP_CONF_FILE}" 2>/dev/null
 
    fi

    # 下载卸载脚本
    UNINSTALL_TEMP="${PREFIX}/tmp/casaos-uninstall.$$"
    UNINSTALL_DIR=$(dirname "${CASA_UNINSTALL_PATH}")
    ${sudo_cmd} mkdir -p "$(dirname "${UNINSTALL_TEMP}")" "${UNINSTALL_DIR}" ||
        Show 3 "Warning: Failed to create temp directory"

    if ! ${sudo_cmd} curl -fsSLk "${CASA_UNINSTALL_URL}" -o "${UNINSTALL_TEMP}"; then
        Show 3 "Warning: Failed to download uninstall script"
    else
        ${sudo_cmd} chmod +x "${UNINSTALL_TEMP}" &&
        ${sudo_cmd} mv -f "${UNINSTALL_TEMP}" "${CASA_UNINSTALL_PATH}" ||
            Show 3 "Warning: Failed to install uninstall script"
    fi

    # 安装 Rclone
    Install_Rclone || Show 3 "Warning: Failed to install Rclone"

    # 启动服务
    for SERVICE in "${CASA_SERVICES[@]}"; do
        Show 2 "Starting ${SERVICE}..."
        if ! ${sudo_cmd} systemctl start "${SERVICE}"; then
            Show 3 "Warning: Failed to start service ${SERVICE}"
        fi
    done

    return 0
}

Clean_Temp_Files() {
    Show 2 "Clean temporary files..."
    ${sudo_cmd} rm -rf "${TMP_DIR}" || Show 1 "Failed to clean temporary files"
}

Check_Service_status() {
    for SERVICE in "${CASA_SERVICES[@]}"; do
        Show 2 "Checking ${SERVICE}..."
        if [[ $(${sudo_cmd} systemctl is-active "${SERVICE}") == "active" ]]; then
            Show 0 "${SERVICE} is running."
        else
            Show 1 "${SERVICE} is not running, Please reinstall."
            exit 1
        fi
    done
}

# Get the physical NIC IP
Get_IPs() {
    PORT=$(${sudo_cmd} cat ${CASA_CONF_PATH} | grep port | sed 's/port=//')
    ALL_NIC=$($sudo_cmd ls /sys/class/net/ | grep -v "$(ls /sys/devices/virtual/net/)")
    for NIC in ${ALL_NIC}; do
        IP=$($sudo_cmd ifconfig "${NIC}" | grep inet | grep -v 127.0.0.1 | grep -v inet6 | awk '{print $2}' | sed -e 's/addr://g')
        if [[ -n $IP ]]; then
            if [[ "$PORT" -eq "80" ]]; then
                echo -e "${GREEN_BULLET} http://$IP (${NIC})"
            else
                echo -e "${GREEN_BULLET} http://$IP:$PORT (${NIC})"
            fi
        fi
    done
}

# Show Welcome Banner
Welcome_Banner() {
    CASA_TAG=$(casaos -v)

    echo -e "${GREEN_LINE}${aCOLOUR[1]}"
    echo -e " CasaOS ${CASA_TAG}${COLOUR_RESET} is running at${COLOUR_RESET}${GREEN_SEPARATOR}"
    echo -e "${GREEN_LINE}"
    Get_IPs
    echo -e " Open your browser and visit the above address."
    echo -e "${GREEN_LINE}"
    echo -e ""
    echo -e " ${aCOLOUR[2]}CasaOS Project  : https://github.com/IceWhaleTech/CasaOS"
    echo -e " ${aCOLOUR[2]}CasaOS Team     : https://github.com/IceWhaleTech/CasaOS#maintainers"
    echo -e " ${aCOLOUR[2]}CasaOS Discord  : https://discord.gg/knqAbbBbeX"
    echo -e " ${aCOLOUR[2]}Website         : https://www.casaos.io"
    echo -e " ${aCOLOUR[2]}Online Demo     : http://demo.casaos.io"
    echo -e ""
    echo -e " ${COLOUR_RESET}${aCOLOUR[1]}Uninstall       ${COLOUR_RESET}: casaos-uninstall"
    echo -e "${COLOUR_RESET}"
}

###############################################################################
# Main                                                                        #
###############################################################################

#Usage
usage() {
    cat <<-EOF
		Usage: install.sh [options]
		Valid options are:
		    -p <build_dir>          Specify build directory (Local install)
		    -h                      Show this help message and exit
	EOF
    exit "$1"
}

while getopts ":p:h" arg; do
    case "$arg" in
    p)
        BUILD_DIR=$OPTARG
        ;;
    h)
        usage 0
        ;;
    *)
        usage 1
        ;;
    esac
done


# Install bc for floating-point arithmetic
if ! command -v bc &> /dev/null; then
    echo "📦 Installing bc (for calculations)..."
    sudo apt update && sudo apt install -y bc || true
fi



# Execute selection
# Step 0: Get Download URL Domain
Get_Download_Url_Domain

# # Output final result (can be used in subsequent scripts)
# echo "========================================"
# echo "🎉 Final download domain: $CASA_DOWNLOAD_DOMAIN"
# exit 

# #  https://github.com/IceWhaleTech/CasaOS-CLI/releases/download/v0.4.4-3-alpha1/linux-amd64-casaos-cli-v0.4.4-3-alpha1.tar.gz
# echo "wget -c https://github.com/IceWhaleTech/CasaOS-CLI/releases/download/v0.4.4-3-alpha1/linux-amd64-casaos-cli-v0.4.4-3-alpha1.tar.gz"

# rm -f linux-amd64-casaos-cli-v0.4.4-3-alpha1.tar.gz
# wget -c https://github.com/IceWhaleTech/CasaOS-CLI/releases/download/v0.4.4-3-alpha1/linux-amd64-casaos-cli-v0.4.4-3-alpha1.tar.gz
# rm -f linux-amd64-casaos-cli-v0.4.4-3-alpha1.tar.gz

# ping -c 5 github.com
# ping -c 5 ghproxy.link
# ping -c 5 casaos.oss-cn-shanghai.aliyuncs.com
# exit 

# Step 1: Check ARCH
Check_Arch

# Step 2: Check OS
Check_OS

# Step 3: Check Distribution
Check_Distribution

# Step 4: Check System Required
Check_Memory
Check_Disk

# Step 5: Install Depends
Update_Package_Resource
Install_Depends
Check_Dependency_Installation

# Step 6: Check And Install Docker
Check_Docker_Install


# Step 7: Configuration Addon
Configuration_Addons

# Step 8: Download And Install CasaOS
DownloadAndInstallCasaOS

# Step 9: Check Service Status
Check_Service_status

# Step 10: Clear Term and Show Welcome Banner
Welcome_Banner