include $(TOPDIR)/rules.mk

PKG_NAME:=amneziawg3
PKG_VERSION:=3.1.20260814
PKG_RELEASE:=2
PKGARCH:=all

PKG_MAINTAINER:=AWG OpenWrt3 contributors
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/amneziawg3
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=AmneziaWG 3.1 for OpenWrt
  DEPENDS:=+amneziawg3-go +amneziawg3-tools +luci-proto-amneziawg3
endef

define Package/amneziawg3/description
  Meta-package for the AmneziaWG 3.1 userspace runtime, OpenWrt netifd
  integration, namespaced tools, and LuCI protocol support.
endef

define Build/Compile
endef

define Package/amneziawg3/install
	true
endef

$(eval $(call BuildPackage,amneziawg3))
