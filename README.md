# 京东云「亚瑟」AX1800 Pro r4546 免拆机刷 OpenWrt

## 0. 刷机前准备

## 0.0 机器配置

| 项目 | 规格 |
|---|---|
| 设备 | 京东云无线宝 AX1800 Pro（代号「亚瑟」） |
| 型号 | `RE-SS-01` |
| SoC | Qualcomm IPQ6000 四核 Cortex-A53 @1.2GHz |
| 内存 | 512 MB DDR3 |
| 存储 | 64 GB eMMC |
| 无线 | QCN5022（2.4G）+ QCN5052（5G），WiFi 6，驱动 `ath11k` |
| 交换芯片 | QCA8075，4 × 千兆 |
| 其他 | USB 3.0 × 1 |

### 0.1 硬件

| 物品 | 说明 | 必需 |
|---|---|---|
| 京东云 AX1800 Pro 及电源 | 型号：`RE-SS-01` 本文使用 `悦享版 64G` | ✅ |
| 带有线网口的电脑 | **必须有线**，不能用 WiFi 刷。Windows / macOS / Linux 均可，本文使用 Windows，其他系统请自行适配脚本 | ✅ |
| 网线 | 连接电脑 ↔ 路由器 LAN 口 | ✅ |
| 回形针 | 掰直捅 RST（其他针状物体也可） | ✅ |

### 0.2 软件

| 软件 | 用途 | 来源 |
|---|---|---|
| 浏览器 | 打开原厂后台、U-Boot Web、LuCI | 系统自带（Chrome / Edge 都行）|
| **Telnet 客户端** | 刷 U-Boot 阶段全靠它 | Windows 自带功能，`控制面板 → 程序 → 启用或关闭 Windows 功能 → Telnet 客户端` |
| **PowerShell** | 改本机 IP、放行防火墙、跑传输脚本 | 系统自带（建议用管理员窗口）|
| `recv.ps1` | 接收路由器备份（3.3 节，路由器 → 电脑）| 根目录 |
| `send-file.ps1` | 把 U-Boot 文件推给路由器（4.2 节，电脑 → 路由器）| 根目录 |

### 0.3 固件

| 文件 | 大小 | 用途 | 校验值 |
|---|---|---|---|
| `uboot-flashfiles-ss-01.bin` | **655360** 字节 | 替换原厂 U-Boot | SHA256 `0fb6879f2bdb1bdc48f0dbcbbd8383ef3328f88c957601ce1e2363ffec647311` |
| `gpt-AX1800Pro-rootfs2048M.bin` | **17408** 字节 | 扩容分区表（rootfs 60 MiB → 2 GiB） | MD5 `4e68b53b2646a4824aed74a4f5b656ea` |
| `libwrt-factory.bin` | **117243904** 字节 | OpenWrt 固件 | SHA256 `5241f47317f7148c1dba997d74775ef3343ecbc4fdb21c690ccf43bbd70fd6d6` |

**务必核对这三个文件是否无误**

### 0.4 存储空间

| 用途 | 空间 |
|---|---|
| 本机 eMMC 备份（整体镜像 `ax1800-1111m.img` + 还原时可能用到的分区备份） | 约 **1.1 GiB** |
| 电脑上留档同一份镜像 | 约 **1.1 GiB** |
| 三个待刷文件 | 约 **112 MiB** |

## 1. 准备

