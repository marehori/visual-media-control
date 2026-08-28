import base64
import hashlib
import json
import pathlib
import socket
import struct
import subprocess
import sys
import time


PORT = 28543


def recv_exact(connection, count):
    data = b""
    while len(data) < count:
        chunk = connection.recv(count - len(data))
        if not chunk:
            raise RuntimeError("connection closed")
        data += chunk
    return data


def recv_frame(connection):
    first, second = recv_exact(connection, 2)
    opcode = first & 0x0F
    length = second & 0x7F
    if length == 126:
        length = struct.unpack("!H", recv_exact(connection, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", recv_exact(connection, 8))[0]
    mask = recv_exact(connection, 4) if second & 0x80 else None
    payload = bytearray(recv_exact(connection, length))
    if mask:
        for index in range(length):
            payload[index] ^= mask[index % 4]
    return opcode, bytes(payload)


def send_frame(connection, payload, opcode=1):
    payload = payload if isinstance(payload, bytes) else payload.encode("utf-8")
    header = bytes([0x80 | opcode])
    if len(payload) < 126:
        header += bytes([len(payload)])
    elif len(payload) < 65536:
        header += bytes([126]) + struct.pack("!H", len(payload))
    else:
        header += bytes([127]) + struct.pack("!Q", len(payload))
    connection.sendall(header + payload)


def expect_image(connection, expected_context):
    deadline = time.time() + 10
    while time.time() < deadline:
        opcode, payload = recv_frame(connection)
        if opcode != 1:
            continue
        message = json.loads(payload)
        if message.get("event") != "setImage" or message.get("context") != expected_context:
            continue
        assert message["payload"]["target"] == 0
        prefix = "data:image/png;base64,"
        assert message["payload"]["image"].startswith(prefix)
        png = base64.b64decode(message["payload"]["image"][len(prefix):])
        assert png[:8] == b"\x89PNG\r\n\x1a\n"
        width, height = struct.unpack("!II", png[16:24])
        assert (width, height) == (144, 144)
        return png
    raise AssertionError(f"no setImage for {expected_context}")


def expect_grid_gap_sync(connection, expected_contexts, expected_gap):
    remaining = set(expected_contexts)
    deadline = time.time() + 10
    while remaining and time.time() < deadline:
        opcode, payload = recv_frame(connection)
        if opcode != 1:
            continue
        message = json.loads(payload)
        context = message.get("context")
        if message.get("event") != "setSettings" or context not in remaining:
            continue
        assert message.get("payload", {}).get("gridGap") == expected_gap
        remaining.remove(context)
    if remaining:
        raise AssertionError(f"grid gap was not synchronized to: {sorted(remaining)}")


def main():
    plugin_process = None
    output_directory = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else None
    if output_directory is not None:
        output_directory.mkdir(parents=True, exist_ok=True)
    with socket.socket() as server:
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", PORT))
        server.listen(1)
        server.settimeout(15)
        if len(sys.argv) > 1:
            plugin_process = subprocess.Popen(
                [
                    sys.argv[1],
                    "-port", str(PORT),
                    "-pluginUUID", "com.marehori.nowplaying",
                    "-registerEvent", "registerPlugin",
                    "-info", "{}",
                ],
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
        connection, _ = server.accept()

    with connection:
        connection.settimeout(15)
        request = b""
        while b"\r\n\r\n" not in request:
            request += connection.recv(4096)
        headers = request.decode("latin-1").split("\r\n")
        key = next(line.split(":", 1)[1].strip() for line in headers if line.lower().startswith("sec-websocket-key:"))
        accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        connection.sendall(
            ("HTTP/1.1 101 Switching Protocols\r\n"
             "Upgrade: websocket\r\n"
             "Connection: Upgrade\r\n"
             f"Sec-WebSocket-Accept: {accept}\r\n\r\n").encode("ascii")
        )

        opcode, payload = recv_frame(connection)
        registration = json.loads(payload)
        assert opcode == 1
        assert registration == {
            "event": "registerPlugin",
            "uuid": "com.marehori.nowplaying",
        }

        send_frame(connection, json.dumps({
            "action": "com.marehori.nowplaying.playpause",
            "context": "test-context",
            "device": "test-device",
            "event": "willAppear",
            "payload": {"coordinates": {"column": 0, "row": 0}, "settings": {}},
        }))

        default_image = expect_image(connection, "test-context")

        send_frame(connection, json.dumps({
            "action": "com.marehori.nowplaying.playpause",
            "context": "test-context",
            "device": "test-device",
            "event": "didReceiveSettings",
            "payload": {
                "settings": {
                    "iconSize": 72,
                    "fillMode": "gradient",
                    "solidColor": "#FFFFFF",
                    "gradientStart": "#FF3366",
                    "gradientEnd": "#33CCFF",
                    "gradientAngle": 120,
                    "iconTransparency": 25,
                    "shadowEnabled": True,
                    "shadowColor": "#220044",
                    "shadowOpacity": 70,
                    "shadowBlur": 8,
                    "shadowSpread": 4,
                    "shadowOffsetX": -5,
                    "shadowOffsetY": 7,
                    "backdropEnabled": True,
                    "backdropColor": "#FFD400",
                    "backdropTransparency": 18,
                    "backdropSize": 88,
                    "backdropBlur": 14,
                }
            },
        }))
        customized_image = expect_image(connection, "test-context")
        assert customized_image != default_image
        if output_directory is not None:
            (output_directory / "customized-full.png").write_bytes(customized_image)

        send_frame(connection, json.dumps({
            "action": "com.marehori.nowplaying.playpause",
            "context": "property-inspector-context",
            "event": "sendToPlugin",
            "payload": {
                "actionContext": "test-context",
                "settings": {
                    "iconSize": 64,
                    "fillMode": "solid",
                    "solidColor": "#00FF88",
                    "gradientStart": "#FFFFFF",
                    "gradientEnd": "#7C5CFF",
                    "gradientAngle": 45,
                    "iconTransparency": 10,
                    "shadowEnabled": False,
                    "backdropEnabled": False,
                },
            },
        }))
        preview_image = expect_image(connection, "test-context")
        assert preview_image != customized_image

        send_frame(connection, json.dumps({
            "context": "test-context",
            "event": "willDisappear",
            "payload": {},
        }))

        grid_actions = [
            ("top-left", "com.marehori.nowplaying.grid.topleft"),
            ("top-right", "com.marehori.nowplaying.grid.topright"),
            ("bottom-left", "com.marehori.nowplaying.grid.bottomleft"),
            ("bottom-right", "com.marehori.nowplaying.grid.bottomright"),
        ]
        grid_images = {}
        for name, action in grid_actions:
            context = f"grid-{name}"
            send_frame(connection, json.dumps({
                "action": action,
                "context": context,
                "device": "test-device",
                "event": "willAppear",
                "payload": {
                    "coordinates": {"column": 0, "row": 0},
                    "settings": {"buttonFunction": "artwork"},
                },
            }))
            grid_images[name] = expect_image(connection, context)
            if output_directory is not None:
                (output_directory / f"grid-{name}.png").write_bytes(grid_images[name])

        send_frame(connection, json.dumps({
            "action": "com.marehori.nowplaying.grid.topleft",
            "context": "grid-top-left",
            "device": "test-device",
            "event": "didReceiveSettings",
            "payload": {
                "settings": {
                    "buttonFunction": "artwork",
                    "gridGap": 42,
                }
            },
        }))
        expect_grid_gap_sync(
            connection,
            ["grid-top-right", "grid-bottom-left", "grid-bottom-right"],
            42,
        )

        send_frame(connection, json.dumps({
            "action": "com.marehori.nowplaying.grid.topleft",
            "context": "grid-previous-control",
            "device": "test-device",
            "event": "willAppear",
            "payload": {
                "coordinates": {"column": 0, "row": 0},
                "settings": {"buttonFunction": "previous"},
            },
        }))
        previous_image = expect_image(connection, "grid-previous-control")
        assert previous_image != grid_images["top-left"]

        custom_png = (
            "data:image/png;base64,"
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZkL0AAAAASUVORK5CYII="
        )
        send_frame(connection, json.dumps({
            "action": "com.marehori.nowplaying.grid.topleft",
            "context": "grid-previous-control",
            "device": "test-device",
            "event": "didReceiveSettings",
            "payload": {
                "settings": {
                    "buttonFunction": "previous",
                    "customIconData": custom_png,
                    "customIconName": "test.png",
                    "iconSize": 68,
                    "iconTransparency": 15,
                    "shadowEnabled": True,
                    "shadowBlur": 4,
                    "backdropEnabled": True,
                }
            },
        }))
        custom_icon_image = expect_image(connection, "grid-previous-control")
        assert custom_icon_image != previous_image
        if output_directory is not None:
            (output_directory / "custom-icon.png").write_bytes(custom_icon_image)

        send_frame(connection, json.dumps({
            "action": "com.marehori.nowplaying.grid.bottomleft",
            "context": "grid-title-control",
            "device": "test-device",
            "event": "willAppear",
            "payload": {
                "coordinates": {"column": 0, "row": 0},
                "settings": {
                    "buttonFunction": "title",
                    "textContent": "titleArtist",
                    "textSize": 18,
                    "textFontFamily": "Georgia",
                    "textAutoFit": True,
                    "textFillMode": "gradient",
                    "textGradientStart": "#FFFFFF",
                    "textGradientEnd": "#FF55AA",
                    "textGradientAngle": 90,
                    "textAlignment": "center",
                    "textVerticalAlignment": "bottom",
                    "textBold": True,
                    "textOutlineEnabled": True,
                    "textOutlineColor": "#000000",
                    "textOutlineOpacity": 85,
                    "textOutlineWidth": 2,
                },
            },
        }))
        title_image = expect_image(connection, "grid-title-control")
        assert title_image != grid_images["bottom-left"]
        if output_directory is not None:
            (output_directory / "advanced-text.png").write_bytes(title_image)

        send_frame(connection, json.dumps({
            "action": "com.marehori.nowplaying.grid.topright",
            "context": "recovered-grid-context",
            "device": "test-device",
            "event": "keyDown",
            "payload": {"state": 0, "settings": {}},
        }))
        recovered_grid_image = expect_image(connection, "recovered-grid-context")
        assert recovered_grid_image != grid_images["top-right"]

        # FIFINE/StreamDock compatibility case: the native plugin starts after
        # the action is already visible, so no willAppear is delivered. The
        # plugin must recover the context from the next key event.
        send_frame(connection, json.dumps({
            "action": "com.marehori.nowplaying.playpause",
            "context": "recovered-context",
            "device": "test-device",
            "event": "keyDown",
            "payload": {"state": 0, "settings": {}},
        }))
        expect_image(connection, "recovered-context")

        send_frame(connection, b"", opcode=8)
        print("PASS: full key, grid, custom icon, advanced text, synchronized gap, and recovery")

    if plugin_process is not None:
        return_code = plugin_process.wait(timeout=5)
        assert return_code == 0, f"plugin exit code: {return_code}"


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise
