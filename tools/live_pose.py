"""LIVE WEBCAM PUPPET helper (roadmap 21). The webcam (or a recorded pose file) -> MediaPipe PoseLandmarker world landmarks
per frame -> a local socket to Kine. Kine (scripts/live_puppet.gd) listens on 127.0.0.1 at a port it picks and starts this
script with that port; this script connects to it and sends one JSON line per frame:
    {"i": frame index, "t": capture time (unix s), "w": [[x, y, z] x 33] or null (no body in view)}
The world landmarks are MediaPipe's: metres, the hips' midpoint at 0, y DOWN (the same layout tools/see_video.py writes).
A camera failure is sent as {"error": "..."} and the script exits. Nothing else crosses the socket.

    python tools/live_pose.py --port 50123 [--camera 0] [--model D:/pose_models/pose_landmarker_heavy.task]
    python tools/live_pose.py --port 50123 --replay <pose.json>     (the test's fake sender: a recorded sequence in real time)

It exits when Kine closes the socket, when the replay ends, or on Ctrl+C."""
import argparse
import json
import socket
import sys
import time


def connect(port):
    # Kine opens the socket before it starts this script, but retry for a while in case the listener is slow
    end = time.time() + 15.0
    while True:
        try:
            return socket.create_connection(("127.0.0.1", port), timeout=5.0)
        except OSError:
            if time.time() > end:
                raise
            time.sleep(0.1)


class Sender:
    def __init__(self, sock):
        self.sock = sock
        self.sock.settimeout(None)

    def send(self, obj):
        # False when Kine has gone (it closed the socket): the caller stops
        try:
            self.sock.sendall((json.dumps(obj) + "\n").encode("utf-8"))
            return True
        except OSError:
            return False


def replay(sender, path):
    d = json.load(open(path))
    frames = d["frames"]
    start = time.time()
    for i, f in enumerate(frames):
        due = start + float(f["t"])
        now = time.time()
        if due > now:
            time.sleep(due - now)
        if not sender.send({"i": i, "t": time.time(), "w": f.get("world")}):
            return
    # the end: Kine sees the socket close once this returns


def camera(sender, args):
    import cv2
    import mediapipe as mp
    from mediapipe.tasks import python as mpt
    from mediapipe.tasks.python import vision

    cap = cv2.VideoCapture(args.camera)
    if not cap.isOpened():
        sender.send({"error": "no webcam at index %d (is it in use by another app?)" % args.camera})
        return
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)   # the newest frame, not a queue of old ones: less lag
    det = vision.PoseLandmarker.create_from_options(vision.PoseLandmarkerOptions(
        base_options=mpt.BaseOptions(model_asset_path=args.model), running_mode=vision.RunningMode.VIDEO,
        num_poses=1))
    t0 = time.monotonic()
    last_ms = -1
    i = 0
    stats_t = time.time()
    stats_n = 0
    while True:
        ok, img = cap.read()
        tcap = time.time()
        if not ok:
            sender.send({"error": "the webcam stopped giving frames"})
            break
        ms = max(last_ms + 1, int((time.monotonic() - t0) * 1000))   # MediaPipe's VIDEO mode wants rising timestamps
        last_ms = ms
        res = det.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB,
                                            data=cv2.cvtColor(img, cv2.COLOR_BGR2RGB)), ms)
        w = None
        if res.pose_world_landmarks:
            w = [[round(q.x, 4), round(q.y, 4), round(q.z, 4)] for q in res.pose_world_landmarks[0]]
        if not sender.send({"i": i, "t": tcap, "w": w}):
            break
        i += 1
        stats_n += 1
        if time.time() - stats_t >= 5.0:
            print("LIVE %.1f fps (camera frames tracked)" % (stats_n / (time.time() - stats_t)), file=sys.stderr)
            stats_t = time.time()
            stats_n = 0
    cap.release()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--camera", type=int, default=0)
    ap.add_argument("--model", default="D:/pose_models/pose_landmarker_heavy.task")
    ap.add_argument("--replay", default="")
    a = ap.parse_args()
    sock = connect(a.port)
    sender = Sender(sock)
    try:
        if a.replay:
            replay(sender, a.replay)
        else:
            try:
                camera(sender, a)
            except ImportError as e:
                sender.send({"error": "the tracker needs opencv-python and mediapipe (pip install mediapipe opencv-python): %s" % e})
            except Exception as e:   # a model or camera failure: one line to Kine, never a silent exit
                sender.send({"error": "the tracker failed: %s" % e})
    except KeyboardInterrupt:
        pass
    finally:
        sock.close()


if __name__ == "__main__":
    main()
