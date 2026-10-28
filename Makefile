TARGET = iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = appconduitd

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WatchMessages18

WatchMessages18_FILES = Tweak.x WM18Log.m
WatchMessages18_FRAMEWORKS = Foundation
WatchMessages18_CFLAGS = -fobjc-arc

ifeq ($(WM18_DEBUG),1)
WatchMessages18_CFLAGS += -DWM18_DEBUG=1
endif

include $(THEOS_MAKE_PATH)/tweak.mk
