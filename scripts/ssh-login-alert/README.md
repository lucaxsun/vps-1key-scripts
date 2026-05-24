## 安装方式

请将下面命令中的：



### 方式一：推荐方式，下载后执行

推荐使用这种方式。脚本会保存到 `/root/install-ssh-login-tg-alert.sh`，方便后续检查、重复执行、卸载或彻底卸载。

```bash
curl -fsSL https://raw.githubusercontent.com/lucaxsun/vps-1key-scripts/main/scripts/ssh-login-alert/install.sh -o /root/install-ssh-login-tg-alert.sh
chmod +x /root/install-ssh-login-tg-alert.sh
bash /root/install-ssh-login-tg-alert.sh
```

如果你的系统没有 `curl`，可以使用 `wget`：

```bash
wget -O /root/install-ssh-login-tg-alert.sh https://raw.githubusercontent.com/lucaxsun/vps-1key-scripts/main/scripts/ssh-login-alert/install.sh
chmod +x /root/install-ssh-login-tg-alert.sh
bash /root/install-ssh-login-tg-alert.sh
```

---

### 方式二：在线一键运行

这种方式不会把安装脚本保存到 `/root/install-ssh-login-tg-alert.sh`，适合临时快速安装。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/lucaxsun/vps-1key-scripts/main/scripts/ssh-login-alert/install.sh)
```

注意：如果使用这种方式，后续想卸载时，需要再次从 GitHub 调用脚本。

---

## 安装过程

执行安装脚本后，会要求输入：

```text
Telegram Bot Token
Telegram Chat ID
服务器公网 IP，可留空自动检测
```

其中服务器公网 IP 建议手动填写，尤其是 VPS 上使用了 WARP、Proton VPN、WireGuard 或其他代理分流的情况。

如果留空，脚本会自动尝试从云厂商 Metadata 和外部公网 IP API 获取公网 IP。

---

## 卸载方式

### 普通卸载

普通卸载会删除：

```text
/etc/pam.d/sshd 中的 PAM 接入行
/usr/local/bin/ssh-login-alert.sh
```

但会保留 Telegram 配置文件：

```text
/root/.tg-ssh-alert.env
```

如果你是使用“方式一：下载后执行”安装的，可以运行：

```bash
bash /root/install-ssh-login-tg-alert.sh uninstall
```

如果你是使用“方式二：在线一键运行”安装的，可以运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/lucaxsun/vps-1key-scripts/main/scripts/ssh-login-alert/install.sh) uninstall
```

---

### 彻底卸载

彻底卸载会删除：

```text
/etc/pam.d/sshd 中的 PAM 接入行
/usr/local/bin/ssh-login-alert.sh
/root/.tg-ssh-alert.env
```

如果你是使用“方式一：下载后执行”安装的，可以运行：

```bash
bash /root/install-ssh-login-tg-alert.sh purge
```

如果你是使用“方式二：在线一键运行”安装的，可以运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/lucaxsun/vps-1key-scripts/main/scripts/ssh-login-alert/install.sh) purge
```

---

## 安装后检查

可以使用下面命令检查是否安装成功：

```bash
ls -l /usr/local/bin/ssh-login-alert.sh
grep -n ssh-login-alert.sh /etc/pam.d/sshd
ls -l /root/.tg-ssh-alert.env
```

正常情况下应该看到：

```text
/usr/local/bin/ssh-login-alert.sh 存在且可执行
/etc/pam.d/sshd 中存在 pam_exec 接入行
/root/.tg-ssh-alert.env 权限为 600
```

---

## 测试方法

安装完成后，脚本会先发送一条测试消息。

然后请不要关闭当前 SSH 窗口，重新打开一个新的 SSH 窗口登录 VPS。

如果 Telegram 收到类似下面的通知，说明安装成功：

```text
🔐 SSH 登录通知

主机: example-host
公网IP: 1.2.3.4
IP来源: Manual config
用户: root
来源IP: 8.8.8.8
终端: ssh
时间: 2026-05-24 16:30:00 CST
```
