#!/usr/bin/env python3
"""Generate the four deck images in the REAL Searce brand system (extracted from
the Searce BQ-Graph POV deck): editorial / minimal, blue family (#0064FF /
navy #002659), Poppins typography, white cards with subtle borders.

Outputs (RGBA, transparent bg) into deck/images/:
  arch-conceptual.png · arch-technical.png · before-after.png · cost-insight.png
"""
from __future__ import annotations
import os, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

# ── Searce palette ──
BLUE    = (0, 100, 255)     # #0064FF primary
BLUEDK  = (0, 81, 203)      # #0051CB
NAVY    = (0, 38, 89)       # #002659 headlines
INK     = (32, 33, 36)
BODY    = (71, 85, 105)     # #475569
SUB     = (95, 99, 104)     # #5F6368
MUTED   = (154, 160, 166)   # #9AA0A6
CARDLN  = (224, 230, 246)   # card border
CALLOUT = (230, 240, 255)   # #E6F0FF
PANEL   = (244, 247, 251)
GRAYFILL= (236, 239, 243)
WHITE   = (255, 255, 255)

FD = os.path.join(os.path.dirname(__file__), "..", "fonts")
def _f(w): return os.path.join(FD, f"Poppins-{w}.ttf")
PR, PM, PS, PB, PX = _f("Regular"), _f("Medium"), _f("SemiBold"), _f("Bold"), _f("ExtraBold")

ICONS = "/Users/sureya.sathiamoorthi/Desktop/home/icon-library/GCP/google-cloud-legacy-icons"
OUT = os.path.join(os.path.dirname(__file__), "..", "images")
os.makedirs(OUT, exist_ok=True)

def font(p, s): return ImageFont.truetype(p, s)
def tw(d, t, f):
    b = d.textbbox((0, 0), t, font=f); return b[2] - b[0], b[3] - b[1]
def ctext(d, cx, y, t, f, fill):
    w, _ = tw(d, t, f); d.text((cx - w / 2, y), t, font=f, fill=fill)

def shadow_card(base, x, y, w, h, r, fill, line=None, lw=2, blur=16, alpha=34, dy=8):
    sh = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([x, y + dy, x + w, y + dy + h], radius=r,
                                         fill=(20, 40, 80, alpha))
    base.alpha_composite(sh.filter(ImageFilter.GaussianBlur(blur)))
    d = ImageDraw.Draw(base)
    d.rounded_rectangle([x, y, x + w, y + h], radius=r, fill=fill,
                        outline=line, width=lw if line else 0)

def paste_icon(base, path, x, y, size):
    ic = Image.open(path).convert("RGBA").resize((size, size), Image.LANCZOS)
    base.alpha_composite(ic, (int(x), int(y)))

# ════════════════════════════════════════════════ conceptual flow
def make_conceptual():
    W, H = 2560, 1040
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    f_num = font(PX, 86); f_hd = font(PS, 40); f_bd = font(PR, 27)
    steps = [
        ("01", "A file lands", ["Monthly supplier file dropped", "into the cloud landing zone"]),
        ("02", "It runs itself", ["Ingest · unify · KPIs ·", "anomalies — no human"]),
        ("03", "One unified model", ["Rail + UK road + EU road in", "a single source of truth"]),
        ("04", "Answers, instantly", ["Dashboards + ask in plain", "English, grounded in data"]),
    ]
    cw, ch, y0 = 556, 600, 230
    gap = (W - 160 - cw * 4) / 3; x0 = 80
    for i, (num, hd, lines) in enumerate(steps):
        x = x0 + i * (cw + gap)
        shadow_card(img, x, y0, cw, ch, 26, WHITE, line=CARDLN, lw=2)
        d.text((x + 44, y0 + 40), num, font=f_num, fill=BLUE)
        d.line([x + 48, y0 + 188, x + 130, y0 + 188], fill=BLUE, width=5)
        d.text((x + 46, y0 + 250), hd, font=f_hd, fill=NAVY)
        for j, ln in enumerate(lines):
            d.text((x + 46, y0 + 330 + j * 42), ln, font=f_bd, fill=BODY)
        if i < 3:
            ax = x + cw; ay = y0 + ch / 2
            d.line([ax + 18, ay, ax + gap - 22, ay], fill=BLUE, width=5)
            d.polygon([(ax + gap - 6, ay), (ax + gap - 24, ay - 12), (ax + gap - 24, ay + 12)], fill=BLUE)
    img.save(os.path.join(OUT, "arch-conceptual.png")); print("conceptual ok")

