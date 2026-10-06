TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SpeakerPicker

SpeakerPicker_FILES = SpeakerPicker.c
SpeakerPicker_CFLAGS = -Wno-deprecated-declarations
SpeakerPicker_LDFLAGS = -lobjc
SpeakerPicker_FRAMEWORKS = CoreFoundation CydiaSubstrate

include $(THEOS_MAKE_PATH)/tweak.mk
