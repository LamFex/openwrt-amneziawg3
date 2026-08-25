include $(TOPDIR)/rules.mk

PKG_NAME:=amneziawg3-go
PKG_VERSION:=3.1.20260814
PKG_RELEASE:=2

PKG_SOURCE:=amneziawg-go-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/amnezia-vpn/amneziawg-go/tar.gz/refs/tags/v$(PKG_VERSION)?
PKG_HASH:=c146a640c18468caac71fd158c02a94afcf6beadb5fd585c092bf55cbdefdbff
PKG_BUILD_DIR:=$(BUILD_DIR)/amneziawg-go-$(PKG_VERSION)

PKG_MAINTAINER:=AWG OpenWrt3 contributors
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1

GO_PKG:=github.com/amnezia-vpn/amneziawg-go/v3
GO_PKG_BUILD_PKG:=$(GO_PKG)
GO_PKG_LDFLAGS_X:=main.Version=$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/amneziawg3-go
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=AmneziaWG 3.1 userspace implementation
  URL:=https://github.com/amnezia-vpn/amneziawg-go
  DEPENDS:=@TARGET_mediatek_filogic $(GO_ARCH_DEPENDS) +kmod-tun
  CONFLICTS:=amneziawg-go
endef

define Package/amneziawg3-go/description
  Userspace AmneziaWG 3.1 implementation. This package intentionally uses
  TUN and does not install or replace an AmneziaWG kernel module.
endef

define Package/amneziawg3-go/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/amneziawg-go $(1)/usr/bin/amneziawg-go
	$(INSTALL_DIR) $(1)/usr/libexec/amneziawg3
	$(INSTALL_BIN) ./files/amneziawg3.init $(1)/usr/libexec/amneziawg3/amneziawg3.init
endef

define Package/amneziawg3-go/preinst
#!/bin/sh
init_path="$${IPKG_INSTROOT}/etc/init.d/amneziawg3"
init_target="/usr/libexec/amneziawg3/amneziawg3.init"
if [ -e "$$init_path" ] || [ -L "$$init_path" ]; then
	current_target="$$(readlink "$$init_path" 2>/dev/null || true)"
	if [ "$$current_target" != "$$init_target" ]; then
		echo "Refusing to replace existing $$init_path" >&2
		exit 1
	fi
fi
endef

define Package/amneziawg3-go/postinst
#!/bin/sh
init_path="$${IPKG_INSTROOT}/etc/init.d/amneziawg3"
init_target="/usr/libexec/amneziawg3/amneziawg3.init"
mkdir -p "$${IPKG_INSTROOT}/etc/init.d"
if [ -e "$$init_path" ] || [ -L "$$init_path" ]; then
	current_target="$$(readlink "$$init_path" 2>/dev/null || true)"
	if [ "$$current_target" != "$$init_target" ]; then
		echo "Refusing to replace existing $$init_path" >&2
		exit 1
	fi
else
	ln -s "$$init_target" "$$init_path"
fi
endef

define Package/amneziawg3-go/prerm
#!/bin/sh
init_path="$${IPKG_INSTROOT}/etc/init.d/amneziawg3"
init_target="/usr/libexec/amneziawg3/amneziawg3.init"
if [ -L "$$init_path" ] && \
	[ "$$(readlink "$$init_path" 2>/dev/null)" = "$$init_target" ]; then
	if [ -z "$${IPKG_INSTROOT}" ]; then
		"$$init_path" stop
		"$$init_path" disable
	fi
	rm -f "$$init_path"
fi
endef

$(eval $(call GoBinPackage,amneziawg3-go))
$(eval $(call BuildPackage,amneziawg3-go))