# ════════════════════════════════════════════════ technical (Google Cloud ref)
def make_technical():
    W, H = 2560, 1080
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    p = lambda *a: os.path.join(ICONS, *a)
    BORDER = (224, 230, 246)
    f_word = font(PS, 38); f_grp = font(PS, 24); f_lab = font(PS, 28)
    f_sub = font(PR, 22); f_bq = font(PS, 30); f_chip = font(PS, 25)
    d.rounded_rectangle([40, 40, 2520, 1040], radius=18, fill=WHITE, outline=BORDER, width=2)
    cx0, cy0 = 92, 88
    for e in [(-26, -2, -2, 22), (-12, -16, 18, 16), (6, -2, 32, 22)]:
        d.ellipse([cx0 + e[0], cy0 + e[1], cx0 + e[2], cy0 + e[3]], fill=BLUE)
    d.rectangle([cx0 - 26, cy0 + 8, cx0 + 32, cy0 + 22], fill=BLUE)
    d.text((140, 66), "Google Cloud", font=f_word, fill=NAVY)
    GY0, GY1 = 175, 995
    for name, gx0, gx1 in [("INGESTION", 80, 900), ("TRANSFORMATION", 940, 1760), ("SERVING", 1800, 2480)]:
        d.rounded_rectangle([gx0, GY0, gx1, GY1], radius=14, fill=PANEL, outline=BORDER, width=2)
        d.text((gx0 + 28, GY0 + 22), name, font=f_grp, fill=SUB)
    CY = 595
    def card(cx, icon, label, sub, cw=210, ch=290):
        x, top = cx - cw / 2, CY - ch / 2
        d.rounded_rectangle([x, top, x + cw, top + ch], radius=14, fill=WHITE, outline=BORDER, width=2)
        paste_icon(img, icon, cx - 50, top + 30, 100)
        lines = label.split("\n"); by = top + (150 if len(lines) == 2 else 160)
        for i, ln in enumerate(lines): ctext(d, cx, by + i * 36, ln, f_lab, NAVY)
        ctext(d, cx, by + len(lines) * 36 + 6, sub, f_sub, SUB)
        return cx - cw / 2, cx + cw / 2
    cs_l, cs_r = card(225, p("cloud_storage", "cloud_storage.png"), "Cloud Storage", "landing · 3 feeds")
    ea_l, ea_r = card(490, p("eventarc", "eventarc.png"), "Eventarc", "on finalize")
    cr_l, cr_r = card(755, p("cloud_run", "cloud_run.png"), "Cloud Run", "ingest service")
    wf_l, wf_r = card(1090, p("workflows", "workflows.png"), "Workflows", "orchestration")
    bx0, bx1, by0, by1 = 1250, 1720, CY - 145, CY + 145
    d.rounded_rectangle([bx0, by0, bx1, by1], radius=14, fill=WHITE, outline=BLUE, width=2)
    paste_icon(img, p("bigquery", "bigquery.png"), bx0 + 26, by0 + 26, 64)
    d.text((bx0 + 104, by0 + 40), "BigQuery", font=f_bq, fill=NAVY)
    for i, (lab, col) in enumerate([("RAW", MUTED), ("STG", BLUE), ("MART", NAVY)]):
        lx = bx0 + 30 + i * 150
        d.rounded_rectangle([lx, by0 + 150, lx + 118, by0 + 220], radius=10, fill=col)
        ctext(d, lx + 59, by0 + 170, lab, f_chip, WHITE)
        if i < 2:
            d.line([lx + 118, by0 + 185, lx + 144, by0 + 185], fill=SUB, width=3)
            d.polygon([(lx + 150, by0 + 185), (lx + 138, by0 + 178), (lx + 138, by0 + 192)], fill=SUB)
    lk_l, lk_r = card(1945, p("looker", "looker.png"), "Looker", "LookML semantic")
    ca_l, ca_r = card(2275, p("vertexai", "vertexai.png"), "Conversational\nAnalytics", "Gemini", cw=330)
    def conn(x1, x2, y=CY):
        d.line([x1, y, x2 - 14, y], fill=SUB, width=3)
        d.polygon([(x2, y), (x2 - 14, y - 9), (x2 - 14, y + 9)], fill=SUB)
    conn(cs_r, ea_l); conn(ea_r, cr_l); conn(cr_r, wf_l)
    conn(wf_r, bx0); conn(bx1, lk_l); conn(lk_r, ca_l)
    img.save(os.path.join(OUT, "arch-technical.png")); print("technical ok")