下载[刷机套件](https://github.com/WorldHim/jdc-ax1800pro-openwrt/releases/download/v1.0/jdc-ax1800pro-openwrt.7z)并解压备用

后续所有命令行操作均在仓库根目录下执行

## 2. 打开 Telnet

### 2.0 断网

原厂固件联网会接收下发热补丁，可能把 Telnet 服务干掉甚至改配置。

### 2.1 注入

登录路由器后台，按 `F12` 打开浏览器开发者工具控制台并输入以下内容：

```javascript
var s = document.createElement('script');
s.src = 'https://gwrt.uk/wp-content/uploads/2026/06/telnet.mini.js?t=' + Date.now();
document.body.appendChild(s);
```

执行完成后网页应出现如图弹窗，点击 `开启 Telnet`。

### 2.2 连接

```sh
telnet 192.168.68.1
# 用户名：root，密码：后台登录密码
```

你应该会看到 `BusyBox` `Welcome to JDBox Router` 等字样。

tips: **断电重启后 telnetd 不会自启**。


## 3. 备份

### 3.1 准备

```sh
mkdir -p /mnt/mmcblk0p27
mount -t ext4 /dev/mmcblk0p27 /mnt/mmcblk0p27
df -h /mnt/mmcblk0p27
```

确保 `df -h` 显示可用空间充足后进行下一步备份。

### 3.2 本机备份

```sh
dd if=/dev/mmcblk0 bs=1M count=1111 of=/mnt/mmcblk0p27/ax1800-1111m.img
```

> 还原：
>
> ```sh
> dd if=/mnt/mmcblk0p27/ax1800-1111m.img of=/dev/mmcblk0 bs=1M count=1111
> ```

### 3.3 电脑备份

1. **记录源文件 MD5**

```sh
md5sum /mnt/mmcblk0p27/ax1800-1111m.img
wc -c < /mnt/mmcblk0p27/ax1800-1111m.img
```

`1111 MiB` 的精确镜像大小应该是 **1164967936** 字节。

2. **电脑放行入站**（管理员：PowerShell）

```powershell
New-NetFirewallRule -DisplayName "AX1800 flash 8000" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow -Profile Any
```

3. **电脑起接收端**

```powershell
.\recv.ps1  # 详细参数请自行查阅文末
```

4. **路由器发送镜像**

```sh
cd /mnt/mmcblk0p27
sz=$(wc -c < ax1800-1111m.img)
{ echo ax1800-1111m.img; echo $sz; cat ax1800-1111m.img; } | busybox nc <电脑IP> 8000
```

5. **校验**

```powershell
certutil -hashfile .\backup\ax1800-1111m.img MD5
(Get-Item .\backup\ax1800-1111m.img).Length
```

MD5 应等于第 1 步路由器上算出来的值，大小为 **1164967936**。

> 查询 eMMC 寿命：
> 
> ```sh
> var="$(cat /sys/kernel/debug/mmc0/mmc0\:0001/ext_csd)"
> eol=${var:534:2}; slc=${var:536:2}; mlc=${var:538:2}
> echo "EOL:0x$eol SLC:0x$slc MLC:0x$mlc"
> ```
>
> 我这台输出 `EOL:0x01 SLC:0x0b MLC:0x02`：
>
> - `EOL 0x01` → Normal，寿命未耗尽
> - `SLC 0x0b` → 已超标称寿命（按主机写入模式放大的等效磨损）
> - `MLC 0x02` → 实际磨损 **20%**，还剩 80%


## 4. 刷 U-Boot

### 4.1 传文件

```powershell
.\send-file.ps1 -File .\firmware\uboot-flashfiles-ss-01.bin  # 详细参数请自行查阅文末
```

路由器上：

```sh
cd /tmp
nc <电脑IP> 8000 > uboot.bin
```

`nc` 收到 EOF 自动退出，提示符回来就传完了。

tips: **跑 4.2 之前先把 3.3 的接收端关掉**，否则会占用端口。

### 4.2 校验

```sh
cd /tmp
wc -c uboot.bin            # 必须 655360
md5sum uboot.bin           # 必须 2266697f5106c170a91e283adf7a3d19
hexdump -C -n 4 uboot.bin  # 必须 7f 45 4c 46（ELF32 LSB）
```

### 4.3 写入

```sh
# 清空 A/B 槽配置，强制固定从槽 0 启动
dd if=/dev/zero of=/dev/mmcblk0p2 bs=1k count=256
dd if=/dev/zero of=/dev/mmcblk0p3 bs=1k count=256
sync

# 写入两个 U-Boot 槽
dd if=/tmp/uboot.bin of=/dev/mmcblk0p13 bs=64k
dd if=/tmp/uboot.bin of=/dev/mmcblk0p14 bs=64k
sync

# 校验
md5sum /dev/mmcblk0p13
md5sum /dev/mmcblk0p14
# 两个都必须等于 2266697f5106c170a91e283adf7a3d19
# 不匹配就重新执行 不要断电 不要断电 不要断电！！！
```

## 5. 进 U-Boot Web

### 5.1 电脑设置

网卡设为静态 IP **`192.168.1.2 / 255.255.255.0`**，**不设网关**（U-Boot 不提供 DHCP）。

### 5.2 按键操作

1. **拔电源**；
2. **按住 RST 不放，插入电源**；
3. 观察指示灯：**红灯闪烁 → 蓝灯常亮**；
4. **蓝灯常亮后过 2–3 秒松手**；
5. 浏览器打开 `http://192.168.1.1`，此时应当能打开 U-Boot Web 界面。

## 6. 刷 GPT

1. 打开 `http://192.168.1.1/img.html`，选择 `gpt-AX1800Pro-rootfs2048M.bin`，点击「更新 IMG」；
2. 稍等片刻后确认没有报错后即可断开电源。

## 7. 刷固件

1. 重复 5.2 操作进入 U-Boot；
2. 打开 `http://192.168.1.1/`，选择 `libwrt-factory.bin`，点击「更新固件」。


## 8. 成功

访问 `http://192.168.1.1/`，用户名为 root，密码为空，直接点击登录即可。


### 9. 改回防火墙


```powershell
Remove-NetFirewallRule -DisplayName "AX1800 flash 8000"
```

---

## 附：常用信息速查

### 灯态

| 灯 | 含义 |
|---|---|
| 红灯闪 6 次 → 蓝灯常亮 | U-Boot 就绪 |
| 蓝灯闪 → 绿灯亮 3 秒 → 绿灯常亮 | 固件启动成功 |
| 红灯常亮 | 引导失败 |
| 完全不亮 | 电源故障 |

### 默认地址

| 阶段 | 地址 |
|---|---|
| 原厂系统 | `192.168.68.1` |
| U-Boot Web | `192.168.1.1`（电脑设 `192.168.1.2/24`，无网关） |
| 第三方固件 | 看网卡拿到的默认网关 |

### 各脚本参数

| 脚本 | 参数名 | 参数类型 | 用途 |
|---|---|---|---|
| `recv.ps1` | `-OutDir` | `string` | 输出目录 |
| `recv.ps1` | `-BindIp` | `string` | 绑定 IP |
| `recv.ps1` | `-Port` | `int` | 绑定端口 |
| `recv.ps1` | `-Expect` | `int` | 接收文件数 |
| `recv.ps1` | `-IdleSec` | `int` | 超时时间 |
| `send-file.ps1` | `-File` | `string` | 发送的文件 |
| `send-file.ps1` | `-BindIp` | `string` | 绑定 IP |
| `send-file.ps1` | `-Port` | `int` | 绑定端口 |
| `send-file.ps1` | `-Seconds` | `int` | 超时时间 |

---

## 参考资料与致谢

### 教程

1. [gwrt.uk《京东云亚瑟免拆开启 Telnet 教程（4.5.3.r4546）》](https://gwrt.uk/jdc-arthur-telnet-4546.html)
2. [8477667](https://www.right.com.cn/forum/thread-8477667-1-1.html)（V-2333）
3. 恩山 [8477903](https://www.right.com.cn/forum/thread-8477903-1-1.html)（rogueboy《新手刷机完全版》）
4. 恩山 [8494030](https://www.right.com.cn/forum/thread-8494030-1-1.html)
5. 数码罗记 [京东云无线宝 AX1800Pro 亚瑟 RE-SS-01 第三方OpenWrt刷机记录](https://godsun.pro/blog/jdc-ax1800pro-flash.html)
6. 数码罗记 [京东云盒 IPQ6018 刷机指南](https://gwrt.uk/jdcloud-ipq6018-flash-guide.html)
6. lgs2007m（咖啡猫）《分区备份 + TTL 双分区刷机 + 回原厂 + USB 救砖教程》
7. 小猫佩奇、XOS（gwrt 文中致谢） 

### 固件

| 文件 | 来源 | 下载 | 校验值 |
|---|---|---|---|
| `uboot-flashfiles-ss-01.bin` | [chenxin527/uboot-ipq60xx-emmc-build](https://github.com/chenxin527/uboot-ipq60xx-emmc-build) | [uboot-ipq60xx-emmc-jdcloud_re-ss-01-260102.153309.bin](https://github.com/chenxin527/uboot-ipq60xx-emmc-build/releases/download/26.01.02-15.33.09/uboot-ipq60xx-emmc-jdcloud_re-ss-01-260102.153309.bin) | `sha256:0fb6879f2bdb1bdc48f0dbcbbd8383ef3328f88c957601ce1e2363ffec647311` |
| `gpt-AX1800Pro-rootfs2048M.bin` | [京东云盒 IPQ6018 刷机指南](https://gwrt.uk/jdcloud-ipq6018-flash-guide.html) | [gpt-AX1800Pro-rootfs2048M.bin](https://godsun.pro/wp-content/uploads/flash-files/gpt-AX1800Pro-rootfs2048M.bin) | `md5:4e68b53b2646a4824aed74a4f5b656ea` |
| `libwrt-factory.bin` | [xiaofu2415/JDCloud-AX1800-Pro-RE-SS-01](https://github.com/xiaofu2415/JDCloud-AX1800-Pro-RE-SS-01) | [libwrt-qualcommax-ipq60xx-jdcloud_re-ss-01-squashfs-factory.bin](https://github.com/xiaofu2415/JDCloud-AX1800-Pro-RE-SS-01/releases/download/re-ss-01-4-1/libwrt-qualcommax-ipq60xx-jdcloud_re-ss-01-squashfs-factory.bin) | `sha256:5241f47317f7148c1dba997d74775ef3343ecbc4fdb21c690ccf43bbd70fd6d6` |

---

*本文基于真实的刷机过程整理，命令与数据均来自实机实测。刷机有风险，操作前请确保已完成完整备份。*
*部分代码由 AI 生成*

---

本文采用 [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/deed.zh-hans) 许可协议。转载请注明出处！