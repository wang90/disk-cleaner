#!/bin/bash
# ============================================================================
#  diskautoclean.sh — macOS 自动磁盘清理工具
#
#  目标：在后台运行时，尽量保证系统至少保留 N GB（默认 10GB）可用空间。
#  做法：分 3 个安全等级，按“最安全 → 稍激进”的顺序清理，
#        一旦可用空间达到目标值就立刻停止，绝不“过度清理”。
#
#  只清理：应用缓存、开发工具缓存、日志、崩溃报告等可自动重建的内容。
#  默认不碰：个人文档、照片、代码、Xcode 归档、iOS 备份、废纸篓。
#
#  兼容 macOS 自带 bash 3.2，无需安装任何依赖（只用系统自带命令）。
# ============================================================================

set -u

VERSION="1.0.0-beta.2"

# ------------------------------ 默认参数 -----------------------------------
TARGET_FREE_KB=$((10 * 1000 * 1000 * 1000 / 1024))   # 目标：10 GB（十进制，跟 macOS 一致）
MAX_TIER=2                             # 默认清理到第 2 级
DRY_RUN=0
FORCE=0
QUIET=0
USER_DATA=0                            # 是否允许清理用户数据（第 3 级里的备份/下载）
PURGE_MEM=0                            # 是否顺带清理内存（purge）
ALLOW_ROOT=0
MODE=""                                # scan / status / 空=清理
JSON=0                                 # 输出 JSON（给 GUI 用）
MACHINE="${DISKAUTOCLEAN_MACHINE:-0}"  # 输出 @@ 机器可读进度行
KB_TIMEOUT="${DISKAUTOCLEAN_KB_TIMEOUT:-40}"  # 单个路径 du 的硬超时（秒）
APP_TIMEOUT="${DISKAUTOCLEAN_APP_TIMEOUT:-12}" # 扫描单个 .app 的硬超时（秒）
LOG_FILE="${DISKAUTOCLEAN_LOG:-$HOME/Library/Logs/diskautoclean.log}"
LOCK_DIR="${TMPDIR:-/tmp}/diskautoclean.lock"

# ------------------------------ 统计变量 -----------------------------------
FREED_KB=0
DELETED_COUNT=0
REACHED=0
KB_TIMEOUT_HIT=0
KB_LAST_KB=0          # kb_of 的结果（用全局变量回传，避免子 shell 丢失状态）
KB_STATUS="ok"        # kb_of 的结果状态: ok / timeout / fail

# ------------------------------ 基础函数 -----------------------------------

human() {
  awk -v k="${1:-0}" 'BEGIN {
    b = k * 1024;                      # KB -> 字节
    if (b >= 1e12)      printf "%.2f TB", b/1e12;
    else if (b >= 1e9)  printf "%.1f GB", b/1e9;
    else if (b >= 1e6)  printf "%.0f MB", b/1e6;
    else                printf "%.0f KB", b/1000;
  }'
}

ts() { date '+%Y-%m-%d %H:%M:%S'; }

log() {
  if [ -n "${LOG_FILE:-}" ]; then
    { printf '%s %s\n' "$(ts)" "$*" >>"$LOG_FILE"; } 2>/dev/null
  fi
  [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"
}

# 确保日志文件可写；不可写则退回临时目录
setup_log() {
  local d
  d=$(dirname "$LOG_FILE")
  [ -d "$d" ] || mkdir -p "$d" 2>/dev/null
  if ! { : >>"$LOG_FILE"; } 2>/dev/null; then
    LOG_FILE="${TMPDIR%/}/diskautoclean.log"
    warn "默认日志目录不可写，已改用: $LOG_FILE"
  fi
}

warn() { printf '警告: %s\n' "$*" >&2; }

# --- 给 GUI 用的机器可读输出（以 @@ 开头，单独一行）---
emit_freed() { if [ "$MACHINE" -eq 1 ]; then printf '@@FREED\t%s\t%s\n' "$1" "$2"; fi; return 0; }
emit_tier()  { if [ "$MACHINE" -eq 1 ]; then printf '@@TIER\t%s\n' "$1"; fi; return 0; }
emit_kv()    { if [ "$MACHINE" -eq 1 ]; then printf '@@%s\t%s\n' "$1" "$2"; fi; return 0; }

json_escape() {
  printf '%s' "$1" | tr -d '\000-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# 取路径占用大小（KB），任何失败都返回 0（保证是数字，便于运算与排序）
#
# 重要：某些目录（例如 Cache 里残留的 socket、失效的网络卷、需要 TCC 授权的
# 目录）会让 du 立刻失败或长时间阻塞。这里给每条路径加一个硬超时，超时就杀掉
# du 并返回 0；同时用全局 KB_STATUS 告诉调用方到底是 ok / timeout / fail。
kb_of() {
  local path="$1" tmpf pid n limit v rc
  KB_STATUS="ok"
  KB_LAST_KB=0
  KB_TIMEOUT_HIT=0
  tmpf="${TMPDIR%/}/diskautoclean.kb.$$"
  if ! : >"$tmpf" 2>/dev/null; then
    KB_STATUS="fail"
    return 0
  fi

  du -sk "$path" >"$tmpf" 2>/dev/null &
  pid=$!

  limit=$((KB_TIMEOUT * 10))
  n=0
  while kill -0 "$pid" 2>/dev/null; do
    n=$((n + 1))
    if [ "$n" -ge "$limit" ]; then
      kill -9 "$pid" 2>/dev/null
      KB_TIMEOUT_HIT=1
      break
    fi
    sleep 0.1
  done
  wait "$pid" 2>/dev/null
  rc=$?

  v=$(awk 'NR==1 { printf "%d", $1+0 }' "$tmpf" 2>/dev/null)
  rm -f "$tmpf" 2>/dev/null

  if [ "$KB_TIMEOUT_HIT" -eq 1 ]; then
    KB_STATUS="timeout"
  elif [ "$rc" -ne 0 ] || [ -z "${v:-}" ]; then
    KB_STATUS="fail"
  fi

  [ -n "${v:-}" ] || v=0
  KB_LAST_KB="$v"
  return 0
}

# 取包含 $1 的卷的可用空间（KB），失败返回 0
free_kb() {
  local v
  v=$(df -Pk "$1" 2>/dev/null | awk 'NR==2 { printf "%d", $4+0; exit }')
  [ -n "${v:-}" ] || v=0
  printf '%s' "$v"
}

# 把 10G / 10GB / 10240M 之类解析为 KB
parse_size() {
  local raw norm num unit mult
  raw="$1"
  norm=$(printf '%s' "$raw" | tr '[:lower:]' '[:upper:]' | tr -d ' ')
  num=$(printf '%s' "$norm" | sed 's/[^0-9.]//g')
  unit=$(printf '%s' "$norm" | sed 's/[0-9.]//g')
  # 采用 macOS/Finder 的十进制单位（1 GB = 1000^3 字节），结果换算成 KB
  case "$unit" in
    ""|K|KB|KIB)   mult=1000 ;;
    M|MB|MIB)      mult=1000000 ;;
    G|GB|GIB)      mult=1000000000 ;;
    T|TB|TIB)      mult=1000000000000 ;;
    *) warn "无法识别的空间大小: $raw"; return 1 ;;
  esac
  case "$num" in ""|*[!0-9.]*) warn "无法识别的空间大小: $raw"; return 1 ;; esac
  awk -v n="$num" -v m="$mult" 'BEGIN { printf "%d", n * m / 1024 }'
}

