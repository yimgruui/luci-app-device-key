include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-device-key
PKG_VERSION:=1.1.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=yimgruui

LUCI_TITLE:=LuCI app: per-device SSH key
LUCI_DESCRIPTION:=Generate an SSH key pair on the device, claim the private key once, manage authorized keys.
LUCI_DEPENDS:=+luci-compat +dropbear +openssh-keygen +openssl-util
LUCI_PKGARCH:=all

define Package/luci-app-device-key/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
rm -f /tmp/luci-indexcache /tmp/luci-indexcache.* 2>/dev/null
mkdir -p /etc/device-key /tmp/device-key 2>/dev/null
chmod 700 /etc/device-key /tmp/device-key 2>/dev/null
chmod 755 /usr/sbin/device-key 2>/dev/null
exit 0
endef

define Package/luci-app-device-key/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
case "$$1" in upgrade|failed-upgrade) exit 0 ;; esac
# 卸载时不让用户被锁在门外：本机生成的私钥早已被领取，这里只清临时目录
rm -rf /tmp/device-key 2>/dev/null
exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
