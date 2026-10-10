TARGET := iphone:clang:latest:15.0
ARCHS = arm64e
THEOS_PACKAGE_SCHEME = rootless
# a backboardd restart is a userspace reboot: nothing is restarted automatically, reboot userspace after installing

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Backport162BBD

Backport162BBD_FILES = Tweak.x
Backport162BBD_CFLAGS = -fobjc-arc -Wall -Werror -Wno-deprecated-declarations
Backport162BBD_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
