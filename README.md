# luci-app-device-key

为每一台路由器**在设备上**生成一把独立的 SSH 密钥，私钥只在 LuCI 页面显示一次，
设备从此只保留公钥。适合批量刷同一份固件、又不想让所有机器共用一把私钥的场景。

## 功能

- **设备端生成**：`ssh-keygen` 在路由器上生成 ed25519 密钥对，私钥不经过任何服务器。
- **一次性领取**：私钥只存在于 `/tmp/device-key`（tmpfs，重启即失），领取后立即删除。
- **默认不生成**：安装后不会自动运行，必须由用户在页面上点击生成。
- **二次确认**：生成 / 领取 / 吊销 / 改公钥，都要重新输入 root 密码。
- **手动公钥**：保留原「SSH 密钥」页的手动粘贴能力，每行一个公钥。
- **只保留公钥**：设备长期只保存 `/etc/device-key/pub` 和 `authorized_keys`，
  本插件添加的公钥带 `device-key@` 注释，吊销时只删这些行，不影响手动公钥。
- **中英双语**：`po/zh_Hans`、`po/zh_Hant`，其余语言回退英文。

## 安全模型

| 风险 | 处理 |
| --- | --- |
| 私钥泄露 | 私钥仅存在于 tmpfs，领取后 `rm`，页面 `Cache-Control: no-store` |
| 无人值守的会话被利用 | 每个写操作都要重新输入 root 密码（`openssl passwd` 校验 `/etc/shadow`） |
| CSRF | 表单带 LuCI `token`，由 dispatcher 校验 |
| 误锁死 | 只增删带 `device-key@` 注释的条目；手动公钥永不被删除 |
| 隐私 | 日志只记指纹，不记私钥 |

> 私钥一旦领走，设备无法再次生成同一把；丢失只能重新生成并替换。

## 依赖

```
luci-compat  dropbear  openssh-keygen  openssl-util
```

- `openssh-keygen`：生成 ed25519 密钥（dropbear 自带的 `dropbearkey` 不能直接产出 OpenSSH 格式私钥）。
- `openssl-util`：用 `openssl passwd -5/-6` 校验 root 密码，不需要 python 或 libcrypt 绑定。

## 安装

编译进固件（推荐）：

```sh
# 在 OpenWrt/ImmortalWrt 源码树中
echo "CONFIG_PACKAGE_luci-app-device-key=y" >> .config
```

或单独编译 ipk：

```sh
make package/luci-app-device-key/compile V=s
```

装好后刷新 LuCI，菜单在 **系统 → 管理权 → 设备 SSH 密钥**。

## 使用

1. 打开页面，点「生成新密钥对」，输入 root 密码。
2. 状态变成“已生成，等待领取”，点「显示一次私钥」，再次输入 root 密码。
3. 复制私钥保存到本地，`chmod 600 id_ed25519`。
4. 登录：`ssh -i id_ed25519 root@192.168.11.1`（页面会按 dropbear 的实际端口显示，默认 22）。

命令行等价操作：

```sh
device-key gen          # 生成（替换上一把设备密钥）
device-key status       # KEY=VALUE 状态
device-key claim        # 打印私钥并删除
device-key revoke       # 吊销设备密钥
device-key getkeys      # 查看 authorized_keys
device-key setkeys      # 从 stdin 覆盖 authorized_keys
```

## 与官方「SSH-Keys」页的关系

本插件的菜单只**新增**自己的页面，不会在运行时修改 `luci-mod-system` 的菜单文件
（那需要 python/jsonfilter，且升级时会被覆盖）。

如果希望彻底用本页替换官方「SSH-Keys」页，在构建固件时删除
`/usr/share/luci/menu.d/luci-mod-system.json` 里的 `admin/system/admin/sshkeys` 条目即可
（本项目的配套构建仓库在 `scripts/patch-feeds.sh` 里做这件事）。
「SSH 访问」（dropbear 端口、密码登录开关）页面保持不变。

## 兼容性

- 页面用 Lua 控制器 + LuCI 模板实现，依赖 `luci-compat`，适用于 19.07 ~ 25.12 的 Lua LuCI；
  已在 ImmortalWrt 25.12 上验证。
- 需要 `ssh-keygen`（openssh-client）与 `openssl`，二者在 OpenWrt 官方源里都有。
- 21.02+ 的 JS 版 LuCI 同样可以打开该 Lua 页面（走 luci-compat 的 uwsgi 通道）。

## 卸载

`prerm` 只清理 `/tmp/device-key`，不会动 `/etc/dropbear/authorized_keys`，
避免卸载后把自己锁在门外。需要清理时手动执行 `device-key revoke`。

## 许可证

MIT
