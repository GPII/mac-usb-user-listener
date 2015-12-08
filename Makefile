CC=clang # or gcc

FRAMEWORKS:= -framework Foundation -framework DiskArbitration
LIBRARIES:= -lobjc

SOURCE=mac-usb-user-listener.m

CFLAGS=-Wall -Werror -g -v $(SOURCE)
LDFLAGS=$(LIBRARIES) $(FRAMEWORKS)
OUT=-o mac-usb-user-listener

all:
	$(CC) $(CFLAGS) $(LDFLAGS) $(OUT)

clean:
	rm -fr mac-usb-listener.dSYM
	rm mac-usb-listener
