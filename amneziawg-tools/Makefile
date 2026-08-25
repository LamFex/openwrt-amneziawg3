include $(TOPDIR)/rules.mk

PKG_NAME:=amneziawg3-tools
PKG_VERSION:=3.1.20260812
PKG_RELEASE:=2

PKG_SOURCE:=amneziawg-tools-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/amnezia-vpn/amneziawg-tools/tar.gz/refs/tags/v$(PKG_VERSION)?
PKG_HASH:=dbd8ce0748d835d18f30bb76720246b7bfc80bd09cd17c379b1c59f683a18493
PKG_BUILD_DIR:=$(BUILD_DIR)/amneziawg-tools-$(PKG_VERSION)

PKG_MAINTAINER:=AWG OpenWrt3 contributors
PKG_LICENSE:=GPL-2.0-only AND Apache-2.0
PKG_LICENSE_FILES:=COPYING

PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

MAKE_PATH:=src
MAKE_VARS += PLATFORM=linux
MAKE_FLAGS += WIREGUARD_TOOLS_VERSION=$(PKG_VERSION)

define Package/amneziawg3-tools
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=AmneziaWG 3.1 control and OpenWrt integration tools
  URL:=https://github.com/amnezia-vpn/amneziawg-tools
  DEPENDS:=+amneziawg3-go +bash +ip-full +netifd +nftables-json +resolveip
endef

define Package/amneziawg3-tools/description
  Namespaced AmneziaWG 3.1 control tools, a userspace-only awg-quick
  compatibility command, and the netifd protocol integration.
endef

define Package/amneziawg3-tools/conffiles
/etc/amnezia/amneziawg3/
endef

define Package/amneziawg3-tools/install
	$(INSTALL_DIR) $(1)/usr/libexec/amneziawg3
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/wg $(1)/usr/libexec/amneziawg3/awg
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/wg-quick/linux.bash $(1)/usr/libexec/amneziawg3/awg-quick
	$(INSTALL_BIN) ./files/amneziawg3-key-helper $(1)/usr/libexec/amneziawg3/amneziawg3-key-helper
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/awg3 $(1)/usr/bin/awg3
	$(INSTALL_BIN) ./files/awg-quick3 $(1)/usr/bin/awg-quick3
	$(INSTALL_BIN) ./files/amneziawg3_watchdog $(1)/usr/bin/amneziawg3_watchdog
	$(INSTALL_DIR) $(1)/lib/netifd/proto
	$(INSTALL_BIN) ./files/amneziawg3.sh $(1)/lib/netifd/proto/amneziawg3.sh
	$(INSTALL_DIR) $(1)/etc/amnezia/amneziawg3
endef

define Package/amneziawg3-tools/prerm
#!/bin/sh
init_path="$${IPKG_INSTROOT}/etc/init.d/amneziawg3"
init_target="/usr/libexec/amneziawg3/amneziawg3.init"
if [ -z "$${IPKG_INSTROOT}" ] && [ -L "$$init_path" ] && \
	[ "$$(readlink "$$init_path" 2>/dev/null)" = "$$init_target" ]; then
	"$$init_path" stop || {
		echo "Could not stop all AmneziaWG 3.1 interfaces; APK may continue removal, verify residual processes and links" >&2
		exit 1
	}
fi
endef

$(eval $(call BuildPackage,amneziawg3-tools))
