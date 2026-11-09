#!/bin/bash
# ============================================================
#  双击这个文件 → 把网页课件拷到 U 盘
#  只拷「运行要用」的东西（约 478 MB），不拷 .git 和历史备份
#  固定目标见下面 FIXED_DEST；那个盘没插时会自动弹窗让你另选
# ============================================================
cd "$(dirname "$0")" || exit 1
SRC="$(pwd)"

# ★ 固定目标：平时插这个 U 盘双击就行
FIXED_DEST="/Volumes/NO NAME/2026数字产品设计实践/unity-course"

clear
echo "=================================================="
echo "   课件打包到 U 盘"
echo "   来源：$SRC"
echo "=================================================="
echo ""

# ---------- 1) 定目标 ----------
DEST=""
if [ -n "$1" ]; then
    DEST="$1"                                  # 命令行/测试时直接给完整目标
elif [ -n "$PACK_TARGET" ]; then
    DEST="$PACK_TARGET"
elif [ -d "/Volumes/NO NAME" ]; then           # 固定那个 U 盘在，直接用
    DEST="$FIXED_DEST"
    echo "目标（固定）：$DEST"
else
    echo "没找到固定目标 /Volumes/NO NAME，改成自动找盘…"
    CAND=""
    N=0
    for v in /Volumes/*; do
        [ -d "$v" ] || continue
        name="$(basename "$v")"
        [ "$name" = "Macintosh HD" ] && continue
        [ -w "$v" ] || continue
        CAND="$v"; N=$((N+1))
    done
    if [ "$N" -eq 1 ]; then
        DEST="$CAND/unity-course"
        echo "检测到可移动磁盘：$CAND"
        printf "就拷到 %s ？[Y/n] " "$DEST"
        read -r ans
        case "$ans" in
            n|N) DEST="" ;;
        esac
    fi
    if [ -z "$DEST" ]; then
        echo "请在弹出的窗口里选择 U 盘（或任意目标文件夹）…"
        PICK="$(osascript -e 'POSIX path of (choose folder with prompt "选择 U 盘")' 2>/dev/null)"
        PICK="${PICK%/}"
        [ -n "$PICK" ] && DEST="$PICK/unity-course"
    fi
    if [ -z "$DEST" ]; then
        echo ""
        echo "没有选中目标，已取消。"
        read -n 1 -s -r -p "按任意键关闭…"
        exit 1
    fi
fi

DEST="${DEST%/}"
DEST_ROOT="$(dirname "$DEST")"
FOLDER="$(basename "$DEST")"

if [ -d "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
    echo ""
    echo "注意：$DEST 里已经有东西，会覆盖同名文件（不多删）。"
    printf "继续？[Y/n] "
    read -r ans
    case "$ans" in
        n|N) echo "已取消。"; read -n 1 -s -r -p "按任意键关闭…"; exit 1 ;;
    esac
fi
mkdir -p "$DEST" || { echo "建目录失败：$DEST"; read -n 1 -s -r -p "按任意键关闭…"; exit 1; }

echo ""
echo "正在拷贝到：$DEST"
echo ""

# ---------- 2) 拷 HTML ----------
cnt=0
for f in 课件*.html; do
    case "$(basename "$f")" in _bak_*) continue ;; esac
    [ -f "$f" ] || continue
    cp -p "$f" "$DEST/" && cnt=$((cnt+1))
done
for f in index.html 参考代码手册.html 大作业说明.html knowledge_graph.html 课程教学计划_2026.html; do
    [ -f "$f" ] && cp -p "$f" "$DEST/" && cnt=$((cnt+1))
done
echo "  网页 $cnt 个"

# ---------- 3) 拷图片与依赖 ----------
if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude='.DS_Store' images/ "$DEST/images/"
    rsync -a --exclude='.DS_Store' vendor/ "$DEST/vendor/"
else
    cp -R images "$DEST/" 2>/dev/null
    cp -R vendor "$DEST/" 2>/dev/null
    find "$DEST" -name '.DS_Store' -delete 2>/dev/null
fi
echo "  图片与依赖已拷完"

# ---------- 4) 拷 Windows 服务器脚本 ----------
srv=0
for f in server.ps1 start_server.bat 启动课件服务.bat; do
    if [ -f "$f" ]; then cp -p "$f" "$DEST/" && srv=$((srv+1)); fi
done
echo "  服务器脚本 $srv 个"

echo ""
echo "--------------------------------------------------"
printf "完成。合计 %s\n" "$(du -sh "$DEST" | awk '{print $1}')"
echo "U 盘上的位置：$DEST"
echo "（同名文件：没改动的自动跳过，改动过的覆盖；U 盘上多出来的旧文件不会删）"

# ---------- 5) 在 U 盘根目录放一个「一键启动」 ----------
if [ -w "$DEST_ROOT" ] && [ "$srv" -gt 0 ]; then
    LAUNCHER="$DEST_ROOT/启动课件.bat"
    printf '@echo off\r\ncd /d "%%~dp0%s"\r\ncall "启动课件服务.bat"\r\n' "$FOLDER" > /tmp/_launcher_utf8.bat
    if command -v iconv >/dev/null 2>&1; then
        iconv -f UTF-8 -t GBK /tmp/_launcher_utf8.bat > "$LAUNCHER" 2>/dev/null
    fi
    if [ -s "$LAUNCHER" ]; then
        echo "U 盘根目录已放「启动课件.bat」——插上后双击它就行"
    fi
    rm -f /tmp/_launcher_utf8.bat
fi

echo ""
echo "教室电脑（Windows）上：插 U 盘 → 双击根目录「启动课件.bat」"
echo "（或进 $FOLDER 文件夹双击「启动课件服务.bat」，一样的）"
echo "学生访问窗口里显示的 http://IP:8000/"
echo "--------------------------------------------------"

# 拷贝后自检：有没有漏掉引用了的图片
miss=0
if command -v python3 >/dev/null 2>&1; then
    miss=$(cd "$DEST" && python3 - <<'PY' 2>/dev/null
import glob,os,re,urllib.parse,unicodedata
N=lambda s:unicodedata.normalize('NFC',s)
ref=set()
for f in glob.glob('*.html'):
    s=open(f,encoding='utf-8',errors='ignore').read()
    for m in re.finditer(r'(?:src|href)="((?:images|vendor)/[^"]+)"',s):
        ref.add(N(urllib.parse.unquote(m.group(1)).split('?')[0]))
have={N(os.path.relpath(os.path.join(r,f),'.').replace('\\','/')) for r,_,fs in os.walk('.') for f in fs}
print(len([p for p in ref if p not in have]))
PY
)
    echo "自检：页面引用但没拷到的图片 $miss 张（多数是还没拍的缺图占位，属正常）"
fi

[ -z "$1" ] && open "$DEST" 2>/dev/null
echo ""
read -n 1 -s -r -p "按任意键关闭这个窗口…"
