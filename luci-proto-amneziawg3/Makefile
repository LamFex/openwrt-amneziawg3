include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for AmneziaWG 3.1
LUCI_DEPENDS:=@TARGET_mediatek_filogic +amneziawg3-tools +ucode
LUCI_PKGARCH:=all

PKG_VERSION:=3.1.20260814
PKG_RELEASE:=2
PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)
PKG_LICENSE:=Apache-2.0
LUCI_MAINTAINER:=AWG OpenWrt3 contributors

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