# ════════════════════════════════════════════════ before / after
def make_before_after():
    W, H = 2560, 1240
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    f_item = font(PR, 35); f_lab = font(PB, 42)
    pw, ph, ly = 1080, 980, 180
    gap_mid = W - 160 - pw * 2
    # BEFORE (muted)
    shadow_card(img, 80, ly, pw, ph, 28, (240, 242, 245), line=CARDLN, lw=2)
    d.rounded_rectangle([80, ly, 80 + pw, ly + 96], radius=28, fill=(120, 130, 140))
    d.rectangle([80, ly + 60, 80 + pw, ly + 96], fill=(120, 130, 140))
    d.text((124, ly + 26), "BEFORE", font=f_lab, fill=WHITE)
    before = ["Three disconnected spreadsheets", "Manual consolidation by an analyst",
              "One feed viewed at a time", "Static Power BI — look, can’t ask",
              "~6 days per monthly refresh"]
    for i, t in enumerate(before):
        yy = ly + 168 + i * 150
        d.ellipse([130, yy + 6, 168, yy + 44], outline=(120, 130, 140), width=6)
        d.line([139, yy + 25, 159, yy + 25], fill=(120, 130, 140), width=6)
        d.text((200, yy), t, font=f_item, fill=(70, 78, 88))
    # AFTER (blue)
    ax = 80 + pw + gap_mid
    shadow_card(img, ax, ly, pw, ph, 28, BLUE)
    d.rounded_rectangle([ax, ly, ax + pw, ly + 96], radius=28, fill=BLUEDK)
    d.rectangle([ax, ly + 60, ax + pw, ly + 96], fill=BLUEDK)
    d.text((ax + 44, ly + 26), "AFTER", font=f_lab, fill=WHITE)
    after = ["One file drop — nothing else", "Self-running cloud pipeline",
             "Rail + UK road + EU road unified", "Ask in plain English (Gemini)",
             "Minutes, fully hands-off"]
    for i, t in enumerate(after):
        yy = ly + 168 + i * 150
        d.ellipse([ax + 50, yy + 6, ax + 88, yy + 44], fill=WHITE)
        d.line([ax + 59, yy + 26, ax + 67, yy + 34], fill=BLUE, width=6)
        d.line([ax + 67, yy + 34, ax + 81, yy + 16], fill=BLUE, width=6)
        d.text((ax + 120, yy), t, font=f_item, fill=WHITE)
    # medallion
    mcx, mcy, R = W / 2, ly + ph / 2, 162
    d.ellipse([mcx - R, mcy - R, mcx + R, mcy + R], fill=WHITE, outline=BLUE, width=16)
    f_s = font(PS, 36); f_b = font(PX, 40)
    sw, _ = tw(d, "6 DAYS", f_s)
    d.text((mcx - sw / 2, mcy - 96), "6 DAYS", font=f_s, fill=MUTED)
    d.line([mcx - sw / 2 - 8, mcy - 70, mcx + sw / 2 + 8, mcy - 70], fill=MUTED, width=6)
    d.line([mcx, mcy - 34, mcx, mcy + 2], fill=BLUE, width=12)
    d.polygon([(mcx - 22, mcy - 6), (mcx + 22, mcy - 6), (mcx, mcy + 24)], fill=BLUE)
    ctext(d, mcx, mcy + 40, "MINUTES", f_b, NAVY)
    img.save(os.path.join(OUT, "before-after.png")); print("before/after ok")

# ════════════════════════════════════════════════ cost insight
def make_cost_insight():
    import matplotlib; matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib import font_manager as fm
    reg = fm.FontProperties(fname=PR); semi = fm.FontProperties(fname=PS); bold = fm.FontProperties(fname=PB)
    labels = ["Rail\n(DB Cargo)", "Road UK", "Road EU\n(imports)"]
    vals = [6.57, 20.37, 55.31]
    cols = [(0/255, 38/255, 89/255), (154/255, 160/255, 166/255), (0/255, 100/255, 255/255)]
    fig, ax = plt.subplots(figsize=(11, 6.2), dpi=240); fig.patch.set_alpha(0)
    bars = ax.bar(labels, vals, color=cols, width=0.62, zorder=3)
    for b, v in zip(bars, vals):
        ax.text(b.get_x() + b.get_width() / 2, v + 1.2, f"£{v:.2f}", ha="center", va="bottom",
                fontproperties=bold, fontsize=21, color=(0.0, 0.15, 0.35))
    ax.set_ylabel("Cost per tonne (£)", fontproperties=semi, fontsize=18, color=(0.1, 0.15, 0.25))
    ax.set_ylim(0, 66)
    ax.tick_params(axis="x", labelsize=17, length=0)
    for l in ax.get_xticklabels(): l.set_fontproperties(reg); l.set_color((0.1, 0.12, 0.16))
    for l in ax.get_yticklabels(): l.set_fontproperties(reg); l.set_color((0.45, 0.48, 0.52))
    for s in ["top", "right"]: ax.spines[s].set_visible(False)
    ax.spines["left"].set_color((0.85, 0.87, 0.9)); ax.spines["bottom"].set_color((0.85, 0.87, 0.9))
    ax.grid(axis="y", color=(0.92, 0.93, 0.96), zorder=0)
    ax.annotate("8.4× rail", xy=(2, 55.31), xytext=(1.18, 60), fontproperties=bold, fontsize=21,
                color=(0, 100/255, 255/255),
                arrowprops=dict(arrowstyle="->", color=(0, 100/255, 255/255), lw=2.4))
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, "cost-insight.png"), transparent=True, bbox_inches="tight")
    plt.close(fig); print("cost insight ok")

if __name__ == "__main__":
    make_conceptual(); make_technical(); make_before_after(); make_cost_insight()
    print("ALL DONE ->", os.path.abspath(OUT))
