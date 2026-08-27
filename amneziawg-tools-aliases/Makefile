include $(TOPDIR)/rules.mk

PKG_NAME:=amneziawg3-tools-aliases
PKG_VERSION:=3.1.20260812
PKG_RELEASE:=2

PKG_MAINTAINER:=AWG OpenWrt3 contributors
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/amneziawg3-tools-aliases
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=Optional standard command aliases for AmneziaWG 3.1
  DEPENDS:=+amneziawg3-tools
  CONFLICTS:=amneziawg-tools
  PKGARCH:=all
endef

define Package/amneziawg3-tools-aliases/description
  Installs /usr/bin/awg and /usr/bin/awg-quick aliases. Do not install this
  package when an AWG2 amneziawg-tools package is present.
endef

define Build/Compile
endef

define Build/Configure
endef

define Package/amneziawg3-tools-aliases/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(LN) awg3 $(1)/usr/bin/awg
	$(LN) awg-quick3 $(1)/usr/bin/awg-quick
endef

$(eval $(call BuildPackage,amneziawg3-tools-aliases))
