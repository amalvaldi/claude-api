# Kiro 账号池管理系统 (Claude API 修改版) 从零部署指南

本文档基于 `zhangrenhua/claude-api` (AWS Kiro / Amazon Q Developer API 代理与账号池管理系统) 的实际部署排错过程整理。涵盖了从全新 Ubuntu 服务器到最终服务上线的完整步骤，并特别收录了常见的环境与依赖报错解决方案。

---

## 目录
1. [基础系统环境准备与网络优化](#1-基础系统环境准备与网络优化)
2. [MySQL 数据库初始化](#2-mysql-数据库初始化)
3. [安装最新版 Go 语言环境](#3-安装最新版-go-语言环境)
4. [拉取项目与前端依赖修复](#4-拉取项目与前端依赖修复)
5. [编译服务端程序](#5-编译服务端程序)
6. [配置与启动服务](#6-配置与启动服务)
7. [常见错误 (FAQ) 汇总](#7-常见错误-faq-汇总)

---

## 1. 基础系统环境准备与网络优化

在全新的 Ubuntu 服务器上，首先需要安装必要的系统工具。

### 1.1 优化系统软件源（解决下载卡死问题）
**现象：** 在执行 `apt update` 或 `apt install` 时，终端长时间卡在 `[Waiting for headers]`，且 `curl` 测试官方源超时。
**原因：** 默认的 Ubuntu 官方源节点（如 `archive.ubuntu.com`）对当前服务器网络不通畅。
**解决：** 将官方源替换为稳定的备用源（如 kernel.org），并清理缓存：

```bash
# 备份并替换源
sed -i.bak 's/[archive.ubuntu.com/mirrors.kernel.org/g](https://archive.ubuntu.com/mirrors.kernel.org/g)' /etc/apt/sources.list

# 清理缓存并更新列表
apt clean
apt update

1.2 安装基础依赖
apt install -y git mysql-server curl wget
(注：如果安装过程中弹出粉灰色界面提示 "Daemons using outdated libraries"，直接按 回车键 (Enter) 采用默认选项重启服务即可。)

2. MySQL 数据库初始化
# 进入 MySQL 控制台 (直接回车)
mysql -u root
在 MySQL 终端中依次执行以下 SQL 语句（请自行修改 your_password 为你的数据库密码）：
-- 创建支持中文字符集的数据库
CREATE DATABASE kiro_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 创建专用数据库用户并设置密码
CREATE USER 'kiro_user'@'localhost' IDENTIFIED BY 'Carrot0416.';

-- 赋予该用户操作 kiro_db 的所有权限
GRANT ALL PRIVILEGES ON kiro_db.* TO 'kiro_user'@'localhost';

-- 刷新权限并退出
FLUSH PRIVILEGES;
EXIT;


3. 安装最新版 Go 语言环境
注意：千万不要使用 apt install golang-go！
该项目使用了较新的 Go 特性，要求 Go 版本 >= 1.24.0。Ubuntu 自带的 apt 源通常版本过老 (1.18)，会导致后续编译出现 invalid go version 错误。

3.1 卸载旧版本（如有）
apt remove -y golang-go golang-1.18-go

3.2 手动安装 Go (以 1.26.2 为例)
# 下载 Go 安装包
wget [https://go.dev/dl/go1.26.2.linux-amd64.tar.gz](https://go.dev/dl/go1.26.2.linux-amd64.tar.gz)

# 清理旧目录并解压新版本到 /usr/local
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.26.2.linux-amd64.tar.gz

# 临时配置环境变量（让当前终端立即生效）
export PATH=$PATH:/usr/local/go/bin

# 验证安装是否成功
go version
(为保证下次登录依然有效，建议将 export PATH=$PATH:/usr/local/go/bin 添加到 ~/.bashrc 文件末尾。)
4. 拉取项目与前端依赖修复
该项目自带 Web 管理面板，如果直接编译会提示缺少静态文件。必须通过自带脚本下载前端依赖。

cd ~
git clone [https://github.com/zhangrenhua/claude-api.git](https://github.com/zhangrenhua/claude-api.git)
cd claude-api

4.2 修复缺失的前端目录 (核心排错)
现象： 运行 ./download.sh 时提示 Failed to create the file... No such file or directory。
原因： 下载脚本不会自动创建多级父目录。
解决： 手动创建缺失的目录，并赋予脚本执行权限。

# 创建缺失的静态资源目录
mkdir -p frontend/vendor/js frontend/vendor/css frontend/vendor/fonts

# 赋予脚本执行权限
chmod +x download.sh build.sh claude_start.sh

# 手动复制项目自带的 css 文件（防止脚本中 URL 报错）
cp github.min.css frontend/vendor/css/
cp github-dark.min.css frontend/vendor/css/

# 运行下载脚本
./download.sh

5. 编译服务端程序
执行官方提供的统一构建脚本：

./build.sh

⚠️ 重点注意 Wails CLI 报错：
如果在日志最后看到以下内容：

[SUCCESS] Server [linux/amd64] -> /root/claude-api/dist/server/claude-server-linux-amd64.tar.gz
[ERROR] Wails CLI 未安装

请直接忽略该错误！
Wails 是用于打包桌面端客户端（Windows/Mac）的工具。我们仅需部署 Linux 服务器端，看到 [SUCCESS] Server... 就意味着核心服务已经打包完成了。

5.1 解压服务端程序
将打包好的服务端程序解压到当前目录：


tar -xzf dist/server/claude-server-linux-amd64.tar.gz -C ./

6. 配置与启动服务
6.1 修改配置文件
项目根目录下提供了一个 MySQL 专属的配置模板，我们需要基于它进行修改。

# 复制模板文件
cp config-mysql-example.yaml config.yaml

# 编辑配置文件
nano config.yaml

在文件中找到 database / mysql 相关配置段，修改为你第 2 步设置的信息：

dbname: kiro_db

username: kiro_user

password: your_password

保存并退出 (Ctrl+O -> Enter -> Ctrl+X)。

chmod +x claude-server
./claude_start.sh