# 绝不能删除的路径（即使参数写错也不会碰）
is_protected() {
  local p="$1"
  case "$p" in
    "/"|/System|/System/*|/Library|/Library/*|/Applications|/Applications/*) return 0 ;;
    /usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/opt|/opt/*) return 0 ;;
    /private|/private/*|/etc|/etc/*|/var|/var/*|/Volumes|/Volumes/*) return 0 ;;
  esac
  [ "$p" = "$HOME" ] && return 0
  case "$p" in
    "$HOME"/Documents|"$HOME"/Documents/*|"$HOME"/Desktop|"$HOME"/Desktop/*) return 0 ;;
    "$HOME"/Pictures|"$HOME"/Pictures/*|"$HOME"/Movies|"$HOME"/Movies/*) return 0 ;;
    "$HOME"/Music|"$HOME"/Music/*|"$HOME"/Library|"$HOME"/.ssh|"$HOME"/.ssh/*) return 0 ;;
    "$HOME"/.gnupg|"$HOME"/.gnupg/*|"$HOME"/Library/Keychains*) return 0 ;;
  esac
  return 1
}

# 是否已达到目标空间而应该停止
should_stop() {
  [ "$FORCE" -eq 1 ] && return 1
  [ "$REACHED" -eq 1 ] && return 0
  local f
  f=$(free_kb "$HOME")
  if [ "${f:-0}" -ge "$TARGET_FREE_KB" ]; then
    REACHED=1
    return 0
  fi
  return 1
}

# 删除单个条目（受保护路径会跳过；dry-run 只打印）
remove_item() {
  local p="$1" sz
  if is_protected "$p"; then
    log "  [跳过] 受保护路径: $p"
    return 0
  fi
  kb_of "$p"; sz=$KB_LAST_KB
  if [ "$DRY_RUN" -eq 1 ]; then
    log "  [演练] 将删除 $p  ($(human "$sz"))"
  else
    if rm -rf -- "$p" 2>/dev/null; then
      log "  [已删] $p  ($(human "$sz"))"
    else
      log "  [失败] 无法删除 $p（可能权限不足）"
      return 0
    fi
  fi
  FREED_KB=$((FREED_KB + sz))
  DELETED_COUNT=$((DELETED_COUNT + 1))
  emit_freed "$sz" "$p"
}

# ----------------------------------------------------------------------------
# process_dir <目录> <保留天数> <说明>
#   删除目录下“超过保留天数”的第一层条目（兼容 bash 3.2，路径含空格安全）
# ----------------------------------------------------------------------------
process_dir() {
  local dir="$1" age="$2" label="$3" found=0 before
  [ -d "$dir" ] || return 0
  case "$dir/" in
    "$HOME"/*) : ;;
    *) log "  [跳过] 不在主目录内: $dir"; return 0 ;;
  esac
  kb_of "$dir"; before=$KB_LAST_KB
  [ "${before:-0}" -le 0 ] && return 0
  log "▶ $label — $(human "$before")"

  if [ "$age" -gt 0 ]; then
    while IFS= read -r -d '' item; do
      remove_item "$item"
      found=1
      should_stop && break
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -mtime +"$age" -print0 2>/dev/null)
  else
    while IFS= read -r -d '' item; do
      remove_item "$item"
      found=1
      should_stop && break
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
  fi

  [ "$found" -eq 0 ] && log "  （没有符合“超过 ${age} 天”的条目）"
  return 0
}

# ----------------------------------------------------------------------------
# truncate_big_logs <目录> <阈值MB> <说明>
#   把超大日志文件内容清空（而不是删除），避免影响正在写日志的进程
# ----------------------------------------------------------------------------
truncate_big_logs() {
  local dir="$1" mb="$2" label="$3" f sz
  [ -d "$dir" ] || return 0
  while IFS= read -r -d '' f; do
    kb_of "$f"; sz=$KB_LAST_KB
    [ "${sz:-0}" -lt $((mb * 1024)) ] && continue
    if [ "$DRY_RUN" -eq 1 ]; then
      log "  [演练] 将清空日志 $f  ($(human "$sz"))"
    else
      if : >"$f" 2>/dev/null; then
        log "  [已清空] 日志 $f  ($(human "$sz"))"
      else
        log "  [失败] 无法清空 $f"
        continue
      fi
    fi
    FREED_KB=$((FREED_KB + sz))
    DELETED_COUNT=$((DELETED_COUNT + 1))
    emit_freed "$sz" "$f"
  done < <(find "$dir" -type f \( -name '*.log' -o -name '*.log.*' -o -name '*.out' \) \
             -size +"${mb}"M -print0 2>/dev/null)
  return 0
}

# 只报告、不删除（用于第 3 级里的用户数据）
report_dir() {
  local dir="$1" label="$2" sz
  [ -e "$dir" ] || return 0
  kb_of "$dir"; sz=$KB_LAST_KB
  [ "${sz:-0}" -le 0 ] && return 0
  log "ℹ $label — $(human "$sz")（仅报告，未删除；如要清理请加 --user-data）"
}

# ----------------------------------------------------------------------------
# 第 1 级：安全清理（应用缓存 / 日志 / 崩溃报告）
# ----------------------------------------------------------------------------
tier1() {
  emit_tier 1
  log ""
  log "===== 第 1 级：安全缓存与日志 ====="
  process_dir "$HOME/Library/Caches"                      14 "应用缓存（超过 14 天）"
  process_dir "$HOME/.cache"                              14 "开发工具缓存 ~/.cache（超过 14 天）"
  process_dir "$HOME/Library/Developer/Xcode/DerivedData"  0 "Xcode 编译缓存 DerivedData"
  process_dir "$HOME/Library/Developer/CoreSimulator/Caches" 0 "iOS 模拟器缓存"
  process_dir "$HOME/Library/Logs/DiagnosticReports"       7 "崩溃报告（超过 7 天）"
  truncate_big_logs "$HOME/Library/Logs"                  200 "清空超大日志（>200MB）"
  process_dir "$HOME/Library/Logs"                        14 "旧日志（超过 14 天）"
}

# ----------------------------------------------------------------------------
# 第 2 级：开发工具缓存（可重新下载/重建）
# ----------------------------------------------------------------------------
tier2() {
  emit_tier 2
  log ""
  log "===== 第 2 级：开发工具缓存 ====="
  process_dir "$HOME/.npm/_cacache"                30 "npm 缓存（>30 天）"
  process_dir "$HOME/.npm/_npx"                    30 "npx 缓存（>30 天）"
  process_dir "$HOME/.pnpm-store"                  30 "pnpm 存储（>30 天）"
  process_dir "$HOME/Library/pnpm/store"           30 "pnpm 存储 (Library)（>30 天）"
  process_dir "$HOME/Library/Caches/pnpm"          30 "pnpm 缓存（>30 天）"
  process_dir "$HOME/Library/Caches/pip"           14 "pip 缓存（>14 天）"
  process_dir "$HOME/Library/Caches/Homebrew"       0 "Homebrew 下载缓存"
  process_dir "$HOME/Library/Caches/go-build"      14 "Go 编译缓存（>14 天）"
  process_dir "$HOME/Library/Caches/typescript"    30 "TypeScript 缓存（>30 天）"
  process_dir "$HOME/Library/Caches/Yarn"          30 "Yarn 缓存（>30 天）"
  process_dir "$HOME/Library/Caches/npm"           30 "npm 缓存（>30 天）"
  process_dir "$HOME/Library/Caches/uv"            30 "uv 缓存（>30 天）"
  process_dir "$HOME/Library/Caches/Electron"      30 "Electron 缓存（>30 天）"
  process_dir "$HOME/Library/Caches/electron"      30 "electron 缓存（>30 天）"
  process_dir "$HOME/Library/Caches/ms-playwright" 60 "Playwright 浏览器（>60 天）"
  process_dir "$HOME/.cargo/registry/cache"        30 "Cargo 缓存（>30 天）"
  process_dir "$HOME/.gradle/caches"               30 "Gradle 缓存（>30 天）"
  process_dir "$HOME/.gradle/wrapper/dists"        30 "Gradle 发行包（>30 天）"
  process_dir "$HOME/Library/Developer/Xcode/iOS DeviceSupport"     90 "旧 iOS 设备支持文件（>90 天）"
  process_dir "$HOME/Library/Developer/Xcode/watchOS DeviceSupport" 90 "旧 watchOS 设备支持文件（>90 天）"
  process_dir "$HOME/Library/Developer/Xcode/tvOS DeviceSupport"    90 "旧 tvOS 设备支持文件（>90 天）"
}

# ----------------------------------------------------------------------------
# 第 3 级：用户数据（默认只报告；加 --user-data 才会删除）
# ----------------------------------------------------------------------------
tier3() {
  emit_tier 3
  log ""
  log "===== 第 3 级：用户数据（需显式允许）====="
  report_dir "$HOME/Library/Developer/Xcode/Archives"              "Xcode 归档 .xcarchive"
  report_dir "$HOME/Library/Application Support/MobileSync/Backup" "iPhone/iPad 本机备份"
  report_dir "$HOME/Library/Application Support/iPhone Simulator"  "旧 iPhone 模拟器数据"
  report_dir "$HOME/Downloads"                                    "下载文件夹"
  report_dir "$HOME/.Trash"                                       "废纸篓"

  if [ "$USER_DATA" -eq 1 ]; then
    log "（--user-data 已开启，将清理第 3 级内容）"
    process_dir "$HOME/Library/Developer/Xcode/Archives"              90 "Xcode 归档（>90 天）"
    process_dir "$HOME/Library/Application Support/MobileSync/Backup"  0 "iOS 本机备份"
    process_dir "$HOME/Downloads"                                    90 "下载文件夹（>90 天）"
  fi
}

# ----------------------------------------------------------------------------
# 可选：清理内存（不是磁盘）
# ----------------------------------------------------------------------------
purge_memory() {
  log ""
  log "===== 清理内存（可选）====="
  if ! command -v purge >/dev/null 2>&1; then
    log "未找到 purge 命令，跳过"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "  [演练] 将执行 purge 释放非活跃内存"
    return 0
  fi
  if purge 2>/dev/null; then
    log "  purge 执行完成，已释放非活跃内存"
  else
    log "  purge 需要管理员权限，已跳过（可手动执行: sudo purge）"
  fi
}

# ----------------------------------------------------------------------------
# --scan：只显示各清理项的当前占用，不删除任何东西
# ----------------------------------------------------------------------------
scan_list() {
  # 格式: 等级|路径|名称   （尽量互不重叠，避免重复计算）
  printf '%s\n' \
    "1|$HOME/Library/Caches|应用缓存" \
    "1|$HOME/.cache|开发工具缓存" \
    "1|$HOME/Library/Logs|日志" \
    "1|$HOME/Library/Developer/Xcode/DerivedData|Xcode 编译缓存" \
    "1|$HOME/Library/Developer/CoreSimulator/Caches|模拟器缓存" \
    "2|$HOME/.npm/_cacache|npm 缓存" \
    "2|$HOME/.pnpm-store|pnpm 存储" \
    "2|$HOME/.gradle/caches|Gradle 缓存" \
    "2|$HOME/.cargo/registry/cache|Cargo 缓存" \
    "2|$HOME/Library/Developer/Xcode/iOS DeviceSupport|iOS 设备支持文件" \
    "3|$HOME/Library/Developer/Xcode/Archives|Xcode 归档" \
    "3|$HOME/Library/Application Support/MobileSync/Backup|iOS 本机备份" \
    "3|$HOME/.Trash|废纸篓" \
    "3|$HOME/Downloads|下载文件夹"
}

do_scan() {
  local tmp sz tier label path entry rest total=0 st="ok"
  tmp=$(mktemp "${TMPDIR%/}/diskautoclean.scan.XXXXXX" 2>/dev/null) || tmp=""
  [ -n "$tmp" ] || { warn "无法创建临时文件"; return 1; }

  while IFS= read -r entry; do
    tier="${entry%%|*}"; rest="${entry#*|}"; path="${rest%%|*}"; label="${rest#*|}"
    sz=0
    st="ok"
    if [ -e "$path" ]; then
      kb_of "$path"
      sz=$KB_LAST_KB
      st=$KB_STATUS
    fi
    total=$((total + sz))
    printf '%s\t%s\t%s\t%s\t%s\n' "$sz" "$tier" "$label" "$path" "$st" >>"$tmp"
  done <<EOF2
$(scan_list)
EOF2

  if [ "$JSON" -eq 1 ]; then
    local out="" first=1
    while IFS="$(printf '\t')" read -r sz tier label path st; do
      [ -n "${sz:-}" ] || continue
      [ "$first" -eq 1 ] || out="$out,"
      first=0
      out="$out{\"label\":\"$(json_escape "$label")\",\"path\":\"$(json_escape "$path")\",\"tier\":$tier,\"kb\":$sz,\"status\":\"${st:-ok}\"}"
    done < <(sort -nr "$tmp")
    rm -f "$tmp"
    printf '{"free_kb":%s,"target_kb":%s,"total_kb":%s,"items":[%s]}\n' \
      "$(free_kb "$HOME")" "$TARGET_FREE_KB" "$total" "$out"
    return 0
  fi

  printf '%-4s %-34s %10s\n' "等级" "清理目标" "占用"
  printf '%s\n' "----------------------------------------------------------------"
  while IFS="$(printf '\t')" read -r sz tier label path st; do
    [ -n "${sz:-}" ] || continue
    case "${st:-ok}" in
      timeout) printf '%-4s %-34s %10s\n' "L$tier" "$label" "读取超时" ;;
      fail)    printf '%-4s %-34s %10s\n' "L$tier" "$label" "读取失败" ;;
      *)       printf '%-4s %-34s %10s\n' "L$tier" "$label" "$(human "$sz")" ;;
    esac
  done < <(sort -nr "$tmp")
  printf '%s\n' "----------------------------------------------------------------"
  printf '%-4s %-34s %10s\n' "" "合计" "$(human "$total")"
  printf '\n当前可用空间: %s\n' "$(human "$(free_kb "$HOME")")"
  printf '提示: 出现“读取超时/读取失败”通常是因为该目录受系统保护，\n'
  printf '      请在 系统设置 → 隐私与安全性 → 完全磁盘访问权限 中授权后重试。\n'
  rm -f "$tmp"
}

# ----------------------------------------------------------------------------
# 磁盘概况 → 输出 "总量KB 已用KB 可用KB"
# ----------------------------------------------------------------------------
disk_kb() {
  local line
  line=$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 { printf "%d %d %d", $2+0, $3+0, $4+0; exit }')
  [ -n "$line" ] || line="0 0 0"
  printf '%s' "$line"
}

# ----------------------------------------------------------------------------
# 内存概况 → 输出 "总量 可用 活跃 联动 压缩 swap总 swap已用"（单位 KB）
#   可用 = free + inactive（近似“还能拿来用的”）
# ----------------------------------------------------------------------------
mem_kb() {
  local total vs ps f i a w c swap st su
  total=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
  total=$((total / 1024))

  st=0; su=0
  swap=$(sysctl -n vm.swapusage 2>/dev/null)
  if [ -n "${swap:-}" ]; then
    st=$(printf '%s\n' "$swap" | awk '{ for (n = 1; n <= NF; n++) if ($n == "total") { print $(n+2); exit } }')
    su=$(printf '%s\n' "$swap" | awk '{ for (n = 1; n <= NF; n++) if ($n == "used")  { print $(n+2); exit } }')
    st=$(swap_to_kb "$st"); su=$(swap_to_kb "$su")
  fi

  if ! command -v vm_stat >/dev/null 2>&1; then
    printf '%s 0 0 0 0 %s %s' "$total" "${st:-0}" "${su:-0}"
    return 0
  fi
  vs=$(vm_stat 2>/dev/null) || { printf '%s 0 0 0 0 %s %s' "$total" "${st:-0}" "${su:-0}"; return 0; }

  ps=$(printf '%s\n' "$vs" | awk '/page size of/ { print $(NF-1); exit }')
  [ -n "${ps:-}" ] || ps=4096
  f=$(printf '%s\n' "$vs" | awk -F: '/Pages free/                     { gsub(/[^0-9]/,"",$2); print $2+0; exit }')
  i=$(printf '%s\n' "$vs" | awk -F: '/Pages inactive/                 { gsub(/[^0-9]/,"",$2); print $2+0; exit }')
  a=$(printf '%s\n' "$vs" | awk -F: '/Pages active/                   { gsub(/[^0-9]/,"",$2); print $2+0; exit }')
  w=$(printf '%s\n' "$vs" | awk -F: '/Pages wired down/               { gsub(/[^0-9]/,"",$2); print $2+0; exit }')
  c=$(printf '%s\n' "$vs" | awk -F: '/Pages occupied by compressor/   { gsub(/[^0-9]/,"",$2); print $2+0; exit }')

  awk -v t="${total:-0}" -v p="$ps" -v f="${f:-0}" -v i="${i:-0}" -v a="${a:-0}" \
      -v w="${w:-0}" -v c="${c:-0}" -v st="${st:-0}" -v su="${su:-0}" 'BEGIN {
    printf "%d %d %d %d %d %d %d", t, (f+i)*p/1024, a*p/1024, w*p/1024, c*p/1024, st, su;
  }'
}

# 把 sysctl vm.swapusage 里的 "2048.00M" / "1.50G" 转成 KB
swap_to_kb() {
  local v="${1:-}"
  [ -n "$v" ] || { printf '0'; return 0; }
  case "$v" in
    *G|*g) v="${v%[Gg]}"; awk -v x="$v" 'BEGIN { printf "%d", x*1048576 }' ;;
    *M|*m) v="${v%[Mm]}"; awk -v x="$v" 'BEGIN { printf "%d", x*1024 }' ;;
    *K|*k) v="${v%[Kk]}"; awk -v x="$v" 'BEGIN { printf "%d", x }' ;;
    *)     awk -v x="$v" 'BEGIN { printf "%d", x }' ;;
  esac
}

mem_line() {
  mem_kb | awk '{ t=$1; a=$2; c=$5; st=$6; su=$7;
    up = (t > 0) ? (t - a) * 100 / t : 0;
    printf "内存: 已用 %.1f GB / 共 %.1f GB (%.0f%%) | 可回收 %.1f GB | 压缩 %.1f GB | Swap %.1f/%.1f GB\n",
           (t-a)/1048576, t/1048576, up, a/1048576, c/1048576, su/1048576, st/1048576;
  }'
}

# ----------------------------------------------------------------------------
# 卷列表（每个“硬盘”）→ JSON 数组
#   boot 卷取 APFS 容器容量（macOS 里 Macintosh HD 显示的就是容器容量）
# ----------------------------------------------------------------------------
volumes_json() {
  local out="" name line tot u av v

  name=$(diskutil info / 2>/dev/null | awk -F: '/Volume Name/ { sub(/^[ \t]+/, "", $2); print $2; exit }')
  [ -n "$name" ] || name="Macintosh HD"
  line=$(df -Pk /System/Volumes/Data 2>/dev/null | awk 'NR==2 { print ($2+0)" "($3+0)" "($4+0) }')
  [ -n "$line" ] || line="0 0 0"
  set -- $line; tot=${1:-0}; u=${2:-0}; av=${3:-0}
  out="{\"name\":\"$(json_escape "$name")\",\"mount\":\"/System/Volumes/Data\",\"total_kb\":$tot,\"used_kb\":$u,\"avail_kb\":$av,\"boot\":true}"

  if [ -d /Volumes ]; then
    for v in /Volumes/*; do
      [ -d "$v" ] || continue
      [ -L "$v" ] && continue
      name=$(basename "$v")
      case "$name" in Recovery|"$name".*) continue ;; esac
      line=$(df -Pk "$v" 2>/dev/null | awk 'NR==2 { print ($2+0)" "($3+0)" "($4+0) }')
      [ -n "$line" ] || continue
      set -- $line; tot=${1:-0}; u=${2:-0}; av=${3:-0}
      [ "$tot" -gt 0 ] || continue
      out="$out,{\"name\":\"$(json_escape "$name")\",\"mount\":\"$(json_escape "$v")\",\"total_kb\":$tot,\"used_kb\":$u,\"avail_kb\":$av,\"boot\":false}"
    done
  fi

  printf '[%s]' "$out"
}

# ----------------------------------------------------------------------------
# --status：状态（支持 --json）
# ----------------------------------------------------------------------------
do_status() {
  local f pct d dt du_ m mt ma mact mwire mcomp st stt stu
  f=$(free_kb "$HOME")
  d=$(disk_kb)
  dt=$(printf '%s' "$d" | awk '{print $1+0}')
  # APFS 共享容器：已用 = 总容量 − 可用（与 macOS 显示一致）
  du_=$(printf '%s' "$d" | awk '{print $1+0 - $3+0}')
  m=$(mem_kb)
  mt=$(printf '%s' "$m" | awk '{print $1}')
  ma=$(printf '%s' "$m" | awk '{print $2}')
  mact=$(printf '%s' "$m" | awk '{print $3}')
  mwire=$(printf '%s' "$m" | awk '{print $4}')
  mcomp=$(printf '%s' "$m" | awk '{print $5}')
  stt=$(printf '%s' "$m" | awk '{print $6}')
  stu=$(printf '%s' "$m" | awk '{print $7}')

  if [ "$JSON" -eq 1 ]; then
    printf '{"free_kb":%s,"target_kb":%s,"disk_total_kb":%s,"disk_used_kb":%s,"disk_avail_kb":%s,"mem_total_kb":%s,"mem_avail_kb":%s,"mem_active_kb":%s,"mem_wired_kb":%s,"mem_compressed_kb":%s,"swap_total_kb":%s,"swap_used_kb":%s,"volumes":%s}\n' \
      "$f" "$TARGET_FREE_KB" "${dt:-0}" "${du_:-0}" "$f" \
      "${mt:-0}" "${ma:-0}" "${mact:-0}" "${mwire:-0}" "${mcomp:-0}" "${stt:-0}" "${stu:-0}" \
      "$(volumes_json)"
    return 0
  fi

  pct=$(awk -v a="$f" -v t="$TARGET_FREE_KB" 'BEGIN { printf "%.1f", (t>0? a*100/t : 100) }')
  printf '磁盘: 可用 %s | 目标 %s | 达成度 %s%% | %s\n' \
    "$(human "$f")" "$(human "$TARGET_FREE_KB")" "$pct" \
    "$([ "${f:-0}" -ge "$TARGET_FREE_KB" ] && echo '空间充足' || echo '需要清理')"
  awk -v t="${dt:-0}" -v u="${du_:-0}" 'BEGIN {
    # 磁盘按 macOS 惯例用十进制（1 GB = 1000^3 字节）
    printf "整盘: 已用 %.1f GB / 共 %.1f GB (%.0f%%)\n", u*1024/1e9, t*1024/1e9, (t>0? u*100/t : 0);
  }'
  mem_line
}

# ----------------------------------------------------------------------------
# --apps：列出各个应用占用（本体 + 数据），支持 --json
# ----------------------------------------------------------------------------
do_apps() {
  local tmp base app name bid app_kb data_kb d total=0 line saved_kt
  tmp=$(mktemp "${TMPDIR%/}/diskautoclean.apps.XXXXXX" 2>/dev/null) || tmp=""
  [ -n "$tmp" ] || { warn "无法创建临时文件"; return 1; }

  saved_kt="$KB_TIMEOUT"
  KB_TIMEOUT="$APP_TIMEOUT"

  for base in /Applications "$HOME/Applications" /System/Applications; do
    [ -d "$base" ] || continue
    while IFS= read -r -d '' app; do
      name=$(basename "$app" .app)
      kb_of "$app"; app_kb=$KB_LAST_KB
      [ "$app_kb" -le 0 ] && continue

      bid=""
      if [ -f "$app/Contents/Info.plist" ]; then
        bid=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null | head -1 | tr -d '\r')
      fi

      # 该应用在用户目录下的数据（沙盒容器 / 缓存 / 支持文件）
      data_kb=0
      if [ -n "$bid" ]; then
        for d in "$HOME/Library/Containers/$bid" \
                 "$HOME/Library/Caches/$bid" \
                 "$HOME/Library/Application Support/$bid"; do
          [ -d "$d" ] || continue
          kb_of "$d"
          data_kb=$((data_kb + KB_LAST_KB))
        done
      fi

      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$((app_kb + data_kb))" "$app_kb" "$data_kb" "$bid" "$name" "$app" >>"$tmp"
    done < <(find "$base" -maxdepth 1 -name '*.app' -print0 2>/dev/null)
  done

  KB_TIMEOUT="$saved_kt"

  if [ "$JSON" -eq 1 ]; then
    local out="" first=1
    while IFS="$(printf '\t')" read -r tot app_kb data_kb bid name path; do
      [ -n "${tot:-}" ] || continue
      total=$((total + tot))
      [ "$first" -eq 1 ] || out="$out,"
      first=0
      out="$out{\"name\":\"$(json_escape "$name")\",\"path\":\"$(json_escape "$path")\",\"bundle_id\":\"$(json_escape "$bid")\",\"app_kb\":$app_kb,\"data_kb\":$data_kb,\"total_kb\":$tot}"
    done < <(sort -nr "$tmp")
    rm -f "$tmp"
    printf '{"free_kb":%s,"disk_total_kb":%s,"apps":[%s]}\n' \
      "$(free_kb "$HOME")" "$(printf '%s' "$(disk_kb)" | awk '{print $1}')" "$out"
    return 0
  fi

  printf '%-28s %10s %10s %10s\n' "应用" "本体" "数据" "合计"
  printf '%s\n' "----------------------------------------------------------------"
  while IFS="$(printf '\t')" read -r tot app_kb data_kb bid name path; do
    [ -n "${tot:-}" ] || continue
    printf '%-28s %10s %10s %10s\n' "$name" "$(human "$app_kb")" "$(human "$data_kb")" "$(human "$tot")"
  done < <(sort -nr "$tmp" | head -40)
  printf '%s\n' "----------------------------------------------------------------"
  printf '说明: “本体”= .app 自身；“数据”= 该应用在 ~/Library 下的容器/缓存。\n'
  rm -f "$tmp"
}

# ----------------------------------------------------------------------------
# --storage：按 macOS「储存空间」的方式给出分类占用（本地近似统计）
# ----------------------------------------------------------------------------
do_storage() {
  local tmp line total used avail known=0 kb lbl key
  tmp=$(mktemp "${TMPDIR%/}/diskautoclean.storage.XXXXXX" 2>/dev/null) || tmp=""
  [ -n "$tmp" ] || { warn "无法创建临时文件"; return 1; }

  line=$(df -Pk /System/Volumes/Data 2>/dev/null | awk 'NR==2 { print ($2+0)" "($3+0)" "($4+0) }')
  [ -n "$line" ] || line="0 0 0"
  set -- $line; total=${1:-0}; avail=${3:-0}
  # APFS 是共享容器：已用要按 macOS 的口径算成 “总容量 − 可用”，
  # 这样 分类合计 + 可用 = 总容量，堆叠条才是满的。
  used=$((total - avail))
  [ "$used" -lt 0 ] && used=0

  # 一个分类 = 若干路径大小之和；同时记录是否因为权限读不全
  add_cat() {
    local k="$1" l="$2"; shift 2
    local s=0 x st="ok" any=0
    for x in "$@"; do
      [ -e "$x" ] || continue
      any=1
      kb_of "$x"
      s=$((s + KB_LAST_KB))
      [ "$KB_STATUS" = "ok" ] || st="partial"
    done
    [ "$any" -eq 0 ] && st="none"
    printf '%s\t%s\t%s\t%s\n' "$k" "$l" "$s" "$st" >>"$tmp"
  }

  add_cat apps    "应用程序"       /Applications /System/Applications "$HOME/Applications"
  add_cat docs    "文稿与桌面"     "$HOME/Documents" "$HOME/Desktop"
  add_cat down    "下载"           "$HOME/Downloads"
  add_cat photos  "照片"           "$HOME/Pictures"
  add_cat music   "音乐"           "$HOME/Music"
  add_cat movies  "影片"           "$HOME/Movies"
  add_cat mail    "邮件与信息"     "$HOME/Library/Mail" "$HOME/Library/Messages"
  add_cat dev     "开发者缓存"     "$HOME/Library/Developer" "$HOME/.npm" "$HOME/.pnpm-store" \
                                   "$HOME/.cache" "$HOME/.gradle" "$HOME/.cargo" "$HOME/Library/pnpm"
  add_cat appdata "应用数据"       "$HOME/Library/Containers" "$HOME/Library/Application Support" \
                                   "$HOME/Library/Group Containers"
  add_cat caches  "系统与应用缓存" "$HOME/Library/Caches"

  while IFS="$(printf '\t')" read -r key lbl kb st; do
    [ -n "${kb:-}" ] || continue
    known=$((known + kb))
  done <"$tmp"

  local other=$((used - known))
  [ "$other" -lt 0 ] && other=0
  printf '%s\t%s\t%s\t%s\n' "system" "系统数据与其它" "$other" "ok" >>"$tmp"

  if [ "$JSON" -eq 1 ]; then
    local out="" first=1
    while IFS="$(printf '\t')" read -r key lbl kb st; do
      [ -n "${kb:-}" ] || continue
      [ "$first" -eq 1 ] || out="$out,"
      first=0
      out="$out{\"key\":\"$(json_escape "$key")\",\"label\":\"$(json_escape "$lbl")\",\"kb\":$kb,\"status\":\"${st:-ok}\"}"
    done <"$tmp"
    out="$out,{\"key\":\"free\",\"label\":\"可用\",\"kb\":$avail,\"status\":\"ok\"}"
    rm -f "$tmp"
    printf '{"total_kb":%s,"used_kb":%s,"avail_kb":%s,"categories":[%s]}\n' \
      "$total" "$used" "$avail" "$out"
    return 0
  fi

  printf '%-20s %12s %8s\n' "分类" "占用" "占已用"
  printf '%s\n' "------------------------------------------------"
  while IFS="$(printf '\t')" read -r key lbl kb st; do
    [ -n "${kb:-}" ] || continue
    local mark=""
    [ "${st:-ok}" = "partial" ] && mark=" ⚠︎需授权"
    printf '%-20s %12s %7.1f%%%s\n' "$lbl" "$(human "$kb")" \
      "$(awk -v k="$kb" -v t="$used" 'BEGIN { if (t > 0) printf "%.1f", k*100/t; else printf "0.0" }')" "$mark"
  done <"$tmp"
  printf '%-20s %12s %7.1f%%\n' "可用" "$(human "$avail")" \
    "$(awk -v k="$avail" -v t="$total" 'BEGIN { if (t > 0) printf "%.1f", k*100/t; else printf "0.0" }')"
  printf '%s\n' "------------------------------------------------"
  printf '容器容量 %s（已用 %s）\n' "$(human "$total")" "$(human "$used")"
  printf '说明: “系统数据与其它”= 已用 − 上述各项（含系统卷、快照、其它用户等）。\n'
  rm -f "$tmp"
}

# ----------------------------------------------------------------------------
# 主流程
# ----------------------------------------------------------------------------
main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --target)
        [ $# -ge 2 ] || { warn "--target 缺少参数"; exit 2; }
        TARGET_FREE_KB=$(parse_size "$2") || exit 2; shift 2 ;;
      --target=*)   TARGET_FREE_KB=$(parse_size "${1#*=}") || exit 2; shift ;;
      --max-tier)
        [ $# -ge 2 ] || { warn "--max-tier 缺少参数"; exit 2; }
        MAX_TIER="$2"; shift 2 ;;
      --max-tier=*) MAX_TIER="${1#*=}"; shift ;;
      --dry-run|-n) DRY_RUN=1; shift ;;
      --force)      FORCE=1; shift ;;
      --quiet|-q)   QUIET=1; shift ;;
      --user-data)  USER_DATA=1; shift ;;
      --purge-memory) PURGE_MEM=1; shift ;;
      --allow-root) ALLOW_ROOT=1; shift ;;
      --json)       JSON=1; QUIET=1; shift ;;
      --machine)    MACHINE=1; shift ;;
      --scan)       MODE="scan"; shift ;;
      --status)     MODE="status"; shift ;;
      --apps)       MODE="apps"; shift ;;
      --storage)    MODE="storage"; shift ;;
      --volumes)    MODE="volumes"; shift ;;
      --version|-V) echo "diskautoclean $VERSION"; exit 0 ;;
      --help|-h)    usage; exit 0 ;;
      *) warn "未知参数: $1（用 --help 查看用法）"; exit 2 ;;
    esac
  done

  # GUI/脚本查询模式：不需要加锁，查完即走
  if [ "$MODE" = "status" ]; then do_status; exit 0; fi
  if [ "$MODE" = "scan" ];   then do_scan;   exit 0; fi
  if [ "$MODE" = "apps" ];   then do_apps;   exit 0; fi
  if [ "$MODE" = "storage" ]; then do_storage; exit 0; fi
  if [ "$MODE" = "volumes" ]; then volumes_json; printf '\n'; exit 0; fi

  case "$MAX_TIER" in 1|2|3) ;; *) warn "--max-tier 只能是 1/2/3"; exit 2 ;; esac

  if [ "$(id -u)" -eq 0 ] && [ "$ALLOW_ROOT" -eq 0 ]; then
    warn "请不要用 sudo/root 运行（会清理错用户）。如确需，请加 --allow-root。"
    exit 2
  fi

  # 防止并发运行
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    warn "已有另一个清理任务在运行，本次退出。"
    exit 0
  fi
  trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT INT TERM

  setup_log

  local f0
  f0=$(free_kb "$HOME")
  log ""
  log "=========== diskautoclean $(ts) ==========="
  log "可用空间: $(human "$f0") | 目标: $(human "$TARGET_FREE_KB") | 最高等级: $MAX_TIER$([ "$DRY_RUN" -eq 1 ] && echo ' | 演练模式')"
  emit_kv FREE_BEFORE "$f0"
  emit_kv TARGET "$TARGET_FREE_KB"

  if [ "${f0:-0}" -ge "$TARGET_FREE_KB" ] && [ "$FORCE" -eq 0 ]; then
    log "空间充足，无需清理。"
    do_status
    exit 0
  fi

  tier1
  if [ "$MAX_TIER" -ge 2 ] && ! should_stop; then tier2; fi
  if [ "$MAX_TIER" -ge 3 ] && ! should_stop; then tier3; fi
  [ "$PURGE_MEM" -eq 1 ] && purge_memory

  local f1 delta
  f1=$(free_kb "$HOME")
  delta=$((f1 - f0))
  log ""
  log "===== 结果 ====="
  [ "$DRY_RUN" -eq 1 ] && log "（演练模式：以上都没有真正删除）"
  log "处理条目: $DELETED_COUNT 个 | 预计释放: $(human "$FREED_KB")"
  log "可用空间: $(human "$f0") → $(human "$f1")（变化 $(human "$delta")）"
  if [ "${f1:-0}" -ge "$TARGET_FREE_KB" ]; then
    log "✅ 已达成目标：至少 $(human "$TARGET_FREE_KB") 可用空间。"
  else
    log "⚠️ 仍未达到目标。可尝试："
    log "   1) 加上 --max-tier 3 --user-data 清理废纸篓/iOS 备份/旧下载"
    log "   2) 运行 DiskCleaner/clean_disk.py --scan 查看其它可清理项"
    log "   3) 运行本脚本 --scan 或 DiskCleaner/clean_disk.py --big-files 500 找出大文件"
  fi
  emit_kv FREE_AFTER "$f1"
  if [ "$MACHINE" -eq 1 ]; then printf '@@DONE\t%s\t%s\n' "$FREED_KB" "$DELETED_COUNT"; fi
  exit 0
}

usage() {
  cat <<'EOF'
diskautoclean — macOS 自动磁盘清理，尽量保证至少 N GB 可用空间

用法:
  ./diskautoclean.sh [选项]

常用:
  --scan                只查看各清理项占用（不删除）
  --status              查看磁盘总览、内存、可用空间/目标达成情况
  --apps                查看每个应用占用（本体 + 用户数据）
  --storage             按 macOS「储存空间」方式显示分类占用（近似）
  --volumes             显示每个硬盘/卷的容量与使用
  --dry-run, -n         演练：显示会删什么，但不真正删除
  --target 10G          目标可用空间，默认 10G（支持 K/M/G/T）
  --max-tier 2          最高清理等级 1/2/3，默认 2
  --force               忽略“空间已充足”，直接按等级清理
  --user-data           允许第 3 级清理（废纸篓/iOS 备份/旧下载，慎用）
  --purge-memory        顺带执行 purge 释放非活跃内存
  --quiet, -q           只写日志，不输出到终端
  --json                以 JSON 输出（配合 --scan / --status，供 GUI 使用）
  --machine             输出 @@ 开头的机器可读进度行（供 GUI 使用）
  --help, -h            显示帮助

等级说明:
  1  安全：应用缓存、~/.cache、Xcode DerivedData、日志、崩溃报告
  2  开发缓存：npm/pnpm/pip/Homebrew/Go/Cargo/Gradle/Playwright 等
  3  用户数据：Xcode 归档、iOS 备份、废纸篓、下载文件夹（默认只报告）

日志: ~/Library/Logs/diskautoclean.log
EOF
}

main "$@"
