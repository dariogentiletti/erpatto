# Er Patto: turns a video the user gave into a clip the addon can play: frame sheets (1024x1024 TGA, 12 frames a
# second) plus the sound as ogg. A tall (phone) video gives tall frames, a wide one wide frames, 28 to a sheet.
# Usage: python3 tools/make_clip.py VIDEO START SECONDS OUTDIR NAME [preview.mp4]
#   e.g. python3 tools/make_clip.py GHIACIOLETTO_LVL.MOV 13.65 6 Media/livello ghiacciolino
# Prints the line for News.DING_CLIPS. With a preview path, also writes a small mp4 of the cut to check by eye.
import json, os, subprocess, sys, tempfile
from PIL import Image

src, start, secs, outdir, name = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4], sys.argv[5]
preview = sys.argv[6] if len(sys.argv) > 6 else None
FPS, SHEET = 12, 1024
os.makedirs(outdir, exist_ok=True)

probe = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                            "stream=width,height:stream_side_data=rotation", "-of", "json", src]))
st = probe["streams"][0]
w, h = st["width"], st["height"]
rot = 0
for sd in st.get("side_data_list", []):
    rot = int(sd.get("rotation", 0) or 0)
if abs(rot) % 180 == 90:
    w, h = h, w
tall = h > w
fw, fh = (144, 256) if tall else (256, 144)
cols, rows = SHEET // fw, SHEET // fh
per = cols * rows
frames = int(round(secs * FPS))

tmp = tempfile.mkdtemp()
# (the game shows them a bit darker than a phone: a touch of light and colour)
vf = f"fps={FPS},scale={fw}:{fh}:force_original_aspect_ratio=increase,crop={fw}:{fh},eq=brightness=0.03:contrast=1.08:saturation=1.1"
subprocess.check_call(["ffmpeg", "-v", "error", "-y", "-ss", str(start), "-t", str(secs), "-i", src, "-vf", vf,
                       "-frames:v", str(frames), os.path.join(tmp, "f%04d.png")])
pics = sorted(p for p in os.listdir(tmp) if p.endswith(".png"))
frames = len(pics)
sheets = (frames + per - 1) // per
for s in range(sheets):
    img = Image.new("RGB", (SHEET, SHEET))
    for k in range(per):
        i = s * per + k
        if i >= frames:
            break
        img.paste(Image.open(os.path.join(tmp, pics[i])).convert("RGB"), ((k % cols) * fw, (k // cols) * fh))
    img.save(os.path.join(outdir, f"{name}{s + 1}.tga"), compression="tga_rle")

# the sound: as loud as the other clips, in and out softly
fade = max(0.0, secs - 0.35)
af = f"afade=t=in:st=0:d=0.12,afade=t=out:st={fade:.2f}:d=0.35,loudnorm=I=-12:TP=-1:LRA=11"
subprocess.check_call(["ffmpeg", "-v", "error", "-y", "-ss", str(start), "-t", str(secs), "-i", src, "-map", "0:a:0",
                       "-af", af, "-ac", "2", "-ar", "44100", "-c:a", "libvorbis", "-q:a", "4",
                       os.path.join(outdir, name + ".ogg")])
if preview:
    subprocess.check_call(["ffmpeg", "-v", "error", "-y", "-framerate", str(FPS), "-i", os.path.join(tmp, "f%04d.png"),
                           "-i", os.path.join(outdir, name + ".ogg"), "-vf", "scale=iw*2:ih*2:flags=neighbor",
                           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", preview])
print(f'{{ sheets = {sheets}, frames = {frames}, fps = {FPS}, fw = {fw}, fh = {fh}, cols = {cols}, rows = {rows} }}')
